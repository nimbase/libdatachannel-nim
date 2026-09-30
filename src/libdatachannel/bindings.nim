## Low-level 1:1 bindings to the libdatachannel C API.
##
## Targets libdatachannel **v0.24.x** (`rtc.h`). Every exported C entity of
## `rtc.h` is declared here with the same name, argument order and ABI layout,
## so this module can be used as a drop-in replacement for the C API.
##
## The library is loaded at *run time* through `dynlib`, so the C headers do
## **not** need to be installed to compile against this module. Only
## `libdatachannel.so` / `.dylib` / `.dll` has to be reachable by the dynamic
## loader at run time (or passed with `--passL:-L/path/to/lib`).
##
## Pass `-d:RTC_ENABLE_WEBSOCKET` / `-d:RTC_ENABLE_MEDIA` to mirror the
## corresponding compile time options of the C library. The Nim side of the
## bindings does not need them, the flags only exist for feature parity.
##
## Most users want the high-level API re-exported by `libdatachannel` instead.
##

const
  RTC_VERSION_MAJOR* = 0
  RTC_VERSION_MINOR* = 24
  RTC_VERSION_PATCH* = 6

  RTC_VERSION* = $RTC_VERSION_MAJOR & "." & $RTC_VERSION_MINOR & "." &
    $RTC_VERSION_PATCH

const
  libdatachannel_dll* =
    when defined(windows):
      "libdatachannel.dll"
    elif defined(macosx):
      "libdatachannel.dylib"
    else:
      "libdatachannel.so"

const
  RTC_ENABLE_WEBSOCKET* {.booldefine.} = true
  RTC_ENABLE_MEDIA* {.booldefine.} = true

  RTC_DEFAULT_MTU* = 1280 ## IPv6 minimum guaranteed MTU

  RTC_DEFAULT_MAX_FRAGMENT_SIZE* = uint16(RTC_DEFAULT_MTU - 12 - 8 - 40)
    ## SRTP / UDP / IPv6 overhead
  RTC_DEFAULT_MAX_STORED_PACKET_COUNT* = 512
  RTC_DEFAULT_MAXIMUM_FRAGMENT_SIZE* = RTC_DEFAULT_MAX_FRAGMENT_SIZE
    ## Deprecated alias, do not use
  RTC_DEFAULT_MAXIMUM_PACKET_COUNT_FOR_NACK_CACHE* =
    RTC_DEFAULT_MAX_STORED_PACKET_COUNT ## Deprecated alias, do not use

const
  RTC_ERR_SUCCESS* = 0
  RTC_ERR_INVALID* = -1 ## invalid argument
  RTC_ERR_FAILURE* = -2 ## runtime error
  RTC_ERR_NOT_AVAIL* = -3 ## element not available
  RTC_ERR_TOO_SMALL* = -4 ## buffer too small

