/* NRIME's C API over Mozc: the conversion engine runs inside the input method
 * (no mozc_server, no IPC), built as libnrime_mozc.dylib and loaded at run
 * time, so a newer Mozc can replace it without a new NRIME.
 *
 * Commands are Mozc's own protocol — a serialized mozc.commands.Input in, a
 * serialized mozc.commands.Output back — so the Swift side builds and reads
 * exactly the messages it used to send to mozc_server.
 *
 * Use one instance from one thread (the input method's main thread). */
#ifndef NRIME_MOZC_H_
#define NRIME_MOZC_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NrimeMozc NrimeMozc;

/* Version of this API. NRIME loads only a library whose version it knows;
 * bump it whenever a function below changes. */
#define NRIME_MOZC_ABI_VERSION 1
int32_t nrime_mozc_abi_version(void);

/* data_path: mozc.data. profile_dir: where learning and the user dictionary
 * live (NULL or "" for Mozc's default). Set once per process: Mozc keeps the
 * profile directory globally. NULL on failure. */
NrimeMozc *nrime_mozc_new(const char *data_path, const char *profile_dir);
void nrime_mozc_free(NrimeMozc *mozc);

/* Evaluate one serialized mozc.commands.Input. On success returns 1 and puts a
 * serialized mozc.commands.Output, allocated with malloc, in *output (release
 * it with nrime_mozc_free_buffer). A command Mozc rejects still succeeds here:
 * the rejection is the Output's error_code. Returns 0 only if the input could
 * not be parsed or the output not written. */
int nrime_mozc_eval(NrimeMozc *mozc, const uint8_t *input, size_t input_size,
                    uint8_t **output, size_t *output_size);
void nrime_mozc_free_buffer(uint8_t *buffer);

/* Mozc's version, e.g. "3.34.6239.101". */
const char *nrime_mozc_version(void);

#ifdef __cplusplus
}
#endif

#endif  // NRIME_MOZC_H_
