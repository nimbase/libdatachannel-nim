## A WebRTC media track demo: two PeerConnections in one process, one sends
## H264 video payloads, the other receives them.
##
##     nim c -r --path:src examples/track_video.nim
##
## The "video" is a synthetic pattern. Swap `makeFrame` for real encoded
## frames coming out of a camera or a decoder to move actual media.
##
## Note: the C API of libdatachannel v0.24.x provides no depacketizer or
## frame callback, so payloads arrive as RTP packets on the regular
## `onMessage` handler. Codecs without a packetizer setter (VP8/VP9) can
## only send raw RTP packets built by the application.
##

import std/[os, strutils, times]
import libdatachannel

const
  IceServers = @["stun:stun.l.google.com:19302"]
  ClockRate = 90000'u32
  PayloadType = 102
  FrameRate = 30

proc waitUntil(condition: proc (): bool; timeoutMs = 30000): bool =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if condition(): return true
    sleep(20)
  false

proc makeFrame(seq: int): string =
  ## A stand-in for one encoded H264 frame: arbitrary payload bytes.
  result = newStringOfCap(40)
  for i in 0 ..< 36:
    result.add chr((seq + i) and 0xff)

proc main() =
  enableLogging(RTC_LOG_WARNING)

  let sender = newPeerConnection(PeerConnectionConfig(iceServers: IceServers))
  let receiver = newPeerConnection(PeerConnectionConfig())
  defer: receiver.close()
  defer: sender.close()

  # --- signaling ------------------------------------------------------------
  sender.onLocalDescription = proc(sdp: string; kind: SdpType) =
    receiver.setRemoteDescription(sdp, kind)
  receiver.onLocalDescription = proc(sdp: string; kind: SdpType) =
    sender.setRemoteDescription(sdp, kind)
  sender.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0: receiver.addRemoteCandidate(candidate, mid)
  receiver.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0: sender.addRemoteCandidate(candidate, mid)

  # --- receiving side --------------------------------------------------------
  var frames = 0
  var bytes = 0
  receiver.onTrack = proc(track: Track) =
    echo "[receiver] track '", track.id, "', direction ", track.direction()
    # Incoming media arrives as raw payloads on the message callback; the C
    # API has no depacketizer or frame callback to reassemble frames.
    track.onMessage = proc(data: string; isBinary: bool) =
      inc frames
      bytes += data.len
      if frames mod FrameRate == 0:
        echo "[receiver] ", frames, " payloads, ", bytes, " bytes"

    # Only `chainRtcpReceivingSession` works on a receiving track: the
    # sender reporter needs an RTP configuration, which only the packetizer on
    # the sending side creates.
    track.chainRtcpReceivingSession()

  # --- sending side ---------------------------------------------------------
  # The track has to exist before the offer is created, otherwise the media
  # section is missing from the SDP entirely. H264 has a packetizer, so
  # frames go out as RTP packets with a drivable timestamp.
  let track = sender.addTrack(RTC_CODEC_H264,
    PacketizerInit(clockRate: ClockRate, payloadType: PayloadType))
  defer: track.close()

  sender.setLocalDescription()
  if not waitUntil(proc(): bool = receiver.state == RTC_CONNECTED):
    stderr.writeLine("the peers never connected")
    quit(1)

  echo "[sender] connected, streaming ", FrameRate, " frames per second"
  var frameIndex = 0
  while true:
    # The packetizer does not advance the RTP timestamp on its own, so drive
    # it: 90kHz video means one tick is 1/90 s.
    let timestamp = uint32(frameIndex) * ClockRate div uint32(FrameRate)
    track.setRtpTimestamp(timestamp)
    if track.send(makeFrame(frameIndex)) < 0:
      stderr.writeLine("sending failed")
      quit(1)
    inc frameIndex
    sleep(max(1, 1000 div FrameRate))

when isMainModule:
  main()