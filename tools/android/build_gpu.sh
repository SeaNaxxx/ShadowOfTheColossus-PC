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
[[ -f "$prefix/lib/pkgconfig/sdl3.pc" ]] || {
    echo "Build SDL3 first with tools/android/build_cpu.sh." >&2
    exit 1
}

# This is a cross-build: NDK Clang ignores the host's /usr/include by design.
# Put the header-only Boost tree under the Android dependency prefix so the
# Vulkan target can include it without adding the host system headers wholesale.
boost_headers=
for candidate in "${SOTC_HOST_PREFIX:+$SOTC_HOST_PREFIX/include/boost}" \
    /usr/include/boost /usr/local/include/boost /opt/homebrew/include/boost; do
    if [[ -f "$candidate/icl/interval_set.hpp" ]]; then
        boost_headers=$candidate
        break
    fi
done
if [[ ! -f "$prefix/include/boost/icl/interval_set.hpp" ]]; then
    [[ -n $boost_headers ]] || {
        echo "Host Boost headers are required (boost/icl/interval_set.hpp was not found)." >&2
        exit 1
    }
    mkdir -p "$prefix/include/boost"
    cp -a "$boost_headers/." "$prefix/include/boost/"
fi

robin_headers=
for candidate in "${SOTC_HOST_PREFIX:+$SOTC_HOST_PREFIX/include/tsl}" \
    /usr/include/tsl /usr/local/include/tsl /opt/homebrew/include/tsl; do
    if [[ -f "$candidate/robin_map.h" ]]; then
        robin_headers=$candidate
        break
    fi
done
if [[ ! -f "$prefix/include/tsl/robin_map.h" ]]; then
    [[ -n $robin_headers ]] || {
        echo "Host robin-map headers are required (tsl/robin_map.h was not found)." >&2
        exit 1
    }
    mkdir -p "$prefix/include/tsl"
    cp -a "$robin_headers/." "$prefix/include/tsl/"
fi

vulkan_headers=
for candidate in "${VULKAN_SDK:+$VULKAN_SDK/include/vulkan}" \
    "${SOTC_HOST_PREFIX:+$SOTC_HOST_PREFIX/include/vulkan}" \
    /usr/include/vulkan /usr/local/include/vulkan /opt/homebrew/include/vulkan; do
    if [[ -f "$candidate/vulkan.hpp" && -d "$(dirname "$candidate")/vk_video" ]]; then
        vulkan_headers=$candidate
        break
    fi
done
if [[ ! -f "$prefix/include/vulkan/vulkan.hpp" ]]; then
    [[ -n $vulkan_headers ]] || {
        echo "Host Vulkan headers are required (vulkan/vulkan.hpp was not found)." >&2
        exit 1
    }
    mkdir -p "$prefix/include/vulkan" "$prefix/include/vk_video"
    cp -a "$vulkan_headers/." "$prefix/include/vulkan/"
    cp -a "$(dirname "$vulkan_headers")/vk_video/." "$prefix/include/vk_video/"
fi

# VulkanMemoryAllocator ships a host CMake config whose include dir is invisible
# to the NDK cross-build; put the header in the prefix and use it instead.
vma_header=
for candidate in "${SOTC_HOST_PREFIX:+$SOTC_HOST_PREFIX/include/vk_mem_alloc.h}" \
    /usr/include/vk_mem_alloc.h /usr/local/include/vk_mem_alloc.h \
    /usr/include/vma/vk_mem_alloc.h; do
    if [[ -f "$candidate" ]]; then
        vma_header=$candidate
        break
    fi
done
if [[ ! -f "$prefix/include/vk_mem_alloc.h" ]]; then
    [[ -n $vma_header ]] || {
        echo "Host VulkanMemoryAllocator header is required (vk_mem_alloc.h was not found)." >&2
        exit 1
    }
    mkdir -p "$prefix/include"
    cp -a "$vma_header" "$prefix/include/vk_mem_alloc.h"
fi

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

# The pkg-config imported targets hand the linker bare -l names; a cross build has no
# default search path for the prefix, so the linker must be told where the deps live.
cmake -S gpu -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM="android-$api" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_PREFIX_PATH="$prefix${SOTC_HOST_PREFIX:+;$SOTC_HOST_PREFIX}" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$prefix/lib" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DBoost_NO_BOOST_CMAKE=ON \
    -DBoost_INCLUDE_DIR="$prefix/include" \
    -DVulkan_INCLUDE_DIR="$prefix/include" \
    -DCMAKE_DISABLE_FIND_PACKAGE_VulkanMemoryAllocator=ON \
    -DVMA_INCLUDE_DIR="$prefix/include" \
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