type
  rtcState* {.size: sizeof(cint).} = enum
    RTC_NEW = 0
    RTC_CONNECTING = 1
    RTC_CONNECTED = 2
    RTC_DISCONNECTED = 3
    RTC_FAILED = 4
    RTC_CLOSED = 5

  rtcIceState* {.size: sizeof(cint).} = enum
    RTC_ICE_NEW = 0
    RTC_ICE_CHECKING = 1
    RTC_ICE_CONNECTED = 2
    RTC_ICE_COMPLETED = 3
    RTC_ICE_FAILED = 4
    RTC_ICE_DISCONNECTED = 5
    RTC_ICE_CLOSED = 6

  rtcGatheringState* {.size: sizeof(cint).} = enum
    RTC_GATHERING_NEW = 0
    RTC_GATHERING_INPROGRESS = 1
    RTC_GATHERING_COMPLETE = 2

  rtcSignalingState* {.size: sizeof(cint).} = enum
    RTC_SIGNALING_STABLE = 0
    RTC_SIGNALING_HAVE_LOCAL_OFFER = 1
    RTC_SIGNALING_HAVE_REMOTE_OFFER = 2
    RTC_SIGNALING_HAVE_LOCAL_PRANSWER = 3
    RTC_SIGNALING_HAVE_REMOTE_PRANSWER = 4

  rtcLogLevel* {.size: sizeof(cint).} = enum
    ## The values must match the plog severities.
    RTC_LOG_NONE = 0
    RTC_LOG_FATAL = 1
    RTC_LOG_ERROR = 2
    RTC_LOG_WARNING = 3
    RTC_LOG_INFO = 4
    RTC_LOG_DEBUG = 5
    RTC_LOG_VERBOSE = 6

  rtcCertificateType* {.size: sizeof(cint).} = enum
    RTC_CERTIFICATE_DEFAULT = 0 ## ECDSA
    RTC_CERTIFICATE_ECDSA = 1
    RTC_CERTIFICATE_RSA = 2

  rtcCodec* {.size: sizeof(cint).} = enum
    # video
    RTC_CODEC_H264 = 0
    RTC_CODEC_VP8 = 1
    RTC_CODEC_VP9 = 2
    RTC_CODEC_H265 = 3
    RTC_CODEC_AV1 = 4
    # audio
    RTC_CODEC_OPUS = 128
    RTC_CODEC_PCMU = 129
    RTC_CODEC_PCMA = 130
    RTC_CODEC_AAC = 131
    RTC_CODEC_G722 = 132

  rtcDirection* {.size: sizeof(cint).} = enum
    RTC_DIRECTION_UNKNOWN = 0
    RTC_DIRECTION_SENDONLY = 1
    RTC_DIRECTION_RECVONLY = 2
    RTC_DIRECTION_SENDRECV = 3
    RTC_DIRECTION_INACTIVE = 4

  rtcTransportPolicy* {.size: sizeof(cint).} = enum
    RTC_TRANSPORT_POLICY_ALL = 0
    RTC_TRANSPORT_POLICY_RELAY = 1

{.push cdecl.}

type
  rtcLogCallbackFunc* = proc (level: rtcLogLevel; message: cstring) {.cdecl.}
  rtcDescriptionCallbackFunc* = proc (pc: cint; sdp: cstring; `type`: cstring;
                                      usePtr: pointer) {.cdecl.}
  rtcCandidateCallbackFunc* = proc (pc: cint; cand: cstring; mid: cstring;
                                    usePtr: pointer) {.cdecl.}
  rtcStateChangeCallbackFunc* = proc (pc: cint; state: rtcState;
                                      usePtr: pointer) {.cdecl.}
  rtcIceStateChangeCallbackFunc* = proc (pc: cint; state: rtcIceState;
                                         usePtr: pointer) {.cdecl.}
  rtcGatheringStateCallbackFunc* = proc (pc: cint; state: rtcGatheringState;
                                         usePtr: pointer) {.cdecl.}
  rtcSignalingStateCallbackFunc* = proc (pc: cint; state: rtcSignalingState;
                                         usePtr: pointer) {.cdecl.}
  rtcDataChannelCallbackFunc* = proc (pc: cint; dc: cint; usePtr: pointer) {.cdecl.}
  rtcTrackCallbackFunc* = proc (pc: cint; tr: cint; usePtr: pointer) {.cdecl.}
  rtcOpenCallbackFunc* = proc (id: cint; usePtr: pointer) {.cdecl.}
  rtcClosedCallbackFunc* = proc (id: cint; usePtr: pointer) {.cdecl.}
  rtcErrorCallbackFunc* = proc (id: cint; error: cstring; usePtr: pointer) {.cdecl.}
  rtcMessageCallbackFunc* = proc (id: cint; message: cstring; size: cint;
                                  usePtr: pointer) {.cdecl.}
  rtcInterceptorCallbackFunc* = proc (pc: cint; message: cstring; size: cint;
                                      usePtr: pointer): pointer {.cdecl.}
  rtcBufferedAmountLowCallbackFunc* = proc (id: cint; usePtr: pointer) {.cdecl.}
  rtcAvailableCallbackFunc* = proc (id: cint; usePtr: pointer) {.cdecl.}
  rtcPliHandlerCallbackFunc* = proc (tr: cint; usePtr: pointer) {.cdecl.}
  rtcRembHandlerCallbackFunc* = proc (tr: cint; bitrate: cuint;
                                      usePtr: pointer) {.cdecl.}

  rtcFrameInfo* {.bycopy.} = object
    timestamp*: uint32
    payloadType*: uint8
    timestampSeconds*: cdouble ## negative means not available

  rtcFrameCallbackFunc* = proc (tr: cint; data: cstring; size: cint;
                                info: ptr rtcFrameInfo;
                                usePtr: pointer) {.cdecl.}

  rtcWebSocketClientCallbackFunc* = proc (wsserver: cint; ws: cint;
                                          usePtr: pointer) {.cdecl.}

