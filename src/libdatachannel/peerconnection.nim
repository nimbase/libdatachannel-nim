## High-level PeerConnection API: signaling, negotiation and media routing.
##

import std/[locks, options, strutils, tables]
import ./bindings, ./utils, ./channel, ./datachannel, ./track

type
  PeerConnectionId* = cint

  PeerConnectionConfig* = object
    ## Nim friendly counterpart of `rtcConfiguration`. An empty string is
    ## passed to libdatachannel as `NULL`, which means "automatic" everywhere.
    iceServers*: seq[string]
      ## STUN / TURN URLs, for example `@["stun:stun.l.google.com:19302"]`.
    proxyServer*: string
      ## libnice only.
    bindAddress*: string
      ## libjuice only, empty means any address.
    certificateType*: rtcCertificateType
    certificatePemFile*: string
    keyPemFile*: string
    keyPemPass*: string
    iceTransportPolicy*: rtcTransportPolicy
    enableIceTcp*: bool
    enableIceUdpMux*: bool
      ## libjuice only.
    disableAutoNegotiation*: bool
      ## Renegotiation is not triggered automatically.
    forceMediaTransport*: bool
    portRangeBegin*: uint16
      ## 0 means automatic.
    portRangeEnd*: uint16
      ## 0 means automatic.
    mtu*: int
      ## <= 0 means automatic.
    maxMessageSize*: int
      ## <= 0 means the default.
    disableFingerprintVerification*: bool

  PeerConnection* = ref object of RootObj
    ## A WebRTC peer connection. It owns the DataChannels and Tracks it
    ## creates, and the ones the remote peer announces.
    id*: PeerConnectionId
    config*: PeerConnectionConfig
    state*: rtcState
      ## Last state reported through `onStateChange`.
    iceState*: rtcIceState
      ## Last ICE state reported through `onIceStateChange`.
    gatheringState*: rtcGatheringState
      ## Last gathering state reported through `onGatheringStateChange`.
    signalingState*: rtcSignalingState
      ## Last signaling state reported through `onSignalingStateChange`.
    dataChannels*: Table[DataChannelId, DataChannel]
    tracks*: Table[TrackId, Track]
    onLocalDescription*: proc (sdp: string; kind: SdpType) {.closure.}
      ## Fired once the local SDP offer/answer is ready to be signaled.
    onLocalCandidate*: proc (candidate: string; mid: string) {.closure.}
      ## Fired for every gathered ICE candidate. A `nil` candidate signals the
      ## end of gathering.
    onStateChange*: proc (state: rtcState) {.closure.}
    onIceStateChange*: proc (state: rtcIceState) {.closure.}
    onGatheringStateChange*: proc (state: rtcGatheringState) {.closure.}
    onSignalingStateChange*: proc (state: rtcSignalingState) {.closure.}
    onDataChannel*: proc (dc: DataChannel) {.closure.}
      ## Fired when the remote peer opens a DataChannel.
    onTrack*: proc (tr: Track) {.closure.}
      ## Fired when the remote peer sends media.
    rawConfig: rtcConfiguration
      ## The C struct handed to libdatachannel. Its `cstring` members point
      ## into `strings`, which is kept alive for as long as the connection is.
    strings: seq[string]
    iceServers: cstringArray
    lock: Lock

