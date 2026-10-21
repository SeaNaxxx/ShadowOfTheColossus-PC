#define _GNU_SOURCE
#include "guest_cpu.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <unistd.h>

#if !defined(__x86_64__)
#error "guest_cpu_x86.c requires an x86-64 host; use the FEX backend on Android/ARM64"
#endif

#define ARCH_SET_GS 0x1001

void guest_cpu_set_gs_base(void *base) {
    if (syscall(SYS_arch_prctl, ARCH_SET_GS, (unsigned long)base)) {
        perror("STOP: arch_prctl(ARCH_SET_GS)");
        exit(21);
    }
}