{.pop.}

#
#  PeerConnection
#

type
  rtcConfiguration* {.bycopy.} = object
    iceServers*: cstringArray
    iceServersCount*: cint
    proxyServer*: cstring ## libnice only
    bindAddress*: cstring ## libjuice only, NULL means any
    certificateType*: rtcCertificateType
    certificatePemFile*: cstring ## NULL for autogenerated certificate
    keyPemFile*: cstring ## NULL for autogenerated certificate
    keyPemPass*: cstring ## NULL if no pass
    iceTransportPolicy*: rtcTransportPolicy
    enableIceTcp*: bool
    enableIceUdpMux*: bool ## libjuice only
    disableAutoNegotiation*: bool
    forceMediaTransport*: bool
    portRangeBegin*: uint16 ## 0 means automatic
    portRangeEnd*: uint16 ## 0 means automatic
    mtu*: cint ## <= 0 means automatic
    maxMessageSize*: cint ## <= 0 means default
    disableFingerprintVerification*: bool

  rtcLocalDescriptionInit* {.bycopy.} = object
    iceUfrag*: cstring
    icePwd*: cstring

{.push importc, dynlib: libdatachannel_dll.}

proc rtcCreatePeerConnection*(config: ptr rtcConfiguration): cint
  ## Returns the pc id.
proc rtcClosePeerConnection*(pc: cint): cint
proc rtcDeletePeerConnection*(pc: cint): cint

proc rtcSetLocalDescriptionCallback*(pc: cint;
    cb: rtcDescriptionCallbackFunc): cint
proc rtcSetLocalCandidateCallback*(pc: cint; cb: rtcCandidateCallbackFunc): cint
proc rtcSetStateChangeCallback*(pc: cint; cb: rtcStateChangeCallbackFunc): cint
proc rtcSetIceStateChangeCallback*(pc: cint;
    cb: rtcIceStateChangeCallbackFunc): cint
proc rtcSetGatheringStateChangeCallback*(pc: cint;
    cb: rtcGatheringStateCallbackFunc): cint
proc rtcSetSignalingStateChangeCallback*(pc: cint;
    cb: rtcSignalingStateCallbackFunc): cint

proc rtcSetLocalDescription*(pc: cint; `type`: cstring): cint
  ## `type` may be NULL
proc rtcSetLocalDescriptionEx*(pc: cint; `type`: cstring;
    init: ptr rtcLocalDescriptionInit): cint
proc rtcSetRemoteDescription*(pc: cint; sdp: cstring; `type`: cstring): cint
proc rtcAddRemoteCandidate*(pc: cint; cand: cstring; mid: cstring): cint

proc rtcGetLocalDescription*(pc: cint; buffer: cstring; size: cint): cint
proc rtcGetRemoteDescription*(pc: cint; buffer: cstring; size: cint): cint
proc rtcGetLocalDescriptionType*(pc: cint; buffer: cstring; size: cint): cint
proc rtcGetRemoteDescriptionType*(pc: cint; buffer: cstring; size: cint): cint

## For specific use cases only
proc rtcCreateOffer*(pc: cint; buffer: cstring; size: cint): cint
proc rtcCreateAnswer*(pc: cint; buffer: cstring; size: cint): cint

