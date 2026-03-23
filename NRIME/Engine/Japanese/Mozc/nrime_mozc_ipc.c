#include "nrime_mozc_ipc.h"
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/// Protocol version must match mozc's IPC_PROTOCOL_VERSION (currently 3).
#define IPC_PROTOCOL_VERSION 3

/// Matches mozc's mach_ipc_send_message struct exactly.
typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_ool_descriptor_t data;
    mach_msg_type_number_t count;
} nrime_send_message_t;

/// Matches mozc's mach_ipc_receive_message struct exactly.
typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_ool_descriptor_t data;
    mach_msg_type_number_t count;
    mach_msg_trailer_t trailer;
} nrime_receive_message_t;

bool nrime_mozc_call(const char *port_name,
                     const uint8_t *request, size_t request_size,
                     uint8_t **response, size_t *response_size,
                     uint32_t timeout_ms)
{
    *response = NULL;
    *response_size = 0;

    // 1. Look up server port
    mach_port_t server_port = MACH_PORT_NULL;
    kern_return_t kr = bootstrap_look_up(bootstrap_port, port_name, &server_port);
    if (kr != BOOTSTRAP_SUCCESS || server_port == MACH_PORT_NULL) {
        return false;
    }

    // 2. Allocate reply port
    mach_port_t client_port = MACH_PORT_NULL;
    kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &client_port);
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), server_port);
        return false;
    }

    // 3. Build send message — matches upstream mozc mach_ipc.cc exactly
    nrime_send_message_t send_message;
    memset(&send_message, 0, sizeof(send_message));

    send_message.header.msgh_bits =
        MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND) |
        MACH_MSGH_BITS_COMPLEX;
    send_message.header.msgh_size = sizeof(send_message);
    send_message.header.msgh_remote_port = server_port;
    send_message.header.msgh_local_port = client_port;
    send_message.header.msgh_reserved = 0;
    send_message.header.msgh_id = IPC_PROTOCOL_VERSION;

    send_message.body.msgh_descriptor_count = 1;

    send_message.data.address = (void *)request;
    send_message.data.size = (mach_msg_size_t)request_size;
    send_message.data.deallocate = false;
    send_message.data.copy = MACH_MSG_VIRTUAL_COPY;
    send_message.data.type = MACH_MSG_OOL_DESCRIPTOR;

    send_message.count = (mach_msg_type_number_t)request_size;

    // 4. Send request
    kr = mach_msg(&send_message.header,
                  MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                  send_message.header.msgh_size,
                  0,
                  MACH_PORT_NULL,
                  timeout_ms,
                  MACH_PORT_NULL);

    if (kr != MACH_MSG_SUCCESS) {
        mach_port_destroy(mach_task_self(), client_port);
        mach_port_deallocate(mach_task_self(), server_port);
        return false;
    }

    // 5. Receive response — retry up to 2 times (matches upstream)
    bool success = false;
    for (int trial = 0; trial < 2; ++trial) {
        nrime_receive_message_t receive_message;
        memset(&receive_message, 0, sizeof(receive_message));

        receive_message.header.msgh_remote_port = server_port;
        receive_message.header.msgh_local_port = client_port;
        receive_message.header.msgh_size = sizeof(receive_message);

        kr = mach_msg(&receive_message.header,
                      MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                      0,
                      receive_message.header.msgh_size,
                      client_port,
                      timeout_ms,
                      MACH_PORT_NULL);

        if (kr == MACH_RCV_TIMED_OUT) {
            break;
        }
        if (kr != MACH_MSG_SUCCESS) {
            continue;  // Wrong message, try again
        }
        if (receive_message.header.msgh_id != IPC_PROTOCOL_VERSION) {
            continue;  // Wrong protocol version
        }

        // Extract OOL response data
        if (receive_message.data.address != NULL && receive_message.data.size > 0) {
            size_t resp_size = receive_message.data.size;
            uint8_t *resp_buf = (uint8_t *)malloc(resp_size);
            if (resp_buf) {
                memcpy(resp_buf, receive_message.data.address, resp_size);
                *response = resp_buf;
                *response_size = resp_size;
                success = true;
            }
            // Deallocate OOL memory from kernel
            vm_deallocate(mach_task_self(),
                          (vm_address_t)receive_message.data.address,
                          receive_message.data.size);
        }
        break;
    }

    mach_port_destroy(mach_task_self(), client_port);
    mach_port_deallocate(mach_task_self(), server_port);
    return success;
}
