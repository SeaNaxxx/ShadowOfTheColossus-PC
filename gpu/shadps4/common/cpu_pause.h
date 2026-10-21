// SPDX-FileCopyrightText: Copyright 2025 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#if defined(_M_X64) || defined(__x86_64__)
#include <immintrin.h>
#endif

namespace Common {

// Spin-wait hint: PAUSE on x86-64, YIELD on ARM64, nothing elsewhere.
inline void CpuPause() {
#if defined(_M_X64) || defined(__x86_64__)
    _mm_pause();
#elif defined(__aarch64__) || defined(_M_ARM64)
    asm("yield");
#endif
}

} // namespace Common