proc rtcGetLocalAddress*(pc: cint; buffer: cstring; size: cint): cint
proc rtcGetRemoteAddress*(pc: cint; buffer: cstring; size: cint): cint
proc rtcGetSelectedCandidatePair*(pc: cint; local: cstring; localSize: cint;
                                  remote: cstring; remoteSize: cint): cint

proc rtcIsNegotiationNeeded*(pc: cint): bool
proc rtcGetMaxDataChannelStream*(pc: cint): cint
proc rtcGetRemoteMaxMessageSize*(pc: cint): cint

{.pop.}

#
#  DataChannel, Track, and WebSocket common API
#

{.push importc, dynlib: libdatachannel_dll.}

proc rtcSetOpenCallback*(id: cint; cb: rtcOpenCallbackFunc): cint
proc rtcSetClosedCallback*(id: cint; cb: rtcClosedCallbackFunc): cint
proc rtcSetErrorCallback*(id: cint; cb: rtcErrorCallbackFunc): cint
proc rtcSetMessageCallback*(id: cint; cb: rtcMessageCallbackFunc): cint
proc rtcSendMessage*(id: cint; data: cstring; size: cint): cint
  ## A negative `size` sends `data` as a text message, a positive one as binary.
proc rtcClose*(id: cint): cint
proc rtcDelete*(id: cint): cint
proc rtcIsOpen*(id: cint): bool
proc rtcIsClosed*(id: cint): bool
proc rtcMaxMessageSize*(id: cint): cint
proc rtcGetBufferedAmount*(id: cint): cint ## total size buffered to send
proc rtcSetBufferedAmountLowThreshold*(id: cint; amount: cint): cint
proc rtcSetBufferedAmountLowCallback*(id: cint;
    cb: rtcBufferedAmountLowCallbackFunc): cint

#
#  DataChannel, Track, and WebSocket common extended API
#

proc rtcGetAvailableAmount*(id: cint): cint ## total size available to receive
proc rtcSetAvailableCallback*(id: cint; cb: rtcAvailableCallbackFunc): cint
proc rtcReceiveMessage*(id: cint; buffer: cstring; size: ptr cint): cint

{.pop.}

#
#  DataChannel
#

type
  rtcReliability* {.bycopy.} = object
    unordered*: bool
    unreliable*: bool
    maxPacketLifeTime*: cuint ## ignored if reliable
    maxRetransmits*: cuint ## ignored if reliable

  rtcDataChannelInit* {.bycopy.} = object
    reliability*: rtcReliability
    protocol*: cstring ## empty string if NULL
    negotiated*: bool
    manualStream*: bool
    stream*: uint16 ## numeric ID 0-65534, ignored if manualStream is false

{.push importc, dynlib: libdatachannel_dll.}

proc rtcSetDataChannelCallback*(pc: cint; cb: rtcDataChannelCallbackFunc): cint
proc rtcCreateDataChannel*(pc: cint; label: cstring): cint
  ## Returns the dc id.
proc rtcCreateDataChannelEx*(pc: cint; label: cstring;
                             init: ptr rtcDataChannelInit): cint
  ## Returns the dc id.
proc rtcDeleteDataChannel*(dc: cint): cint

proc rtcGetDataChannelStream*(dc: cint): cint
proc rtcGetDataChannelLabel*(dc: cint; buffer: cstring; size: cint): cint
proc rtcGetDataChannelProtocol*(dc: cint; buffer: cstring; size: cint): cint
proc rtcGetDataChannelReliability*(dc: cint;
                                   reliability: ptr rtcReliability): cint

{.pop.}

#
#  Track
#

type
  rtcTrackInit* {.bycopy.} = object
    direction*: rtcDirection
    codec*: rtcCodec
    payloadType*: cint
    ssrc*: uint32
    mid*: cstring
    name*: cstring ## optional
    msid*: cstring ## optional
    trackId*: cstring ## optional, track ID used in MSID
    profile*: cstring ## optional, codec profile

{.push importc, dynlib: libdatachannel_dll.}

