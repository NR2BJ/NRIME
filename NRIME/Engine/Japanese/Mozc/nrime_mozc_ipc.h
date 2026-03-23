#ifndef NRIME_MOZC_IPC_H
#define NRIME_MOZC_IPC_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/// Send a protobuf-serialized Mozc request via Mach IPC and receive the response.
/// Matches upstream mozc mach_ipc.cc client flow exactly.
///
/// @param port_name   Mach bootstrap port name (e.g. "org.mozc.inputmethod.Japanese.Converter.session")
/// @param request     Serialized protobuf request bytes
/// @param request_size Size of request in bytes
/// @param response    On success, set to malloc'd buffer containing response bytes. Caller must free().
/// @param response_size On success, set to size of response in bytes.
/// @param timeout_ms  Timeout in milliseconds for send and receive.
/// @return true on success, false on failure.
bool nrime_mozc_call(const char *port_name,
                     const uint8_t *request, size_t request_size,
                     uint8_t **response, size_t *response_size,
                     uint32_t timeout_ms);

#endif /* NRIME_MOZC_IPC_H */
