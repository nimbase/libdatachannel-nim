
## Shared helpers for the high-level API.
##
## Not meant to be imported directly, use `import libdatachannel` instead.
##

import std/strutils
import ./bindings

type
  LibDataChannelError* = object of CatchableError
    ## Raised whenever libdatachannel reports a negative error code.

type
  SdpType* = enum
    ## The `type` of a session description.
    sdpOffer = "offer"
    sdpAnswer = "answer"
    sdpPrAnswer = "pranswer"
    sdpRollback = "rollback"

template descriptionOffer* = sdpOffer
template descriptionAnswer* = sdpAnswer
template descriptionPrAnswer* = sdpPrAnswer
template descriptionRollback* = sdpRollback

template DCDescriptionType* = SdpType

proc toSdpType*(s: string): SdpType =
  ## Convert an SDP type as reported by libdatachannel.
  case s.toLowerAscii()
  of "offer": sdpOffer
  of "answer": sdpAnswer
  of "pranswer": sdpPrAnswer
  of "rollback": sdpRollback
  else: raise newException(LibDataChannelError, "unknown SDP type: " & s)

proc toSdpType*(s: cstring): SdpType =
  ## Convert an SDP type as reported by libdatachannel.
  toSdpType($s)

proc cstringOrNil*(s: string): cstring =
  ## Convert `s` to a C string, or `nil` when `s` is empty.
  ##
  ## libdatachannel distinguishes "not configured" (`NULL`) from "configured
  ## with this value", so every optional field of a C configuration struct
  ## needs this instead of a plain `cstring` conversion: passing a pointer to an
  ## empty string makes the library try to, for example, load an empty
  ## certificate file.
  if s.len == 0: nil else: cstring(s)

proc toNimString*(s: cstring): string =
  ## Copy a C string into a Nim string. `nil` becomes `""`.
  if s.isNil: "" else: $s

proc toNimBytes*(data: pointer; size: int): string =
  ## Copy `size` raw bytes at `data` into a Nim string. Embedded NUL bytes are
  ## preserved, which matters for binary messages.
  if data.isNil or size <= 0: return ""
  result = newString(size)
  copyMem(addr result[0], data, size)

proc errorCode*(code: cint): string =
  ## Human readable name for a libdatachannel error code.
  case code
  of RTC_ERR_SUCCESS: "RTC_ERR_SUCCESS"
  of RTC_ERR_INVALID: "RTC_ERR_INVALID"
  of RTC_ERR_FAILURE: "RTC_ERR_FAILURE"
  of RTC_ERR_NOT_AVAIL: "RTC_ERR_NOT_AVAIL"
  of RTC_ERR_TOO_SMALL: "RTC_ERR_TOO_SMALL"
  else: "error " & $code

type
  CStringArray* = cstringArray
    ## A `NULL` terminated array of C strings, owned by this module.

proc toCStringArray*(items: openArray[string]): CStringArray =
  ## Allocate a `NULL` terminated array of C strings.
  ##
  ## Uses the shared heap instead of `system.allocCStringArray` so that it is
  ## safe to call from the threads libdatachannel spawns for its callbacks.
  ## Release it with `freeCStringArray`.
  result = cast[CStringArray](allocShared0((items.len + 1) * sizeof(cstring)))
  for i, item in items:
    result[i] = cast[cstring](allocShared0(item.len + 1))
    copyMem(result[i], item.cstring, item.len)

proc freeCStringArray*(array: CStringArray) =
  ## Free an array created by `toCStringArray`. `nil` is accepted.
  if array.isNil: return
  var i = 0
  while array[i] != nil:
    deallocShared(array[i])
    inc i
  deallocShared(array)

proc reportCallbackError(message: string) =
  let line = "libdatachannel: exception escaped a callback: " & message
  try:
    writeLine(stderr, line)
  except IOError:
    discard

template runInCallback*(body: untyped) =
  ## Run `body` from inside a libdatachannel callback.
  ##
  ## libdatachannel calls us from threads the Nim runtime never saw, so the GC
  ## has to be initialised for them **before** anything allocates: without it
  ## the allocator dereferences a per-thread region handle that is still nil
  ## (Nim >= 2.2.12). A Nim exception must never unwind through the C++ frames
  ## below us either.
  ##
  ## `setupForeignThreadGc` is a cheap thread-local guard, so calling it on
  ## every callback only initialises each thread once.
  setupForeignThreadGc()
  try:
    body
  except CatchableError:
    # Report and swallow: unwinding into C++ would abort the process.
    reportCallbackError(getCurrentExceptionMsg())
  except Defect:
    # Defects (a stack-overflow guard tripping on a foreign thread, for
    # example) must not unwind through the C++ frames below us either.
    reportCallbackError(getCurrentExceptionMsg())

proc check*(code: cint) =
  ## Raise a `LibDataChannelError` if `code` is a libdatachannel error.
  if code < 0:
    raise newException(LibDataChannelError,
      "libdatachannel: " & errorCode(code))

## Every libdatachannel getter has the same shape: call it once with a `nil`
## buffer to learn how many bytes are needed, then again with a buffer that is
## large enough. These templates implement that dance around any such call.
##

template getCString*(getter: untyped): string =
  ## Evaluate `getter(buffer, size)` twice and return the NUL terminated string
  ## it produced.
  block:
    var value = ""
    let needed = getter(nil, 0)
    if needed == RTC_ERR_NOT_AVAIL:
      value = ""
    else:
      check needed
      if needed > 0:
        var buffer = newString(needed)
        let written = getter(addr buffer[0], needed)
        check written
        # `written` counts the trailing NUL byte.
        buffer.setLen(max(written - 1, 0))
        value = buffer
    value