proc rtcSetTrackCallback*(pc: cint; cb: rtcTrackCallbackFunc): cint
proc rtcAddTrack*(pc: cint; mediaDescriptionSdp: cstring): cint
  ## Returns the tr id.
proc rtcAddTrackEx*(pc: cint; init: ptr rtcTrackInit): cint
  ## Returns the tr id.
proc rtcDeleteTrack*(tr: cint): cint

proc rtcGetTrackDescription*(tr: cint; buffer: cstring; size: cint): cint
proc rtcGetTrackMid*(tr: cint; buffer: cstring; size: cint): cint
proc rtcGetTrackDirection*(tr: cint; direction: ptr rtcDirection): cint

proc rtcRequestKeyframe*(tr: cint): cint
proc rtcRequestBitrate*(tr: cint; bitrate: cuint): cint
proc rtcSetFrameCallback*(tr: cint; cb: rtcFrameCallbackFunc): cint

{.pop.}

#
#  Media
#

type
  rtcObuPacketization* {.size: sizeof(cint).} = enum
    ## Define how OBUs are packetized in an AV1 sample
    RTC_OBU_PACKETIZED_OBU = 0
    RTC_OBU_PACKETIZED_TEMPORAL_UNIT = 1

  rtcNalUnitSeparator* {.size: sizeof(cint).} = enum
    ## Define how NAL units are separated in an H264/H265 sample
    RTC_NAL_SEPARATOR_LENGTH = 0 ## first 4 bytes are NAL unit length
    RTC_NAL_SEPARATOR_LONG_START_SEQUENCE = 1 ## 0x00, 0x00, 0x00, 0x01
    RTC_NAL_SEPARATOR_SHORT_START_SEQUENCE = 2 ## 0x00, 0x00, 0x01
    RTC_NAL_SEPARATOR_START_SEQUENCE = 3 ## long or short start sequence

  rtcPacketizerInit* {.bycopy.} = object
    ssrc*: uint32
    cname*: cstring
    payloadType*: uint8
    clockRate*: uint32
    sequenceNumber*: uint16
    timestamp*: uint32
    ## H264, H265, AV1
    maxFragmentSize*: uint16 ## Maximum fragment size, 0 means default
    ## H264/H265 only
    nalSeparator*: rtcNalUnitSeparator ## NAL unit separator
    ## AV1 only
    obuPacketization*: rtcObuPacketization ## OBU packetization for AV1 samples
    playoutDelayId*: uint8
    playoutDelayMin*: uint16
    playoutDelayMax*: uint16
    colorSpaceId*: uint8
    colorChromaSitingHorz*: uint8
    colorChromaSitingVert*: uint8
    colorRange*: uint8
    colorPrimaries*: uint8
    colorTransfer*: uint8
    colorMatrix*: uint8

  rtcPacketizationHandlerInit* = rtcPacketizerInit
    ## Deprecated, do not use

  rtcSsrcForTypeInit* {.bycopy.} = object
    ssrc*: uint32
    name*: cstring ## optional
    msid*: cstring ## optional
    trackId*: cstring ## optional, track ID used in MSID

  rtcMessage* = pointer
    ## Opaque type used (via `rtcMessage*`) to reference an `rtc::Message`

{.push importc, dynlib: libdatachannel_dll.}

proc rtcCreateOpaqueMessage*(data: pointer; size: cint): ptr rtcMessage
  ## Allocate a new opaque message. Must be explicitly freed with
  ## `rtcDeleteOpaqueMessage` unless explicitly returned by a media
  ## interceptor callback.
proc rtcDeleteOpaqueMessage*(msg: ptr rtcMessage)

proc rtcSetMediaInterceptorCallback*(id: cint;
                                     cb: rtcInterceptorCallbackFunc): cint
  ## Set a MediaInterceptor on the peer connection.

