import Foundation
import SwiftProtobuf

/// Low-level Mozc IPC client using Mach ports.
/// Communicates with mozc_server via OOL Mach messages containing serialized protobuf.
final class MozcClient {
    private let portName = "org.mozc.inputmethod.Japanese.Converter.session"
    private let protocolVersion: mach_msg_id_t = 3  // IPC_PROTOCOL_VERSION
    private let timeout: mach_msg_timeout_t = 1000  // 1 second

    private var sessionId: UInt64 = 0
    private var hasSession = false

    /// Mozc config attached to every Input message.
    /// Enables realtime conversion, history/dictionary suggest, etc.
    private let mozcConfig: Mozc_Config_Config = {
        var config = Mozc_Config_Config()
        config.useRealtimeConversion = true
        config.useHistorySuggest = true
        config.useDictionarySuggest = true
        config.suggestionsSize = 9
        return config
    }()

    /// Mozc request flags (zero_query_suggestion for NWP, etc.)
    private let mozcRequest: Mozc_Commands_Request = {
        var request = Mozc_Commands_Request()
        request.zeroQuerySuggestion = true
        return request
    }()

    // MARK: - Public API

    /// Create a new session with mozc_server.
    func createSession() -> Bool {
        var input = Mozc_Commands_Input()
        input.type = .createSession

        guard let output = call(input) else { return false }

        if output.hasID {
            sessionId = output.id
            hasSession = true

            // Send SET_REQUEST to configure the session with our Request flags
            var setReqInput = Mozc_Commands_Input()
            setReqInput.type = .setRequest
            setReqInput.id = sessionId
            setReqInput.request = mozcRequest
            _ = call(setReqInput)

            return true
        }
        return false
    }

    /// Send a key event to the current session.
    func sendKey(_ keyEvent: Mozc_Commands_KeyEvent) -> Mozc_Commands_Output? {
        guard ensureSession() else { return nil }

        var input = Mozc_Commands_Input()
        input.type = .sendKey
        input.id = sessionId
        input.key = keyEvent
        initInput(&input)

        return call(input)
    }

    /// Send a session command (SUBMIT, REVERT, SELECT_CANDIDATE, etc.)
    func sendCommand(_ command: Mozc_Commands_SessionCommand,
                     context: Mozc_Commands_Context? = nil) -> Mozc_Commands_Output? {
        guard ensureSession() else { return nil }

        var input = Mozc_Commands_Input()
        input.type = .sendCommand
        input.id = sessionId
        input.command = command
        initInput(&input)
        if let context = context {
            input.context = context
        }

        return call(input)
    }

    /// Delete the current session.
    func deleteSession() {
        guard hasSession else { return }

        var input = Mozc_Commands_Input()
        input.type = .deleteSession
        input.id = sessionId

        _ = call(input)
        hasSession = false
        sessionId = 0
    }

    /// Reset session state (e.g., after error).
    func resetSession() {
        hasSession = false
        sessionId = 0
    }

    /// Clear Mozc's learned user history (conversion preferences).
    func clearUserHistory() {
        guard ensureSession() else { return }

        var input = Mozc_Commands_Input()
        input.type = .clearUserHistory
        input.id = sessionId

        _ = call(input)
    }

    /// Clear Mozc's user prediction data.
    func clearUserPrediction() {
        guard ensureSession() else { return }

        var input = Mozc_Commands_Input()
        input.type = .clearUserPrediction
        input.id = sessionId

        _ = call(input)
    }

    // MARK: - Private

    /// Attach config and request to every Input message.
    private func initInput(_ input: inout Mozc_Commands_Input) {
        input.config = mozcConfig
        input.request = mozcRequest
    }

    private func ensureSession() -> Bool {
        if hasSession { return true }
        return createSession()
    }

    /// Serialize Input protobuf, send via Mach port, receive and deserialize Output.
    /// Mozc server expects serialized Input (not Command) and returns serialized Output.
    private func call(_ input: Mozc_Commands_Input) -> Mozc_Commands_Output? {
        // Serialize Input directly — Mozc server parses request as Input
        let requestData: Data
        do {
            requestData = try input.serializedData()
        } catch {
            return nil
        }

        // Send via Mach IPC
        guard let responseData = machCall(request: requestData) else {
            return nil
        }

        // Deserialize response as Output directly — Mozc server serializes Output
        do {
            return try Mozc_Commands_Output(serializedBytes: responseData)
        } catch {
            return nil
        }
    }

