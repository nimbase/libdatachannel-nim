## High-level DataChannel API.
##

import ./bindings, ./utils, ./channel

type
  DataChannelId* = ChannelId

  DataChannel* = ref object of RtcChannel
    ## A WebRTC DataChannel. Either created locally through
    ## `PeerConnection.createDataChannel` or announced to
    ## `PeerConnection.onDataChannel`.

  Reliability* = object
    ## Reliability settings of a DataChannel.
    unordered*: bool
      ## Allow messages to be delivered out of order.
    unreliable*: bool
      ## Do not retransmit lost messages.
    maxPacketLifeTime*: int
      ## Maximum time in milliseconds to retransmit a lost message.
      ## Ignored if `unreliable` is `false`.
    maxRetransmits*: int
      ## Maximum number of retransmissions for a lost message.
      ## Ignored if `unreliable` is `false`.

  DataChannelInit* = object
    ## Optional parameters of a DataChannel.
    reliability*: Reliability
    protocol*: string
      ## Sub-protocol name, empty for none.
    negotiated*: bool
      ## Create the channel out of band, skipping the `onDataChannel` event.
    manualStream*: bool
      ## Use the explicit `stream` id instead of an automatically assigned one.
    stream*: uint16
      ## Stream id in the range 0-65534. Only used if `manualStream` is `true`.

  DataChannelListener* = enum
    ## Selectable callback slots for `DataChannel.listen`.
    dcOpened, dcMessage, dcClosed, dcError

proc toRtc(init: Reliability): rtcReliability =
  rtcReliability(
    unordered: init.unordered,
    unreliable: init.unreliable,
    maxPacketLifeTime: cuint(max(init.maxPacketLifeTime, 0)),
    maxRetransmits: cuint(max(init.maxRetransmits, 0)))

proc toNim*(rel: rtcReliability): Reliability =
  Reliability(unordered: rel.unordered, unreliable: rel.unreliable,
    maxPacketLifeTime: int(rel.maxPacketLifeTime),
    maxRetransmits: int(rel.maxRetransmits))

proc initDataChannel*(pcId: cint; label: string;
    init: DataChannelInit = DataChannelInit()): DataChannelId =
  ## Raw variant of `PeerConnection.createDataChannel` taking the
  ## PeerConnection id directly. Returns the new channel id, or a negative
  ## libdatachannel error code.
  var protocol = cstringOrNil(init.protocol)
  var rtcInit = rtcDataChannelInit(
    reliability: init.reliability.toRtc(),
    protocol: protocol,
    negotiated: init.negotiated,
    manualStream: init.manualStream,
    stream: init.stream)
  rtcCreateDataChannelEx(pcId, cstring(label), addr rtcInit)

proc label*(dc: DataChannel): string =
  ## The label of the DataChannel.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetDataChannelLabel(dc.id, cast[cstring](buffer), size))

proc protocol*(dc: DataChannel): string =
  ## The sub-protocol negotiated for this DataChannel.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetDataChannelProtocol(dc.id, cast[cstring](buffer), size))

proc stream*(dc: DataChannel): int =
  ## The SCTP stream id of the DataChannel.
  int(rtcGetDataChannelStream(dc.id))

proc reliability*(dc: DataChannel): Reliability =
  ## The reliability settings in use.
  var rel: rtcReliability
  check rtcGetDataChannelReliability(dc.id, addr rel)
  rel.toNim()

proc listen*(dc: DataChannel; listener: DataChannelListener;
             callback: rtcOpenCallbackFunc | rtcClosedCallbackFunc) =
  ## Listen for open/closed events using a raw libdatachannel callback.
  case listener
  of dcOpened: check rtcSetOpenCallback(dc.id, callback)
  of dcClosed: check rtcSetClosedCallback(dc.id, callback)
  else: raise newException(LibDataChannelError,
    "listener " & $listener & " needs a matching callback signature")

proc listen*(dc: DataChannel; listener: DataChannelListener;
             callback: rtcMessageCallbackFunc) =
  ## Listen for messages using a raw libdatachannel callback.
  case listener
  of dcMessage: check rtcSetMessageCallback(dc.id, callback)
  else: raise newException(LibDataChannelError,
    "listener " & $listener & " needs a matching callback signature")

proc listen*(dc: DataChannel; listener: DataChannelListener;
             callback: rtcErrorCallbackFunc) =
  ## Listen for errors using a raw libdatachannel callback.
  case listener
  of dcError: check rtcSetErrorCallback(dc.id, callback)
  else: raise newException(LibDataChannelError,
    "listener " & $listener & " needs a matching callback signature")