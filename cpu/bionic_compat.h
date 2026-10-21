/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Bionic compatibility for the pinned FEXCore source used by the Android build. */
#pragma once

#if defined(__cplusplus) && defined(__ANDROID__) && !defined(_WIN32)
#include <dirent.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

extern "C" {
inline ssize_t sotc_getdents64(int fd, void* dirp, size_t count) {
    return syscall(__NR_getdents64, fd, dirp, count);
}
}

#define getdents64 sotc_getdents64
#endif
