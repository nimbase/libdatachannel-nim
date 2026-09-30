## Integration tests for PeerConnection, DataChannel and Track.
##
## Two PeerConnections are wired to each other inside a single process, which
## is enough to exercise the whole negotiation path over loopback.
##

import std/[os, strutils, tables, times, unittest]
import std/tables
import libdatachannel

proc waitFor(condition: proc (): bool; timeoutMs = 10000): bool =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if condition(): return true
    sleep(10)
  condition()

type Pair = object
  a, b: PeerConnection
    ## The two connected peers, `a` is the offerer.
  dc: DataChannel
    ## The DataChannel opened by `a` to make the offer valid. libdatachannel
    ## refuses to negotiate a connection with nothing to negotiate.

proc connectPair(setup: proc (a, b: PeerConnection) {.closure.}): Pair =
  ## Create two PeerConnections and negotiate them against each other by
  ## relaying descriptions and candidates directly, the same way a signaling
  ## server would.
  let a = newPeerConnection(PeerConnectionConfig(
    iceServers: @["stun:stun.l.google.com:19302"]))
  let b = newPeerConnection(PeerConnectionConfig())

  a.onLocalDescription = proc(sdp: string; kind: SdpType) =
    b.setRemoteDescription(sdp, kind)
  b.onLocalDescription = proc(sdp: string; kind: SdpType) =
    a.setRemoteDescription(sdp, kind)
  a.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0:
      b.addRemoteCandidate(candidate, mid)
  b.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0:
      a.addRemoteCandidate(candidate, mid)

  setup(a, b)
  result.dc = a.createDataChannel("setup")
  a.setLocalDescription()
  check waitFor(proc(): bool = b.state == RTC_CONNECTED)

  result.a = a
  result.b = b

suite "peer connection":
  test "two connections negotiate and reach the connected state":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    check pair.a.state == RTC_CONNECTED
    check pair.b.state == RTC_CONNECTED
    check pair.a.iceState == RTC_ICE_CONNECTED or
          pair.a.iceState == RTC_ICE_COMPLETED
    # Gathering may still be running when the STUN server is unreachable.
    check pair.a.gatheringState in {RTC_GATHERING_COMPLETE,
      RTC_GATHERING_INPROGRESS}
    check pair.a.signalingState == RTC_SIGNALING_STABLE
    check not pair.a.isNegotiationNeeded()

  test "the local description is a valid offer containing both peers":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    let local = pair.a.localDescription()
    let remote = pair.a.remoteDescription()
    check local.startsWith("v=0")
    check local.contains("m=application")
    check local.contains("a=candidate:")
    # `a` offers, `b` answers.
    check pair.a.localDescriptionType() == "offer"
    check pair.b.localDescriptionType() == "answer"
    check pair.a.remoteDescriptionType() == "answer"
    check pair.b.remoteDescriptionType() == "offer"
    check local.contains("a=setup:actpass")
    # libdatachannel normalises a description while parsing it, so the stored
    # remote description is not byte-identical to the local one.
    check remote.startsWith("v=0")
    check remote.contains("m=application")
    check remote.contains("a=setup:active")

  test "candidate pairs and addresses are reported":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    check pair.a.localAddress().len > 0
    check pair.a.remoteAddress().len > 0
    let selected = pair.a.selectedCandidatePair()
    check selected.local.contains("candidate:")
    check selected.remote.contains("candidate:")

  test "a data channel opened by one side is announced on the other":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    var remoteChannel = false
    pair.b.onDataChannel = proc(dc: DataChannel) = remoteChannel = true

    let dc = pair.a.createDataChannel("chat")
    defer: dc.close()
    check waitFor(proc(): bool = remoteChannel)
    # The helper opens a "setup" channel to make the offer valid, plus this one.
    check pair.b.dataChannels.len == 2

suite "data channel":
  test "text and binary messages round trip in both directions":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    var atServer = ""
    var atServerWasBinary = false
    var atClient = ""
    var atClientWasBinary = false

    pair.b.onDataChannel = proc(remote: DataChannel) =
      remote.onMessage = proc(data: string; isBinary: bool) =
        atServer = data
        atServerWasBinary = isBinary
        if isBinary: remote.sendBinary(data) else: remote.send("echo:" & data)

    let dc = pair.a.createDataChannel("chat")
    defer: dc.close()
    dc.onMessage = proc(data: string; isBinary: bool) =
      atClient = data
      atClientWasBinary = isBinary
    check waitFor(proc(): bool = dc.isOpen)

    # Text: the server prefixes it and sends it back as text.
    check dc.send("hello") == RTC_ERR_SUCCESS
    check waitFor(proc(): bool = atClient == "echo:hello")
    check atServer == "hello"
    check not atServerWasBinary
    check not atClientWasBinary

    # Binary: the server echoes it back unchanged, NUL bytes included.
    atClient = ""
    dc.sendBinary("raw bytes\0here")
    check waitFor(proc(): bool = atClient == "raw bytes\0here")
    check atServer == "raw bytes\0here"
    check atServerWasBinary
    check atClientWasBinary

  test "channel properties are reported back":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    var remoteLabel = ""
    var remoteProtocol = ""
    pair.b.onDataChannel = proc(dc: DataChannel) =
      remoteLabel = dc.label()
      remoteProtocol = dc.protocol()

    let dc = pair.a.createDataChannel("metrics",
      DataChannelInit(
        reliability: Reliability(unordered: true, unreliable: true,
          maxRetransmits: 3),
        protocol: "json"))
    defer: dc.close()
    check waitFor(proc(): bool = remoteLabel.len > 0)

    check remoteLabel == "metrics"
    check remoteProtocol == "json"
    check dc.label() == "metrics"
    check dc.protocol() == "json"
    check dc.stream() >= 0

    let reliability = dc.reliability()
    check reliability.unordered
    check reliability.unreliable
    check reliability.maxRetransmits == 3

  test "buffers and sizes are reported":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    let dc = pair.a.createDataChannel("buffers")
    defer: dc.close()
    check dc.maxMessageSize() > 0
    check dc.bufferedAmount() == 0
    check dc.availableAmount() == 0
    dc.setBufferedAmountLowThreshold(1024)

  test "closing the data channel closes the remote one":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    var remoteClosed = false
    pair.b.onDataChannel = proc(dc: DataChannel) =
      dc.onClosed = proc() = remoteClosed = true

    let dc = pair.a.createDataChannel("closable")
    check waitFor(proc(): bool = dc.isOpen)
    dc.close()
    check dc.id == -1
    check not dc.isOpen
    check waitFor(proc(): bool = remoteClosed)

