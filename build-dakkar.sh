#!/bin/bash
set -e

if [ -z "$USER" ];then
    export USER="$(id -un)"
fi
export LC_ALL=C

## set defaults

rom_fp="$(date +%y%m%d)"

myname="$(basename "$0")"
if [[ $(uname -s) = "Darwin" ]];then
    jobs=$(sysctl -n hw.ncpu)
elif [[ $(uname -s) = "Linux" ]];then
    jobs=$(nproc)
fi

chromium="66.0.3359.158"

## handle command line arguments
read -p "Do you want to sync? " choice
read -p "Do you want to rebuild chromium? " choice_chromium

function help() {
    cat <<EOF
Syntax:

  $myname [-j 2] <rom type> <variant>...

Options:

  -j   number of parallel make workers (defaults to $jobs)

ROM types:

  aosp80
  aosp81
  aosp90
  carbon
  lineage
  rr
  pixel
  crdroid
  mokee
  aicp
  aokp
  slim
  aex

Variants are dash-joined combinations of (in order):
* processor type
  * "arm" for ARM 32 bit
  * "arm64" for ARM 64 bit
* A or A/B partition layout ("aonly" or "ab")
* GApps selection
  * "vanilla" to not include GApps
  * "gapps" to include opengapps
  * "go" to include gapps go
  * "floss" to include floss
* SU selection ("su" or "nosu")

for example:

* arm-aonly-vanilla-nosu
* arm64-ab-gapps-su
EOF
}

function get_rom_type() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            aosp80)
                mainrepo="https://android.googlesource.com/platform/manifest"
                mainbranch="android-vts-8.0_r4"
                localManifestBranch="master"
                treble_generate=""
                extra_make_options=""
                ;;
            aosp81)
                mainrepo="https://android.googlesource.com/platform/manifest"
                mainbranch="android-8.1.0_r43"
                localManifestBranch="android-8.1"
                treble_generate=""
                extra_make_options=""
                ;;
            aosp90)
                mainrepo="https://android.googlesource.com/platform/manifest"
                mainbranch="android-9.0.0_r1"
                localManifestBranch="android-9.0"
                treble_generate=""
                extra_make_options=""
                ;;
            carbon)
                mainrepo="https://github.com/CarbonROM/android"
                mainbranch="cr-6.1"
                localManifestBranch="android-8.1"
                treble_generate="carbon"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            lineage)
                mainrepo="https://github.com/LineageOS/android.git"
                mainbranch="lineage-15.1"
                localManifestBranch="android-8.1"
                treble_generate="lineage"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            rr)
                mainrepo="https://github.com/ResurrectionRemix/platform_manifest.git"
                mainbranch="oreo"
                localManifestBranch="android-8.1"
                treble_generate="rr"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            pixel)
                mainrepo="https://github.com/PixelExperience/manifest"
                mainbranch="oreo-mr1"
                localManifestBranch="android-8.1"
                treble_generate="pixel"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            crdroid)
                mainrepo="https://github.com/crdroidandroid/android"
                mainbranch="8.1"
                localManifestBranch="android-8.1"
                treble_generate="crdroid"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            mokee)
                mainrepo="https://github.com/MoKee/android.git"
                mainbranch="mko-mr1"
                localManifestBranch="android-8.1"
                treble_generate="mokee"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            aicp)
                mainrepo="https://github.com/AICP/platform_manifest.git"
                mainbranch="o8.1"
                localManifestBranch="android-8.1"
                treble_generate="aicp"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            aokp)
                mainrepo="https://github.com/AOKP/platform_manifest.git"
                mainbranch="oreo"
                localManifestBranch="android-8.1"
                treble_generate="aokp"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
            aex)
                mainrepo="https://github.com/AospExtended/manifest.git"
                mainbranch="8.1.x"
                localManifestBranch="android-8.1"
                treble_generate="aex"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
	    slim)
                mainrepo="git://github.com/SlimRoms/platform_manifest.git "
                mainbranch="or8.1"
                localManifestBranch="android-8.1"
                treble_generate="slim"
                extra_make_options="WITHOUT_CHECK_API=true"
                ;;
        esac
        shift
    done
}

function parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j)
                jobs="$2";
                shift;
                ;;
        esac
        shift
    done
}

declare -A processor_type_map
processor_type_map[arm]=arm
processor_type_map[arm64]=arm64

declare -A partition_layout_map
partition_layout_map[aonly]=a
partition_layout_map[ab]=b

declare -A gapps_selection_map
gapps_selection_map[vanilla]=v
gapps_selection_map[gapps]=g
gapps_selection_map[go]=o
gapps_selection_map[floss]=f

declare -A su_selection_map
su_selection_map[su]=S
su_selection_map[nosu]=N

function parse_variant() {
    local -a pieces
    IFS=- pieces=( $1 )

    local processor_type=${processor_type_map[${pieces[0]}]}
    local partition_layout=${partition_layout_map[${pieces[1]}]}
    local gapps_selection=${gapps_selection_map[${pieces[2]}]}
    local su_selection=${su_selection_map[${pieces[3]}]}

    if [[ -z "$processor_type" || -z "$partition_layout" || -z "$gapps_selection" || -z "$su_selection" ]]; then
        >&2 echo "Invalid variant '$1'"
        >&2 help
        exit 2
    fi

    #echo "treble_${processor_type}_${partition_layout}${gapps_selection}${su_selection}-userdebug"
    echo "treble_${processor_type}_${partition_layout}${gapps_selection}${su_selection}-user"
}