# Set a packetizer on a track
proc rtcSetH264Packetizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetH265Packetizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetAV1Packetizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetVP8Packetizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetVP9Packetizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetOpusPacketizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetAACPacketizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetPCMUPacketizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetPCMAPacketizer*(tr: cint; init: ptr rtcPacketizerInit): cint
proc rtcSetG722Packetizer*(tr: cint; init: ptr rtcPacketizerInit): cint

# Set a depacketizer on a track
proc rtcSetH264Depacketizer*(tr: cint;
                              nalSeparator: rtcNalUnitSeparator): cint
proc rtcSetH265Depacketizer*(tr: cint;
                              nalSeparator: rtcNalUnitSeparator): cint
proc rtcSetVP8Depacketizer*(tr: cint): cint
proc rtcSetVP9Depacketizer*(tr: cint): cint
proc rtcSetAV1Depacketizer*(tr: cint;
                            obuPacketization: rtcObuPacketization): cint
proc rtcSetOpusDepacketizer*(tr: cint): cint
proc rtcSetAACDepacketizer*(tr: cint): cint
proc rtcSetPCMUDepacketizer*(tr: cint): cint
proc rtcSetPCMADepacketizer*(tr: cint): cint
proc rtcSetG722Depacketizer*(tr: cint): cint

# Chain handlers on a track
proc rtcChainRtcpReceivingSession*(tr: cint): cint
proc rtcChainRtcpSrReporter*(tr: cint): cint
proc rtcChainRtcpNackResponder*(tr: cint;
                                 maxStoredPacketsCount: cuint): cint
proc rtcChainPliHandler*(tr: cint; cb: rtcPliHandlerCallbackFunc): cint
proc rtcChainRembHandler*(tr: cint; cb: rtcRembHandlerCallbackFunc): cint
proc rtcChainPacingHandler*(tr: cint; bitsPerSecond: cdouble;
                            sendIntervalMs: cint): cint

# Timestamps
proc rtcTransformSecondsToTimestamp*(id: cint; seconds: cdouble;
                                    timestamp: ptr uint32): cint
proc rtcTransformTimestampToSeconds*(id: cint; timestamp: uint32;
                                    seconds: ptr cdouble): cint
proc rtcGetCurrentTrackTimestamp*(id: cint; timestamp: ptr uint32): cint
proc rtcSetTrackRtpTimestamp*(id: cint; timestamp: uint32): cint
proc rtcGetLastTrackSenderReportTimestamp*(id: cint;
    timestamp: ptr uint32): cint
proc rtcGetTrackRtcpSyncTimestamps*(tr: cint; rtpTimestamp,
                                    ntpTimestamp: ptr uint64): cint

# SDP / RTP introspection helpers
proc rtcGetTrackPayloadTypesForCodec*(tr: cint; ccodec: cstring;
                                      buffer: ptr cint; size: cint): cint
proc rtcGetSsrcsForTrack*(tr: cint; buffer: ptr uint32; count: cint): cint
proc rtcGetCNameForSsrc*(tr: cint; ssrc: uint32; cname: cstring;
                         cnameSize: cint): cint
proc rtcGetPayloadTypesForCodec*(sdp: cstring; ccodec: cstring;
                                 buffer: ptr cint; size: cint): cint
proc rtcGetSsrcsForType*(mediaType: cstring; sdp: cstring;
                         buffer: ptr uint32; bufferSize: cint): cint
proc rtcSetSsrcForType*(mediaType: cstring; sdp: cstring; buffer: cstring;
                        bufferSize: cint; init: ptr rtcSsrcForTypeInit): cint

proc rtcSetNeedsToSendRtcpSr*(id: cint): cint
  ## Deprecated, do not use

{.pop.}

#
#  WebSocket
#

type
  rtcWsConfiguration* {.bycopy.} = object
    disableTlsVerification*: bool ## if true, don't verify the TLS certificate
    proxyServer*: cstring ## only non-authenticated http supported for now
    protocols*: cstringArray
    protocolsCount*: cint
    tcpConnectionTimeoutMs*: cint ## 0 means default, < 0 means disabled
    connectionTimeoutMs*: cint ## 0 means default, < 0 means disabled
    pingIntervalMs*: cint ## 0 means default, < 0 means disabled
    maxOutstandingPings*: cint ## 0 means default, < 0 means disabled
    maxMessageSize*: cint ## <= 0 means default