suite "track":
  test "adding a track is negotiated and described":
    let pair = connectPair(proc (a, b: PeerConnection) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    let track = pair.a.addTrack(RTC_CODEC_OPUS,
      PacketizerInit(clockRate: 48000, payloadType: 111, cname: "nim"))
    defer: track.close()

    check track.codec == RTC_CODEC_OPUS
    check track.description().len > 0
    check track.direction() == RTC_DIRECTION_SENDRECV
    check track.currentTimestamp() == 0
    check track.secondsToTimestamp(0.020) > 0
    check track.timestampToSeconds(track.secondsToTimestamp(0.020)) > 0.0
    check track.payloadTypesForCodec("opus").len > 0
    check track.ssrcs().len > 0
    track.chainRtcpReceivingSession()
    track.chainRtcpSrReporter()
    track.chainRtcpNackResponder()

  test "media frames reach the remote depacketizer":
    var received = ""
    var frameInfo = FrameInfo()
    var outgoing: Track
    var pair = connectPair(proc (a, b: PeerConnection) =
      # Tracks have to exist before the offer is created for the media section
      # to be negotiated at all. Only `a` sends, `b` receives on the track
      # libdatachannel announces through `onTrack`.
      outgoing = a.addTrack(RTC_CODEC_VP8,
        PacketizerInit(clockRate: 90000, payloadType: 96))
      b.onTrack = proc(remote: Track) =
        remote.setVP8Depacketizer()
        remote.setOnFrame(proc(data: string; info: FrameInfo) =
          received = data
          frameInfo = info))
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()
    defer: outgoing.close()

    check waitFor(proc(): bool = pair.b.state == RTC_CONNECTED)
    check waitFor(proc(): bool = pair.a.state == RTC_CONNECTED)

    # Two frames, so the RTP timestamp has a chance to advance.
    check outgoing.send("\x00" & repeat("\x01", 40)) == RTC_ERR_SUCCESS
    check waitFor(proc(): bool = received.len > 0)
    check received.len > 0
    check frameInfo.payloadType == 96
    # The packetizer does not advance the RTP timestamp on its own, the
    # application drives it.
    outgoing.setRtpTimestamp(90000)
    check outgoing.send("\x00" & repeat("\x02", 40)) == RTC_ERR_SUCCESS
    check waitFor(proc(): bool = frameInfo.timestamp == 90000'u32)
    check outgoing.currentTimestamp() == 90000'u32
    check outgoing.timestampToSeconds(90000'u32) > 0.0

  test "SDP helpers work on a real description":
    var pair = connectPair(proc (a, b: PeerConnection) =
      discard a.addTrack(RTC_CODEC_OPUS,
        PacketizerInit(clockRate: 48000, payloadType: 111))
      discard b.addTrack(RTC_CODEC_OPUS,
        PacketizerInit(clockRate: 48000, payloadType: 111))
      b.onTrack = proc(remote: Track) = discard)
    defer: pair.dc.close()
    defer: pair.b.close()
    defer: pair.a.close()

    let sdp = pair.a.localDescription()
    check payloadTypesForCodec(sdp, "opus").len > 0
    check ssrcsForType("audio", sdp).len > 0
    let rewritten = setSsrcForType("audio", sdp, 0x11223344'u32,
      "mic", "stream track")
    # libdatachannel writes SSRCs in decimal.
    check rewritten.contains($0x11223344'u32)
    check rewritten.contains("mic")
    check rewritten.contains("stream track")

suite "error handling":
  test "creating a data channel on a dead connection raises":
    let pc = newPeerConnection()
    pc.close()
    expect LibDataChannelError:
      discard pc.createDataChannel("nope")

  test "closing twice is a no-op":
    let pc = newPeerConnection()
    pc.close()
    pc.close()
    check pc.id == -1

  test "getters on a fresh connection return empty values":
    let pc = newPeerConnection()
    defer: pc.close()
    check pc.remoteDescription() == ""
    check pc.localAddress() == ""
    check pc.remoteAddress() == ""