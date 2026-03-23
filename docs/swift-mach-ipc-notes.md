# Swift Mach OOL IPC — 실패 기록과 교훈

mozc_server와의 Mach IPC를 Swift로 구현하려다 실패한 과정을 정리한 문서.
나중에 Swift-only Mach IPC를 별도 프로젝트에서 완성할 때 참고용.

## 배경

NRIME의 일본어 변환은 mozc_server와 Mach OOL(Out-of-Line) IPC로 통신한다.
upstream mozc는 C++로 구현된 `src/ipc/mach_ipc.cc`를 사용하며, 이것이 정상 동작의 기준이다.

## 목표

Swift에서 동일한 Mach OOL IPC를 직접 구현하여, C/ObjC 의존 없이 mozc_server와 통신.

## 메시지 구조

```
┌─ mach_msg_header_t (24 bytes) ─────────────────┐
│  msgh_bits, msgh_size, msgh_remote_port,        │
│  msgh_local_port, msgh_voucher_port, msgh_id    │
├─ mach_msg_body_t (4 bytes) ─────────────────────┤
│  msgh_descriptor_count = 1                       │
├─ mach_msg_ool_descriptor_t (16 bytes) ──────────┤
│  address, deallocate, copy, pad, type, size      │
├─ mach_msg_type_number_t (4 bytes) ──────────────┤
│  count (== ool data size)                        │
└─────────────────────────────────────────────────┘
Total send: 48 bytes
Total recv: 56 bytes (+mach_msg_trailer_t 8 bytes)
```

## struct layout 검증 (C vs Swift)

```
C:     send=48, recv=56, header=24, body=4, ool_desc=16, count=4, trailer=8
Swift: send=48, recv=56, header=24, body=4, ool_desc=16, count=4, trailer=8

offsets (C == Swift):
  header=0, body=24, data=28, count=44
```

struct layout은 C와 Swift에서 **완벽히 일치**했다.

## 시도한 방법들

### 1. Swift에서 직접 mach_msg 호출 (inline send/recv)
```swift
var sendMsg = MachIPCSendMessage()
sendMsg.header.msgh_bits = nrime_mach_msgh_bits(...)
sendMsg.data.address = UnsafeMutableRawPointer(mutating: requestPtr)
sendMsg.data.copy = MACH_MSG_VIRTUAL_COPY
sendMsg.data.type = MACH_MSG_OOL_DESCRIPTOR
// ... mach_msg(MACH_SEND_MSG | MACH_RCV_MSG)
```
**결과**: `recv OK size=0` (빈 응답) 또는 `recv failed kr=268451843` (타임아웃)

### 2. send/recv 분리
upstream mozc처럼 send와 recv를 별도 mach_msg 호출로 분리.
**결과**: 동일 실패

### 3. vm_allocate로 요청 버퍼 할당
`Data.withUnsafeBytes` 대신 `vm_allocate`로 Mach VM 영역을 확보하여 OOL descriptor에 전달.
**결과**: 동일 실패

### 4. PHYSICAL_COPY
`MACH_MSG_VIRTUAL_COPY` 대신 `MACH_MSG_PHYSICAL_COPY`로 변경하여 COW 문제 방지.
**결과**: 동일 실패

### 5. reply port에 insert_right 추가/제거
**결과**: 무관

## C 테스트 (성공)

```c
SendMsg msg;
msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND)
                     | MACH_MSGH_BITS_COMPLEX;
msg.data.address = payload;
msg.data.size = sizeof(payload);
msg.data.copy = MACH_MSG_VIRTUAL_COPY;
msg.data.type = MACH_MSG_OOL_DESCRIPTOR;

mach_msg(&msg.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, ...);
mach_msg(&recv.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, ...);
```
**결과**: 즉시 성공. response 11 bytes (CREATE_SESSION 응답).

## 최종 해결: C shim

`nrime_mozc_ipc.c`를 만들어 C에서 mach_msg를 직접 호출하고,
Swift에서는 `nrime_mozc_call()` 함수만 호출하는 방식으로 해결.

```swift
// Swift 측
let ok = nrime_mozc_call(portName, requestPtr, request.count,
                         &responsePtr, &responseSize, timeout)
```

## 추정 원인

정확한 원인은 미확정. struct layout이 동일함에도 실패한 이유:

1. **mach_msg_ool_descriptor_t bitfield 패킹**
   - C에서는 `deallocate:8, copy:8, pad:8, type:8`이 4바이트로 패킹됨
   - Swift에서 동일하게 접근하지만, 컴파일러의 bitfield 최적화가 다를 수 있음

2. **withUnsafeMutablePointer 수명/복사**
   - `withUnsafeMutablePointer(to: &sendMsg)` 안에서 `mach_msg`를 호출하지만,
     Swift 컴파일러가 sendMsg를 스택에서 이동하거나 복사할 수 있음
   - C에서는 변수가 확실히 스택에 고정됨

3. **OOL address 유효성**
   - `Data.withUnsafeBytes`의 포인터 수명이 mach_msg 실행 전에 끝날 가능성
   - vm_allocate로도 실패한 것은 이 가설에 반하지만,
     Swift runtime이 중간에 메모리를 remap할 가능성은 0이 아님

4. **reply port 권한**
   - Swift에서 `mach_port_allocate` → `MACH_MSG_TYPE_MAKE_SEND`로 reply port를 만들지만,
     커널이 실제로 send right를 부여하는 타이밍이 미묘하게 다를 수 있음

## 나중에 재도전할 때 확인 포인트

1. **bitfield 검증**: `mach_msg_ool_descriptor_t`의 각 bitfield에 실제로 올바른 값이 들어가는지
   Swift에서 raw memory dump로 확인
2. **메모리 dump 비교**: C와 Swift에서 전송 직전의 전체 메시지 바이트를 hex dump하여 비교
3. **mach_msg 옵션 차이**: Swift에서 mach_msg_option_t 값이 정확히 같은지 raw value 비교
4. **최소 재현**: 2바이트 payload로 CREATE_SESSION만 보내는 최소 Swift 프로그램 작성
5. **Xcode Memory Graph**: mach_msg 호출 시점의 실제 메모리 레이아웃 디버깅
6. **Apple Developer Forums / Swift Forums**: Swift에서 Mach OOL IPC 사용 사례 검색