{.push importc, dynlib: libdatachannel_dll.}

proc rtcCreateWebSocket*(url: cstring): cint
  ## Returns the ws id.
proc rtcCreateWebSocketEx*(url: cstring; config: ptr rtcWsConfiguration): cint
  ## Returns the ws id.
proc rtcDeleteWebSocket*(ws: cint): cint
proc rtcGetWebSocketRemoteAddress*(ws: cint; buffer: cstring; size: cint): cint
proc rtcGetWebSocketPath*(ws: cint; buffer: cstring; size: cint): cint

{.pop.}

#
#  WebSocketServer
#

type
  rtcWsServerConfiguration* {.bycopy.} = object
    port*: uint16 ## 0 means automatic selection
    enableTls*: bool ## if true, enable TLS (WSS)
    certificatePemFile*: cstring ## NULL for autogenerated certificate
    keyPemFile*: cstring ## NULL for autogenerated certificate
    keyPemPass*: cstring ## NULL if no pass
    bindAddress*: cstring ## NULL for any
    connectionTimeoutMs*: cint ## 0 means default, < 0 means disabled
    maxMessageSize*: cint ## <= 0 means default

{.push importc, dynlib: libdatachannel_dll.}

proc rtcCreateWebSocketServer*(config: ptr rtcWsServerConfiguration;
    cb: rtcWebSocketClientCallbackFunc): cint
  ## Returns the wsserver id.
proc rtcDeleteWebSocketServer*(wsserver: cint): cint
proc rtcGetWebSocketServerPort*(wsserver: cint): cint

{.pop.}

#
#  Global settings
#

type
  rtcSctpSettings* {.bycopy.} = object
    recvBufferSize*: cint ## in bytes, <= 0 means optimized default
    sendBufferSize*: cint ## in bytes, <= 0 means optimized default
    maxChunksOnQueue*: cint ## in chunks, <= 0 means optimized default
    initialCongestionWindow*: cint ## in MTUs, <= 0 means optimized default
    maxBurst*: cint ## in MTUs, 0 means optimized default, < 0 means disabled
    congestionControlModule*: cint
      ## 0: RFC2581 (default), 1: HSTCP, 2: H-TCP, 3: RTCC
    delayedSackTimeMs*: cint ## in msecs, 0 means optimized default, < 0 means disabled
    minRetransmitTimeoutMs*: cint ## in msecs, <= 0 means optimized default
    maxRetransmitTimeoutMs*: cint ## in msecs, <= 0 means optimized default
    initialRetransmitTimeoutMs*: cint ## in msecs, <= 0 means optimized default
    maxRetransmitAttempts*: cint ## number of retransmissions, <= 0 means optimized default
    heartbeatIntervalMs*: cint ## in msecs, <= 0 means optimized default

{.push importc, dynlib: libdatachannel_dll.}

proc rtcSetThreadPoolSize*(count: cuint): cint
  ## Note: applied when threads are spawned.

proc rtcSetSctpSettings*(settings: ptr rtcSctpSettings): cint
  ## Note: SCTP settings apply to newly-created PeerConnections only.

proc rtcPreload*(): bool
  ## Optional global preload. Returns `true` when this call is the one that
  ## initialised the library, and `false` when it was already initialised.
proc rtcCleanup*()
  ## Optional global cleanup. Everything created afterwards must be released
  ## first.

#
#  Log
#

proc rtcInitLogger*(level: rtcLogLevel; cb: rtcLogCallbackFunc)
  ## Install a log callback. A `nil` callback on the first call logs to stdout.

#
#  User pointer
#

proc rtcSetUserPointer*(id: cint; usePtr: pointer)
proc rtcGetUserPointer*(i: cint): pointer

{.pop.}

when isMainModule:
  echo "libdatachannel bindings for RTC_VERSION ", RTC_VERSION