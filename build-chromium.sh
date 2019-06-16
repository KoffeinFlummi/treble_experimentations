#!/bin/bash

# Meant to run on a fresh Ubuntu 16.04

set -e

VERSION="74.0.3729.136"

if [ $(df | egrep "/$" | awk '{print $4}') -lt 104857600 ]; then
    echo "!!! Hard drive probably too small (< 100GiB) !!!"
    echo "!!! (ignore if chromium already cloned)      !!!"
fi

sudo apt update
sudo apt install -y python

if [ ! -d depot_tools ]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$PATH:${HOME}/depot_tools"

if [ ! -d chromium ]; then
    mkdir chromium
    cd chromium
    fetch --nohooks android
else
    cd chromium
fi

./src/build/install-build-deps-android.sh

gclient sync -D --with_branch_heads -r $VERSION

# Apply the Copperhead patches
rm -rf chromium_patches
git clone https://github.com/KoffeinFlummi/chromium_patches
cd src
git am ../chromium_patches/*.patch

./build/linux/sysroot_scripts/install-sysroot.py --arch=i386
./build/linux/sysroot_scripts/install-sysroot.py --arch=amd64

gn gen --args="target_os=\"android\" target_cpu=\"arm64\" is_debug=false is_official_build=true is_component_build=false symbol_level=0 enable_resource_whitelist_generation=false ffmpeg_branding=\"Chrome\" proprietary_codecs=true android_channel=\"stable\" android_default_version_name=\"$VERSION\"" out/Default

time ninja -C out/Default monochrome_public_apk
