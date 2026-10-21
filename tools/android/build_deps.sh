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
        "$HOME/Android/Sdk/ndk/29.0.14206865"; do
        if [[ -f "$candidate/build/cmake/android.toolchain.cmake" ]]; then ndk=$candidate; break; fi
    done
fi
[[ -f "$ndk/build/cmake/android.toolchain.cmake" ]] || {
    echo "Set ANDROID_NDK_HOME to Android NDK 29.0.14206865." >&2
    exit 1
}
for tool in cmake ninja make curl tar sha256sum python3; do
    command -v "$tool" >/dev/null || { echo "Need $tool to build Android dependencies." >&2; exit 1; }
done

root="$repo/out/android-arm64/deps"
src="$root/src"
build="$root/build"
prefix="$root/prefix"
mkdir -p "$src" "$build" "$prefix"
api=${SOTC_ANDROID_API:-28}
jobs=${SOTC_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '4')}
llvm=$(find "$ndk/toolchains/llvm/prebuilt" -maxdepth 1 -type d -name '*-x86_64' -print -quit)
[[ -n $llvm ]] || { echo "NDK LLVM host tools were not found under $ndk." >&2; exit 1; }

sha_for() {
    case "$1" in
        fmt-10.1.1) echo 78b8c0a72b1c35e4443a7e308df52498252d1cefc2b08c9a97bc9ee6cfe61f8b ;;
        zycore-1.5.2) echo 943f91eb9ab2a8cc01ab9f8b785e769a273502071e0ee8011cdfcaad93947cec ;;
        zydis-4.1.1) echo 45c6d4d499a1cc80780f7834747c637509777c01dca1e98c5e7c0bfaccdb1514 ;;
        xxhash-0.8.3) echo aae608dfe8213dfd05d909a57718ef82f30722c392344583d3f39050c7f29a80 ;;
        ffmpeg-7.1.5) echo de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f ;;
        *) return 1 ;;
    esac
}

fetch() {
    local name=$1 url=$2 archive="$src/$1.tar"
    local destination="$src/$1"
    [[ -f "$destination/CMakeLists.txt" || -f "$destination/configure" ]] && return
    curl -fsSL "$url" -o "$archive"
    printf '%s  %s\n' "$(sha_for "$name")" "$archive" | sha256sum --check --status || {
        rm -f "$archive"
        echo "Checksum mismatch while fetching $name." >&2
        exit 1
    }
    mkdir -p "$destination.tmp"
    tar -xf "$archive" -C "$destination.tmp" --strip-components=1
    mv "$destination.tmp" "$destination"
    rm -f "$archive"
}

cmake_dep() {
    local name=$1 source=$2
    shift 2
    [[ -f "$prefix/.done-$name" ]] && return
    cmake -S "$source" -B "$build/$name" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="android-$api" \
        -DANDROID_STL=c++_shared -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_PREFIX_PATH="$prefix" "$@" >/dev/null
    cmake --build "$build/$name" --parallel "$jobs"
    cmake --install "$build/$name" >/dev/null
    touch "$prefix/.done-$name"
}

fetch fmt-10.1.1 https://github.com/fmtlib/fmt/archive/refs/tags/10.1.1.tar.gz
fetch zycore-1.5.2 https://github.com/zyantific/zycore-c/archive/refs/tags/v1.5.2.tar.gz
fetch zydis-4.1.1 https://github.com/zyantific/zydis/archive/refs/tags/v4.1.1.tar.gz
fetch xxhash-0.8.3 https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.3.tar.gz
fetch ffmpeg-7.1.5 https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz

cmake_dep fmt "$src/fmt-10.1.1" -DFMT_TEST=OFF -DFMT_DOC=OFF
cmake_dep zycore "$src/zycore-1.5.2" -DBUILD_SHARED_LIBS=OFF
if [[ ! -f "$src/zydis-4.1.1/dependencies/zycore/CMakeLists.txt" ]]; then
    cp -a "$src/zycore-1.5.2/." "$src/zydis-4.1.1/dependencies/zycore/"
fi
cmake_dep zydis "$src/zydis-4.1.1" -DBUILD_SHARED_LIBS=OFF \
    -DZYDIS_BUILD_EXAMPLES=OFF -DZYDIS_BUILD_TOOLS=OFF -DZYDIS_BUILD_DOXYGEN=OFF
cmake_dep xxhash "$src/xxhash-0.8.3/cmake_unofficial" \
    -DBUILD_SHARED_LIBS=OFF -DXXHASH_BUILD_XXHSUM=OFF

if [[ ! -f "$prefix/.done-ffmpeg" ]]; then
    ffmpeg="$src/ffmpeg-7.1.5"
    ffmpeg_build="$build/ffmpeg"
    mkdir -p "$ffmpeg_build"
    cd "$ffmpeg_build"
    "$ffmpeg/configure" --prefix="$prefix" --enable-cross-compile --target-os=android --arch=aarch64 \
        --cc="$llvm/bin/aarch64-linux-android$api-clang" \
        --cxx="$llvm/bin/aarch64-linux-android$api-clang++" \
        --ar="$llvm/bin/llvm-ar" --ranlib="$llvm/bin/llvm-ranlib" \
        --strip="$llvm/bin/llvm-strip" --nm="$llvm/bin/llvm-nm" \
        --sysroot="$llvm/sysroot" \
        --enable-static --disable-shared --enable-pic --disable-programs --disable-doc --disable-debug \
        --disable-avdevice --disable-avfilter --disable-network --disable-autodetect \
        --disable-mediacodec --disable-jni >"$build/ffmpeg-configure.log" 2>&1 || {
        tail -40 "$ffmpeg_build/ffbuild/config.log" >&2 2>/dev/null || true
        tail -30 "$build/ffmpeg-configure.log" >&2
        exit 1
    }
    make -j"$jobs" >"$build/ffmpeg-build.log" 2>&1 || {
        tail -30 "$build/ffmpeg-build.log" >&2
        exit 1
    }
    make install >/dev/null
    sed -i 's/ -landroid -lmediandk//' "$prefix/lib/pkgconfig/libavutil.pc"
    touch "$prefix/.done-ffmpeg"
fi

echo "Built Android native dependencies in $prefix"
