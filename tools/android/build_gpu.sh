#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo"
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBRARY_PATH CPATH C_INCLUDE_PATH CXX_INCLUDE_PATH

ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
if [[ -z $ndk || ! -f "$ndk/build/cmake/android.toolchain.cmake" ]]; then
    for candidate in \
        "${ANDROID_SDK_ROOT:-}/ndk/29.0.14206865" \
        "${ANDROID_HOME:-}/ndk/29.0.14206865" \
        "$HOME/Android/Sdk/ndk/29.0.14206865" \
        "$HOME/Library/Android/sdk/ndk/29.0.14206865"; do
        if [[ -f "$candidate/build/cmake/android.toolchain.cmake" ]]; then ndk=$candidate; break; fi
    done
fi
[[ -f "$ndk/build/cmake/android.toolchain.cmake" ]] || {
    echo "Set ANDROID_NDK_HOME to Android NDK 29.0.14206865." >&2
    exit 1
}

for tool in cmake ninja pkg-config git; do
    command -v "$tool" >/dev/null || { echo "Need $tool to build the Android GPU runtime." >&2; exit 1; }
done
command -v glslangValidator >/dev/null || {
    echo "Install the host Vulkan SDK (glslangValidator is used to build the GPU shaders)." >&2
    exit 1
}

prefix="$repo/out/android-arm64/deps/prefix"
cpu="$repo/out/android-arm64/lib/libsotc_cpu.so"
[[ -f $cpu ]] || { echo "Build the FEXCore CPU library first with tools/android/build_cpu.sh." >&2; exit 1; }
[[ -f "$prefix/lib/pkgconfig/SDL3.pc" ]] || {
    echo "Build SDL3 first with tools/android/build_cpu.sh." >&2
    exit 1
}

for path in gpu/third_party/fsr-vulkan gpu/third_party/imgui gpu/third_party/magic_enum \
    gpu/third_party/miniz third_party/LibAtrac9; do
    if [[ ! -f "$path/CMakeLists.txt" && ! -f "$path/imgui.h" ]]; then
        git submodule update --init -- "$path"
    fi
done

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
export PKG_CONFIG_SYSROOT_DIR=
api=${SOTC_ANDROID_API:-28}
build="$repo/out/android-arm64/gpu"
mkdir -p "$repo/out/android-arm64/lib"

cmake -S gpu -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM="android-$api" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_PREFIX_PATH="$prefix${SOTC_HOST_PREFIX:+;$SOTC_HOST_PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DSOTC_CPU_LIBRARY="$cpu" \
    -DBB_LTO=OFF -DBB_PGO=off >/dev/null

jobs=${SOTC_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '4')}
if ! cmake --build "$build" --target main --parallel "$jobs"; then
    echo "Android GPU/runtime build failed in $build." >&2
    exit 1
fi

[[ -s "$repo/out/android-arm64/lib/libmain.so" ]] || {
    echo "CMake did not produce libmain.so." >&2
    exit 1
}
echo "Built Android ARM64 native entry library: $repo/out/android-arm64/lib/libmain.so"
