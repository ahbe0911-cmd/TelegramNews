#!/usr/bin/env bash
set -euo pipefail
# Build the JSON ABI from Telegram's official source, not the obsolete binary
# bundled with the Dart FFI wrapper. A pinned revision makes builds repeatable.
TD_REV=d1085f9cebc5a62379991ae1652673954f229c1f
NDK_VERSION=27.0.12077973
OUTPUT="$PWD/native-tdlib"
mkdir -p "$OUTPUT"
sdkmanager "ndk;$NDK_VERSION" "cmake;3.22.1"
sudo apt-get update -qq
sudo apt-get install -y ninja-build gperf libssl-dev zlib1g-dev php-cli
git init tdlib-source
git -C tdlib-source remote add origin https://github.com/tdlib/td.git
git -C tdlib-source fetch --depth 1 origin "$TD_REV"
git -C tdlib-source checkout --detach FETCH_HEAD
cd tdlib-source/example/android
# The app is arm64-only. Do not spend time compiling three unused ABIs.
sed -i 's/for ABI in arm64-v8a armeabi-v7a x86_64 x86/for ABI in arm64-v8a/' build-openssl.sh build-tdlib.sh
# Release without debug/LTO lowers peak memory on GitHub's standard runners.
sed -i 's/CMAKE_BUILD_TYPE=RelWithDebInfo/CMAKE_BUILD_TYPE=Release/' build-tdlib.sh
export CMAKE_BUILD_PARALLEL_LEVEL=2
bash build-openssl.sh "$ANDROID_HOME" "$NDK_VERSION" third-party/openssl openssl-3.3.2
bash build-tdlib.sh "$ANDROID_HOME" "$NDK_VERSION" third-party/openssl c++_static JSON
cp tdlib/libs/arm64-v8a/libtdjson.so "$OUTPUT/libtdjson.so"
printf '%s\n' "$TD_REV" > "$OUTPUT/revision.txt"
test -s "$OUTPUT/libtdjson.so"