template getCInts*(getter: untyped): seq[int] =
  ## Evaluate `getter(buffer, count)` twice and return the `int` array.
  block:
    var values: seq[int] = @[]
    let needed = getter(nil, 0)
    if needed == RTC_ERR_NOT_AVAIL:
      values = @[]
    else:
      check needed
      if needed > 0:
        var buffer = newSeq[cint](needed)
        let written = getter(addr buffer[0], needed)
        check written
        values = newSeqOfCap[int](max(written, 0))
        for i in 0 ..< max(written, 0):
          values.add int(buffer[i])
    values

template getCUint32s*(getter: untyped): seq[uint32] =
  ## Evaluate `getter(buffer, count)` twice and return the `uint32_t` array.
  block:
    var values: seq[uint32] = @[]
    let needed = getter(nil, 0)
    if needed == RTC_ERR_NOT_AVAIL:
      values = @[]
    else:
      check needed
      if needed > 0:
        var buffer = newSeq[uint32](needed)
        let written = getter(addr buffer[0], needed)
        check written
        values = newSeqOfCap[uint32](max(written, 0))
        for i in 0 ..< max(written, 0):
          values.add buffer[i]
    values

#
#  Pretty printing
#

proc `$`*(state: rtcState): string =
  case state
  of RTC_NEW: "new"
  of RTC_CONNECTING: "connecting"
  of RTC_CONNECTED: "connected"
  of RTC_DISCONNECTED: "disconnected"
  of RTC_FAILED: "failed"
  of RTC_CLOSED: "closed"

proc `$`*(state: rtcIceState): string =
  case state
  of RTC_ICE_NEW: "new"
  of RTC_ICE_CHECKING: "checking"
  of RTC_ICE_CONNECTED: "connected"
  of RTC_ICE_COMPLETED: "completed"
  of RTC_ICE_FAILED: "failed"
  of RTC_ICE_DISCONNECTED: "disconnected"
  of RTC_ICE_CLOSED: "closed"

proc `$`*(state: rtcGatheringState): string =
  case state
  of RTC_GATHERING_NEW: "new"
  of RTC_GATHERING_INPROGRESS: "in-progress"
  of RTC_GATHERING_COMPLETE: "complete"

proc `$`*(state: rtcSignalingState): string =
  case state
  of RTC_SIGNALING_STABLE: "stable"
  of RTC_SIGNALING_HAVE_LOCAL_OFFER: "have-local-offer"
  of RTC_SIGNALING_HAVE_REMOTE_OFFER: "have-remote-offer"
  of RTC_SIGNALING_HAVE_LOCAL_PRANSWER: "have-local-pranswer"
  of RTC_SIGNALING_HAVE_REMOTE_PRANSWER: "have-remote-pranswer"

proc `$`*(level: rtcLogLevel): string =
  case level
  of RTC_LOG_NONE: "none"
  of RTC_LOG_FATAL: "fatal"
  of RTC_LOG_ERROR: "error"
  of RTC_LOG_WARNING: "warning"
  of RTC_LOG_INFO: "info"
  of RTC_LOG_DEBUG: "debug"
  of RTC_LOG_VERBOSE: "verbose"

proc `$`*(cert: rtcCertificateType): string =
  case cert
  of RTC_CERTIFICATE_DEFAULT: "default"
  of RTC_CERTIFICATE_ECDSA: "ECDSA"
  of RTC_CERTIFICATE_RSA: "RSA"

proc `$`*(codec: rtcCodec): string =
  case codec
  of RTC_CODEC_H264: "H264"
  of RTC_CODEC_VP8: "VP8"
  of RTC_CODEC_VP9: "VP9"
  of RTC_CODEC_H265: "H265"
  of RTC_CODEC_AV1: "AV1"
  of RTC_CODEC_OPUS: "OPUS"
  of RTC_CODEC_PCMU: "PCMU"
  of RTC_CODEC_PCMA: "PCMA"
  of RTC_CODEC_AAC: "AAC"
  of RTC_CODEC_G722: "G722"

proc `$`*(direction: rtcDirection): string =
  case direction
  of RTC_DIRECTION_UNKNOWN: "unknown"
  of RTC_DIRECTION_SENDONLY: "sendonly"
  of RTC_DIRECTION_RECVONLY: "recvonly"
  of RTC_DIRECTION_SENDRECV: "sendrecv"
  of RTC_DIRECTION_INACTIVE: "inactive"

proc `$`*(policy: rtcTransportPolicy): string =
  case policy
  of RTC_TRANSPORT_POLICY_ALL: "all"
  of RTC_TRANSPORT_POLICY_RELAY: "relay"

proc `$`*(sep: rtcNalUnitSeparator): string =
  case sep
  of RTC_NAL_SEPARATOR_LENGTH: "length"
  of RTC_NAL_SEPARATOR_LONG_START_SEQUENCE: "long-start-sequence"
  of RTC_NAL_SEPARATOR_SHORT_START_SEQUENCE: "short-start-sequence"
  of RTC_NAL_SEPARATOR_START_SEQUENCE: "start-sequence"

proc `$`*(obu: rtcObuPacketization): string =
  case obu
  of RTC_OBU_PACKETIZED_OBU: "obu"
  of RTC_OBU_PACKETIZED_TEMPORAL_UNIT: "temporal-unit"