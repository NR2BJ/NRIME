#ifndef NRIME_Bridging_Header_h
#define NRIME_Bridging_Header_h

#include <servers/bootstrap.h>
#include <mach/mach.h>

// MACH_MSGH_BITS is a function-like macro unavailable in Swift.
static inline mach_msg_bits_t nrime_mach_msgh_bits(mach_msg_bits_t remote, mach_msg_bits_t local) {
    return (remote) | ((local) << 8);
}

#endif