    // MARK: - Mach IPC

    /// Send/receive a single Mach message with OOL protobuf data.
    private func machCall(request: Data) -> Data? {
        // 1. Look up server port
        var serverPort: mach_port_t = mach_port_t(0)
        let kr = bootstrap_look_up(bootstrap_port, portName, &serverPort)
        guard kr == KERN_SUCCESS, serverPort != mach_port_t(0) else {
            return nil
        }
        defer { mach_port_deallocate(mach_task_self_, serverPort) }

        // 2. Allocate reply port
        var replyPort: mach_port_t = mach_port_t(0)
        guard mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &replyPort) == KERN_SUCCESS else {
            return nil
        }
        defer { mach_port_destroy(mach_task_self_, replyPort) }

        // Insert send right for reply port
        mach_port_insert_right(mach_task_self_, replyPort, replyPort,
                               mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))

        // 3. Build send message
        let responseData = request.withUnsafeBytes { (requestBytes: UnsafeRawBufferPointer) -> Data? in
            guard let requestPtr = requestBytes.baseAddress else { return nil }

            var sendMsg = MachIPCSendMessage()
            sendMsg.header.msgh_bits = nrime_mach_msgh_bits(
                UInt32(MACH_MSG_TYPE_COPY_SEND), UInt32(MACH_MSG_TYPE_MAKE_SEND)
            ) | UInt32(MACH_MSGH_BITS_COMPLEX)
            sendMsg.header.msgh_size = UInt32(MemoryLayout<MachIPCSendMessage>.size)
            sendMsg.header.msgh_remote_port = serverPort
            sendMsg.header.msgh_local_port = replyPort
            sendMsg.header.msgh_id = protocolVersion

            sendMsg.body.msgh_descriptor_count = 1

            sendMsg.data.address = UnsafeMutableRawPointer(mutating: requestPtr)
            sendMsg.data.size = mach_msg_size_t(request.count)
            sendMsg.data.deallocate = 0  // false
            sendMsg.data.copy = mach_msg_copy_options_t(MACH_MSG_VIRTUAL_COPY)
            sendMsg.data.type = mach_msg_descriptor_type_t(MACH_MSG_OOL_DESCRIPTOR)

            sendMsg.count = mach_msg_type_number_t(request.count)

            // 4. Send
            let sendResult = withUnsafeMutablePointer(to: &sendMsg) { ptr in
                mach_msg(
                    &ptr.pointee.header,
                    MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                    mach_msg_size_t(MemoryLayout<MachIPCSendMessage>.size),
                    0,
                    mach_port_t(0),
                    timeout,
                    mach_port_t(0)
                )
            }

            guard sendResult == MACH_MSG_SUCCESS else { return nil }

            // 5. Receive response
            var recvMsg = MachIPCReceiveMessage()

            let recvResult = withUnsafeMutablePointer(to: &recvMsg) { ptr in
                mach_msg(
                    &ptr.pointee.header,
                    MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                    0,
                    mach_msg_size_t(MemoryLayout<MachIPCReceiveMessage>.size),
                    replyPort,
                    timeout,
                    mach_port_t(0)
                )
            }

            guard recvResult == MACH_MSG_SUCCESS else { return nil }

            // 6. Validate protocol version
            guard recvMsg.header.msgh_id == protocolVersion else { return nil }

            // 7. Extract OOL data
            let oolSize = recvMsg.data.size
            guard recvMsg.data.address != nil, oolSize > 0 else { return nil }

            let data = Data(bytes: recvMsg.data.address!, count: Int(oolSize))

            // Deallocate OOL memory
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: recvMsg.data.address!),
                vm_size_t(oolSize)
            )

            return data
        }

        return responseData
    }
}

// MARK: - Mach Message Structs

/// Matches mozc mach_ipc_send_message struct layout
private struct MachIPCSendMessage {
    var header = mach_msg_header_t()
    var body = mach_msg_body_t()
    var data = mach_msg_ool_descriptor_t()
    var count: mach_msg_type_number_t = 0
}

/// Matches mozc mach_ipc_receive_message struct layout
private struct MachIPCReceiveMessage {
    var header = mach_msg_header_t()
    var body = mach_msg_body_t()
    var data = mach_msg_ool_descriptor_t()
    var count: mach_msg_type_number_t = 0
    var trailer = mach_msg_trailer_t()
}
