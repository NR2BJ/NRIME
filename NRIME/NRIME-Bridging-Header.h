#ifndef NRIME_Bridging_Header_h
#define NRIME_Bridging_Header_h

#include <servers/bootstrap.h>
#include <mach/mach.h>
#include <ApplicationServices/ApplicationServices.h>

// MACH_MSGH_BITS is a function-like macro unavailable in Swift.
static inline mach_msg_bits_t nrime_mach_msgh_bits(mach_msg_bits_t remote, mach_msg_bits_t local) {
    return (remote) | ((local) << 8);
}

// GetProcessForPID / CGEventPostToPSN are deprecated since 10.9
// but still functional. Swift refuses to import them, so we wrap here.

static inline OSStatus nrime_GetProcessForPID(pid_t pid, ProcessSerialNumber *psn) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return GetProcessForPID(pid, psn);
#pragma clang diagnostic pop
}

static inline void nrime_PostEventToPSN(ProcessSerialNumber *psn, CGEventRef event) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGEventPostToPSN(psn, event);
#pragma clang diagnostic pop
}

#endif
