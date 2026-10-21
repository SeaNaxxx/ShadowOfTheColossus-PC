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
        if [[ -f "$candidate/build/cmake/android.toolchain.cmake" ]]; then
            ndk=$candidate
            break
        fi
    done
fi

for tool in cmake ninja git python3 curl tar sha256sum; do
    command -v "$tool" >/dev/null || { echo "Need $tool to build the Android CPU backend." >&2; exit 1; }
done
[[ -f "$ndk/build/cmake/android.toolchain.cmake" ]] || {
    echo "Set ANDROID_NDK_HOME to Android NDK 29.0.14206865." >&2
    exit 1
}

if [[ ! -f third_party/FEX/CMakeLists.txt ]]; then
    git submodule update --init -- third_party/FEX
fi

# Initialize only FEXCore's runtime build dependencies; test binary submodules are not needed.
git -C third_party/FEX submodule update --init -- \
    External/fmt External/range-v3 External/rpmalloc External/unordered_dense \
    External/xxhash Source/Common/cpp-optparse

api=${SOTC_ANDROID_API:-28}
jobs=${SOTC_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '4')}
build="$repo/out/android-arm64/fex"
package="$repo/out/android-arm64/lib"
toolchain="$ndk/build/cmake/android.toolchain.cmake"
llvm=$(find "$ndk/toolchains/llvm/prebuilt" -maxdepth 1 -type d -name '*-x86_64' -print -quit)
[[ -n $llvm && -f "$llvm/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" ]] || {
    echo "NDK libc++_shared.so was not found under $ndk." >&2
    exit 1
}

# SDL supplies the Android Activity classes and the native Android Vulkan surface.
deps="$repo/out/android-arm64/deps"
sdl_src="$deps/SDL3-3.2.10"
sdl_archive="$deps/SDL3-3.2.10.tar.gz"
mkdir -p "$deps"
if [[ ! -f "$sdl_src/CMakeLists.txt" ]]; then
    curl -fsSL https://github.com/libsdl-org/SDL/releases/download/release-3.2.10/SDL3-3.2.10.tar.gz -o "$sdl_archive"
    echo 'f87be7b4dec66db4098e9c167b2aa34e2ca10aeb5443bdde95ae03185ed513e0  '"$sdl_archive" | sha256sum --check --status || {
        rm -f "$sdl_archive"
        echo "SDL3 release archive checksum mismatch." >&2
        exit 1
    }
    mkdir -p "$sdl_src"
    tar -xf "$sdl_archive" -C "$sdl_src" --strip-components=1
    rm -f "$sdl_archive"
fi

if [[ ! -f "$build/build.ninja" ]]; then
    cmake -S third_party/FEX -B "$build" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
        -DANDROID_ABI=arm64-v8a \
        -DANDROID_PLATFORM="android-$api" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PROJECT_FEX_INCLUDE="$repo/cpu/fex_project.cmake" \
        -DBUILD_TESTING=OFF \
        -DBUILD_THUNKS=OFF \
        -DBUILD_FEXCONFIG=OFF \
        -DBUILD_STEAM_SUPPORT=OFF \
        -DBUILD_FEX_LINUX_TESTS=OFF \
        -DENABLE_GDB_SYMBOLS=OFF \
        -DENABLE_ZYDIS=OFF \
        -DENABLE_JEMALLOC_GLIBC_ALLOC=OFF \
        -DENABLE_FEXCORE_PROFILER=OFF \
        -DTUNE_ARCH=generic \
        -DTUNE_CPU=generic >/dev/null
fi

if ! cmake --build "$build" --target sotc_cpu --parallel "$jobs"; then
    echo "FEXCore Android CPU backend build failed in $build" >&2
    exit 1
fi

sdl_build="$repo/out/android-arm64/sdl"
if [[ ! -f "$sdl_build/build.ninja" ]]; then
    cmake -S "$sdl_src" -B "$sdl_build" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
        -DANDROID_ABI=arm64-v8a \
        -DANDROID_PLATFORM="android-$api" \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$deps/prefix" \
        -DSDL_SHARED=ON \
        -DSDL_STATIC=OFF \
        -DSDL_TESTS=OFF \
        -DSDL_EXAMPLES=OFF \
        -DSDL_TEST_LIBRARY=OFF \
        -DSDL_INSTALL=ON >/dev/null
fi
cmake --build "$sdl_build" --parallel "$jobs"
cmake --install "$sdl_build" >/dev/null

mkdir -p "$package"
cp "$build/libsotc_cpu.so" "$package/libsotc_cpu.so"
cp "$llvm/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$package/libc++_shared.so"
cp "$deps/prefix/lib/libSDL3.so" "$package/libSDL3.so"
echo "Built $package/libsotc_cpu.so (arm64-v8a, Android API $api)"
