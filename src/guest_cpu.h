/* SPDX-License-Identifier: GPL-2.0-or-later */
/* CPU boundary adapted from zFitness/gow3_android. */
#ifndef SOTC_GUEST_CPU_H
#define SOTC_GUEST_CPU_H

#include <signal.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__x86_64__)
#define GUEST_CPU_NATIVE 1
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum {
    GUEST_RAX, GUEST_RCX, GUEST_RDX, GUEST_RBX, GUEST_RSP, GUEST_RBP, GUEST_RSI, GUEST_RDI,
    GUEST_R8, GUEST_R9, GUEST_R10, GUEST_R11, GUEST_R12, GUEST_R13, GUEST_R14, GUEST_R15,
    GUEST_GPRS
};

typedef struct {
    uint64_t gpr[GUEST_GPRS];
    uint64_t rip;
} GuestRegs;

void guest_cpu_init(void *(*map)(size_t size, int prot));
void guest_cpu_code(uintptr_t base, size_t size);
uintptr_t guest_cpu_host_function(void *fn);
uint64_t guest_cpu_call(uintptr_t fn, unsigned count, const uint64_t *args);
void guest_cpu_thread_stack(void *top, size_t size);
void guest_cpu_set_gs(void *base);
void guest_cpu_abandon(void);
void guest_cpu_thread_end(void);
uintptr_t guest_cpu_return_address(uintptr_t native);
uintptr_t guest_cpu_stack_pointer(void);

enum { GUEST_CPU_IN_GUEST = 1, GUEST_CPU_IN_HOST_CALL = 2 };
int guest_cpu_signal_regs(const void *ucontext, GuestRegs *regs);
uintptr_t guest_cpu_host_pc(const void *ucontext);
int guest_cpu_handle_fault(int sig, siginfo_t *info, void *ucontext);

typedef void (*GuestHook)(GuestRegs *regs);
int guest_cpu_hook(uintptr_t address, size_t size, GuestHook hook);
uint64_t guest_cpu_tsc(void);
uint64_t guest_cpu_tsc_frequency(void);

#ifdef __cplusplus
}
#endif
#endif