declare -a variant_codes
declare -a variant_names
function get_variants() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            *-*-*-*)
                variant_codes[${#variant_codes[*]}]=$(parse_variant "$1")
                variant_names[${#variant_names[*]}]="$1"
                ;;
        esac
        shift
    done
}

## function that actually do things

function init_release() {
    mkdir -p release/"$rom_fp"
}

function init_main_repo() {
    repo init -u "$mainrepo" -b "$mainbranch"
}

function clone_or_checkout() {
    local dir="$1"
    local repo="$2"

    if [[ -d "$dir" ]];then
        (
            cd "$dir"
            git fetch
            git reset --hard
            git checkout origin/"$localManifestBranch"
        )
    else
        git clone https://github.com/phhusson/"$repo" "$dir" -b "$localManifestBranch"
    fi
}

function init_local_manifest() {
    clone_or_checkout .repo/local_manifests treble_manifest

    cp "$(dirname "$0")"/custom_manifest.xml .repo/local_manifests/
}

function init_patches() {
    if [[ -n "$treble_generate" ]]; then
        clone_or_checkout patches treble_patches

        # We don't want to replace from AOSP since we'll be applying
        # patches by hand
        rm -f .repo/local_manifests/replace.xml

        # should I do this? will it interfere with building non-gapps images?
        # rm -f .repo/local_manifests/opengapps.xml
    fi
}

function sync_repo() {
    repo sync -c -j "$jobs" --force-sync
}

function patch_things() {
    if [[ -n "$treble_generate" ]]; then
        rm -f device/*/sepolicy/common/private/genfs_contexts
        (
            cd device/phh/treble
    if [[ $choice == *"y"* ]];then
            git clean -fdx
    fi
            bash generate.sh "$treble_generate"
        )
        bash "$(dirname "$0")/apply-patches.sh" patches
    else
        repo manifest -r > release/"$rom_fp"/manifest.xml
        bash "$(dirname "$0")"/list-patches.sh
        cp patches.zip release/"$rom_fp"/patches.zip

        cp -r "$(dirname "$0")/custom_patches" patches
        bash "$(dirname "$0")/apply-patches.sh" .

        (
            cd device/phh/treble
            git clean -fdx
            bash generate.sh
        )

        (
            cd vendor/foss
            git clean -fdx
            bash update.sh
        )
    fi

    cp "$(dirname "$0")"/keys/* build/make/target/product/security/
}

function build_variant() {
    lunch "$1"
    make $extra_make_options BUILD_NUMBER="$rom_fp" installclean
    make $extra_make_options BUILD_NUMBER="$rom_fp" -j "$jobs" target-files-package
    make $extra_make_options BUILD_NUMBER="$rom_fp" vndk-test-sepolicy

    # Sign target files
    if [ ! -d out/host/linux-x86/framework/dumpkey.jar ]; then
        make BUILD_NUMBER="$rom_fp" dumpkey
    fi
    ./build/tools/releasetools/sign_target_files_apks -o -d "$(dirname "$0")"/keys \
        "$OUT"/obj/PACKAGING/target_files_intermediates/*.zip \
        release/"$rom_fp"/target_files-"$2".zip

    # Extract system image
    unzip release/"$rom_fp"/target_files-"$2".zip IMAGES/system.img -d release/"$rom_fp"/
    mv release/"$rom_fp"/IMAGES/system.img release/"$rom_fp"/system-"$2".img
    rmdir release/"$rom_fp"/IMAGES

    # Generate OTA updates
    if [ ! -d out/host/linux-x86/bin/brillo_update_payload ]; then
        make BUILD_NUMBER="$rom_fp" brillo_update_payload
    fi
    ./build/tools/releasetools/ota_from_target_files -v -k "$(dirname "$0")"/keys/releasekey \
        release/"$rom_fp"/target_files-"$2".zip \
        release/"$rom_fp"/ota_update-"$2".zip
}

function jack_env() {
    RAM=$(free | awk '/^Mem:/{ printf("%0.f", $2/(1024^2))}') #calculating how much RAM (wow, such ram)
    if [[ "$RAM" -lt 16 ]];then #if we're poor guys with less than 16gb
	export JACK_SERVER_VM_ARGUMENTS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx"$((RAM -1))"G"
    fi
}

function build_chromium() {
    # needs depot_tools
    mkdir -p chromium
    (
        cd chromium
        fetch --nohooks android --target_os_only=true
        gclient sync --with_branch_heads -r $chromium --jobs $jobs

        # Apply the Copperhead patches
        if [ ! -d chromium_patches ]; then
            git clone https://github.com/KoffeinFlummi/chromium_patches
        fi
        cd src
        git am ../chromium_patches/*.patch

        gn gen --args="target_os=\"android\" target_cpu=\"arm64\" is_debug=false is_official_build=true is_component_build=false symbol_level=0 ffmpeg_branding=\"Chrome\" proprietary_codecs=true android_channel=\"stable\" android_default_version_name=\"$chromium\" android_default_version_code=\"33591852\"" out/Default

        cd out/Default
        ninja -j $jobs monochrome_public_apk
    )

    cp chromium/src/out/Default/apks/MonochromePublic.apk external/chromium/prebuilt/arm64/
}

parse_options "$@"
get_rom_type "$@"
get_variants "$@"

if [[ -z "$mainrepo" || ${#variant_codes[*]} -eq 0 ]]; then
    >&2 help
    exit 1
fi

# Use a python2 virtualenv if system python is python3
python=$(python -V | awk '{print $2}' | head -c2)
if [[ $python == "3." ]]; then
    if [ ! -d .venv ]; then
        virtualenv2 .venv
    fi
    . .venv/bin/activate
fi

init_release
if [[ $choice == *"y"* ]];then
init_main_repo
init_local_manifest
init_patches
sync_repo
fi
patch_things
jack_env

if [[ $choice_chromium == *"y"* ]];then
build_chromium
fi

. build/envsetup.sh

for (( idx=0; idx < ${#variant_codes[*]}; idx++ )); do
    build_variant "${variant_codes[$idx]}" "${variant_names[$idx]}"
done