proc initPeerConnection*(config: PeerConnectionConfig): PeerConnection =
  ## Create a PeerConnection from a Nim friendly configuration.
  ## The low-level handlers still have to be installed, see
  ## `PeerConnection.installCallbacks`.
  new(result)
  initLock(result.lock)
  result.config = config
  # The C struct borrows these strings, so they must outlive the connection.
  result.strings = @[
    config.proxyServer,
    config.bindAddress,
    config.certificatePemFile,
    config.keyPemFile,
    config.keyPemPass]
  result.iceServers = toCStringArray(config.iceServers)
  result.rawConfig = rtcConfiguration(
    iceServers: result.iceServers,
    iceServersCount: cint(config.iceServers.len),
    proxyServer: cstringOrNil(result.strings[0]),
    bindAddress: cstringOrNil(result.strings[1]),
    certificateType: config.certificateType,
    certificatePemFile: cstringOrNil(result.strings[2]),
    keyPemFile: cstringOrNil(result.strings[3]),
    keyPemPass: cstringOrNil(result.strings[4]),
    iceTransportPolicy: config.iceTransportPolicy,
    enableIceTcp: config.enableIceTcp,
    enableIceUdpMux: config.enableIceUdpMux,
    disableAutoNegotiation: config.disableAutoNegotiation,
    forceMediaTransport: config.forceMediaTransport,
    portRangeBegin: config.portRangeBegin,
    portRangeEnd: config.portRangeEnd,
    mtu: cint(config.mtu),
    maxMessageSize: cint(config.maxMessageSize),
    disableFingerprintVerification: config.disableFingerprintVerification)
  result.id = rtcCreatePeerConnection(addr result.rawConfig)
  if result.id < 0:
    if result.iceServers != nil: freeCStringArray(result.iceServers)
    raise newException(LibDataChannelError,
      "failed to create a PeerConnection (" & errorCode(result.id) & ")")

proc initPeerConnection*(config: ptr rtcConfiguration): PeerConnection =
  ## Create a PeerConnection from a raw `rtcConfiguration`. The caller keeps
  ## every string referenced by `config` alive.
  new(result)
  initLock(result.lock)
  result.id = rtcCreatePeerConnection(config)
  if result.id < 0:
    raise newException(LibDataChannelError,
      "failed to create a PeerConnection (" & errorCode(result.id) & ")")

#
#  Callback trampolines
#

#
#  Every trampoline below prepares the thread *before* its first allocation,
#  not just around the user handler: announcing a DataChannel or Track already
#  allocates the wrapper object.
#

