#ifndef SOTC_GUEST_CPU_H
#define SOTC_GUEST_CPU_H

/* Set the guest-visible GS base for the current guest thread. */
void guest_cpu_set_gs_base(void *base);

#endif