proc localDescriptionTrampoline(pc: cint; sdp, kind: cstring;
                                usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil or obj.onLocalDescription.isNil: return
    obj.onLocalDescription($sdp, kind.toSdpType)

proc localCandidateTrampoline(pc: cint; cand, mid: cstring;
                              usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil or obj.onLocalCandidate.isNil: return
    obj.onLocalCandidate($cand, $mid)

proc stateChangeTrampoline(pc: cint; state: rtcState;
                           usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil: return
    obj.state = state
    if obj.onStateChange != nil:
      obj.onStateChange(state)

proc iceStateChangeTrampoline(pc: cint; state: rtcIceState;
                              usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil: return
    obj.iceState = state
    if obj.onIceStateChange != nil:
      obj.onIceStateChange(state)

proc gatheringStateTrampoline(pc: cint; state: rtcGatheringState;
                               usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil: return
    obj.gatheringState = state
    if obj.onGatheringStateChange != nil:
      obj.onGatheringStateChange(state)

proc signalingStateTrampoline(pc: cint; state: rtcSignalingState;
                              usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil: return
    obj.signalingState = state
    if obj.onSignalingStateChange != nil:
      obj.onSignalingStateChange(state)

proc dataChannelTrampoline(pc: cint; dc: cint;
                           usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil or dc < 0: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil: return
    var newChannel = DataChannel()
    newChannel.id = dc
    initChannel(newChannel, dc)
    acquire(obj.lock)
    obj.dataChannels[dc] = newChannel
    release(obj.lock)
    # Never call into user code while holding the lock.
    if obj.onDataChannel != nil:
      obj.onDataChannel(newChannel)

proc trackTrampoline(pc: cint; tr: cint; usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil or tr < 0: return
    let obj = cast[PeerConnection](usePtr)
    if obj.isNil: return
    var newTrack = Track()
    newTrack.id = tr
    initChannel(newTrack, tr)
    acquire(obj.lock)
    obj.tracks[tr] = newTrack
    release(obj.lock)
    if obj.onTrack != nil:
      obj.onTrack(newTrack)

proc installCallbacks*(pc: PeerConnection) =
  ## Route every libdatachannel callback to the high-level handlers of `pc`.
  ## Called automatically by `newPeerConnection`.
  registerOwner(pc.id, pc)
  rtcSetUserPointer(pc.id, cast[pointer](pc))
  discard rtcSetLocalDescriptionCallback(pc.id, localDescriptionTrampoline)
  discard rtcSetLocalCandidateCallback(pc.id, localCandidateTrampoline)
  discard rtcSetStateChangeCallback(pc.id, stateChangeTrampoline)
  discard rtcSetIceStateChangeCallback(pc.id, iceStateChangeTrampoline)
  discard rtcSetGatheringStateChangeCallback(pc.id, gatheringStateTrampoline)
  discard rtcSetSignalingStateChangeCallback(pc.id, signalingStateTrampoline)
  discard rtcSetDataChannelCallback(pc.id, dataChannelTrampoline)
  discard rtcSetTrackCallback(pc.id, trackTrampoline)

proc newPeerConnection*(config: PeerConnectionConfig = PeerConnectionConfig()): PeerConnection =
  ## Create a PeerConnection ready to negotiate through `setLocalDescription`.
  result = initPeerConnection(config)
  result.installCallbacks()

proc newPeerConnection*(config: ptr rtcConfiguration): PeerConnection =
  ## Create a PeerConnection from a raw `rtcConfiguration`.
  result = initPeerConnection(config)
  result.installCallbacks()

#
#  Lifecycle
#

proc close*(pc: PeerConnection) =
  ## Close and delete the PeerConnection together with every channel it owns.
  if pc.isNil or pc.id < 0: return
  let id = pc.id
  # Stop the callbacks before anything is destroyed, then drop our reference
  # only once libdatachannel has released the id.
  rtcSetUserPointer(id, nil)
  discard rtcSetLocalDescriptionCallback(id, nil)
  discard rtcSetLocalCandidateCallback(id, nil)
  discard rtcSetStateChangeCallback(id, nil)
  discard rtcSetIceStateChangeCallback(id, nil)
  discard rtcSetGatheringStateChangeCallback(id, nil)
  discard rtcSetSignalingStateChangeCallback(id, nil)
  discard rtcSetDataChannelCallback(id, nil)
  discard rtcSetTrackCallback(id, nil)
  acquire(pc.lock)
  let channels = pc.dataChannels
  let tracks = pc.tracks
  pc.dataChannels.clear()
  pc.tracks.clear()
  release(pc.lock)
  for _, dc in channels:
    detachChannel(dc)
  for _, tr in tracks:
    detachChannel(tr)
  discard rtcClosePeerConnection(id)
  discard rtcDeletePeerConnection(id)
  unregisterOwner(id)
  # Break the reference cycles that appear when a handler captures `pc`.
  pc.onLocalDescription = nil
  pc.onLocalCandidate = nil
  pc.onStateChange = nil
  pc.onIceStateChange = nil
  pc.onGatheringStateChange = nil
  pc.onSignalingStateChange = nil
  pc.onDataChannel = nil
  pc.onTrack = nil
  if pc.iceServers != nil:
    freeCStringArray(pc.iceServers)
    pc.iceServers = nil
  pc.state = RTC_CLOSED
  pc.id = -1

proc isNegotiationNeeded*(pc: PeerConnection): bool =
  ## Whether the connection wants a new offer/answer round.
  rtcIsNegotiationNeeded(pc.id)

proc localAddress*(pc: PeerConnection): string =
  ## The local address currently selected.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetLocalAddress(pc.id, cast[cstring](buffer), size))

proc remoteAddress*(pc: PeerConnection): string =
  ## The remote address currently selected.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetRemoteAddress(pc.id, cast[cstring](buffer), size))

proc selectedCandidatePair*(pc: PeerConnection): tuple[local, remote: string] =
  ## The currently selected local and remote ICE candidates, in the form used
  ## by SDP and by `PeerConnection.addRemoteCandidate`. Empty until a candidate
  ## pair has been selected.
  template strip(s: string): string =
    ## libdatachannel frames candidates as `a=candidate:...`.
    if s.startsWith("a="): s[2 .. ^1] else: s

  result = (
    local: strip(getCString(proc (buffer: pointer; size: cint): cint =
      rtcGetSelectedCandidatePair(pc.id, cast[cstring](buffer), size, nil, 0))),
    remote: strip(getCString(proc (buffer: pointer; size: cint): cint =
      rtcGetSelectedCandidatePair(pc.id, nil, 0, cast[cstring](buffer), size))))

proc maxDataChannelStream*(pc: PeerConnection): int =
  ## The highest SCTP stream id the remote peer supports.
  int(rtcGetMaxDataChannelStream(pc.id))

proc remoteMaxMessageSize*(pc: PeerConnection): int =
  ## The maximum message size the remote peer accepts.
  int(rtcGetRemoteMaxMessageSize(pc.id))

#
#  Negotiation
#

proc setLocalDescription*(pc: PeerConnection;
                          kind: Option[SdpType] = none(SdpType)) =
  ## Produce the local description. `kind` may be `none` to let libdatachannel
  ## decide, which means an offer unless the remote already sent one.
  if kind.isSome():
    check rtcSetLocalDescription(pc.id, cstring($kind.get()))
  else:
    check rtcSetLocalDescription(pc.id, nil)

proc setLocalDescription*(pc: PeerConnection; kind: SdpType) =
  ## Produce the local description with an explicit `sdpOffer` or `sdpAnswer`.
  pc.setLocalDescription(some(kind))

proc setLocalDescription*(pc: PeerConnection; iceUfrag, icePwd: string) =
  ## Produce the local description with fixed ICE credentials.
  var ufrag = cstring(iceUfrag)
  var pwd = cstring(icePwd)
  var init = rtcLocalDescriptionInit(iceUfrag: ufrag, icePwd: pwd)
  check rtcSetLocalDescriptionEx(pc.id, nil, addr init)

proc setRemoteDescription*(pc: PeerConnection; sdp: string;
                           kind: SdpType = sdpOffer) =
  ## Apply a description received from the remote peer.
  check rtcSetRemoteDescription(pc.id, cstring(sdp), cstring($kind))

proc addRemoteCandidate*(pc: PeerConnection; candidate, mid: string) =
  ## Feed a remote ICE candidate into the connection.
  check rtcAddRemoteCandidate(pc.id, cstring(candidate), cstringOrNil(mid))

proc localDescription*(pc: PeerConnection): string =
  ## The local SDP, available once `setLocalDescription` completed.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetLocalDescription(pc.id, cast[cstring](buffer), size))

proc remoteDescription*(pc: PeerConnection): string =
  ## The remote SDP.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetRemoteDescription(pc.id, cast[cstring](buffer), size))

proc localDescriptionType*(pc: PeerConnection): string =
  ## The type of the local description, "offer" or "answer".
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetLocalDescriptionType(pc.id, cast[cstring](buffer), size))

proc remoteDescriptionType*(pc: PeerConnection): string =
  ## The type of the remote description.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetRemoteDescriptionType(pc.id, cast[cstring](buffer), size))

proc createOffer*(pc: PeerConnection): string =
  ## Build an SDP offer without applying it.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcCreateOffer(pc.id, cast[cstring](buffer), size))

proc createAnswer*(pc: PeerConnection): string =
  ## Build an SDP answer without applying it.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcCreateAnswer(pc.id, cast[cstring](buffer), size))

#
#  DataChannels
#

proc createDataChannel*(pc: PeerConnection; label: string;
                        init: DataChannelInit = DataChannelInit()): DataChannel =
  ## Open a DataChannel. The remote peer is notified through `onDataChannel`.
  var id = initDataChannel(pc.id, label, init)
  check id
  new(result)
  result.id = id
  initChannel(result, id)
  acquire(pc.lock)
  pc.dataChannels[id] = result
  release(pc.lock)

proc dataChannel*(pc: PeerConnection; id: DataChannelId): DataChannel =
  ## Look up a DataChannel by its libdatachannel id.
  acquire(pc.lock)
  result = pc.dataChannels[id]
  release(pc.lock)

#
#  Tracks
#

proc addTrack*(pc: PeerConnection; init: rtcTrackInit): Track =
  ## Add a media track from a raw `rtcTrackInit`. The caller keeps the strings
  ## referenced by `init` alive for as long as the PeerConnection lives.
  var id = rtcAddTrackEx(pc.id, addr init)
  check id
  new(result)
  result.id = id
  result.codec = init.codec
  initChannel(result, id)
  acquire(pc.lock)
  pc.tracks[id] = result
  release(pc.lock)

proc addTrack*(pc: PeerConnection; codec: rtcCodec;
               init: PacketizerInit = PacketizerInit()): Track =
  ## Add a media track for `codec` and install the matching packetizer.
  var trackInit = rtcTrackInit(
    direction: RTC_DIRECTION_SENDRECV,
    codec: codec,
    payloadType: cint(init.payloadType),
    ssrc: init.ssrc,
    mid: nil,
    name: nil,
    msid: nil,
    trackId: nil)
  result = pc.addTrack(trackInit)
  case codec
  of RTC_CODEC_H264: result.setH264Packetizer(init)
  of RTC_CODEC_H265: result.setH265Packetizer(init)
  of RTC_CODEC_AV1: result.setAV1Packetizer(init)
  of RTC_CODEC_VP8: result.setVP8Packetizer(init)
  of RTC_CODEC_VP9: result.setVP9Packetizer(init)
  of RTC_CODEC_OPUS: result.setOpusPacketizer(init)
  of RTC_CODEC_AAC: result.setAACPacketizer(init)
  of RTC_CODEC_PCMU: result.setPCMUPacketizer(init)
  of RTC_CODEC_PCMA: result.setPCMAPacketizer(init)
  of RTC_CODEC_G722: result.setG722Packetizer(init)

proc addTrack*(pc: PeerConnection; mediaDescriptionSdp: string): Track =
  ## Add a media track described by a raw SDP media section.
  var id = rtcAddTrack(pc.id, cstring(mediaDescriptionSdp))
  check id
  new(result)
  result.id = id
  initChannel(result, id)
  acquire(pc.lock)
  pc.tracks[id] = result
  release(pc.lock)

proc track*(pc: PeerConnection; id: TrackId): Track =
  ## Look up a Track by its libdatachannel id.
  acquire(pc.lock)
  result = pc.tracks[id]
  release(pc.lock)

#
#  Raw callback access
#
#  Use these to replace the Nim handlers with plain `cdecl` functions.
#

proc setLocalDescriptionCallback*(pc: PeerConnection;
    cb: rtcDescriptionCallbackFunc) =
  check rtcSetLocalDescriptionCallback(pc.id, cb)

proc setLocalCandidateCallback*(pc: PeerConnection;
    cb: rtcCandidateCallbackFunc) =
  check rtcSetLocalCandidateCallback(pc.id, cb)

proc setStateChangeCallback*(pc: PeerConnection;
    cb: rtcStateChangeCallbackFunc) =
  check rtcSetStateChangeCallback(pc.id, cb)

proc setIceStateChangeCallback*(pc: PeerConnection;
    cb: rtcIceStateChangeCallbackFunc) =
  check rtcSetIceStateChangeCallback(pc.id, cb)

proc setGatheringStateChangeCallback*(pc: PeerConnection;
    cb: rtcGatheringStateCallbackFunc) =
  check rtcSetGatheringStateChangeCallback(pc.id, cb)

proc setSignalingStateChangeCallback*(pc: PeerConnection;
    cb: rtcSignalingStateCallbackFunc) =
  check rtcSetSignalingStateChangeCallback(pc.id, cb)

proc setDataChannelCallback*(pc: PeerConnection;
    cb: rtcDataChannelCallbackFunc) =
  check rtcSetDataChannelCallback(pc.id, cb)

proc setTrackCallback*(pc: PeerConnection; cb: rtcTrackCallbackFunc) =
  check rtcSetTrackCallback(pc.id, cb)