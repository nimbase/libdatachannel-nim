## A WebRTC media track demo: two PeerConnections in one process, one sends
## VP8 video frames, the other depacketizes them.
##
##     nim c -r --path:src examples/track_video.nim
##
## The "video" is a synthetic pattern packed the way VP8 expects it: a VP8
## key frame header followed by payload bytes. Swap `makeFrame` for real
## encoded frames coming out of a camera or a decoder to move actual media.
##

import std/[os, strutils, times]
import libdatachannel

const
  IceServers = @["stun:stun.l.google.com:19302"]
  ClockRate = 90000'u32
  PayloadType = 96
  FrameRate = 30

proc waitUntil(condition: proc (): bool; timeoutMs = 30000): bool =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if condition(): return true
    sleep(20)
  false

proc makeFrame(seq: int): string =
  ## A stand-in for one encoded VP8 frame.
  ##
  ## The first byte is a VP8 key frame header (0x10), the next three bytes are
  ## the 14-bit start code 9, then arbitrary payload bytes.
  result = newStringOfCap(40)
  result.add(char(0x10))
  result.add(char(0x9d))
  result.add(char(0x01))
  result.add(char(0x2a))
  for i in 0 ..< 32:
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
    # Incoming media is depacketized into frames only once a depacketizer is
    # installed; `onFrame` alone would never fire.
    track.setVP8Depacketizer()
    track.setOnFrame(proc(data: string; info: FrameInfo) =
      inc frames
      bytes += data.len
      if frames mod FrameRate == 0:
        echo "[receiver] ", frames, " frames, ", bytes, " bytes, ",
             "payload type ", info.payloadType,
             ", timestamp ", info.timestamp)

    # Only `chainRtcpReceivingSession` works on a receiving track: the
    # sender reporter needs an RTP configuration, which only the packetizer on
    # the sending side creates.
    track.chainRtcpReceivingSession()

  # --- sending side ---------------------------------------------------------
  # The track has to exist before the offer is created, otherwise the media
  # section is missing from the SDP entirely.
  let track = sender.addTrack(RTC_CODEC_VP8,
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
    # it: 90kHz for VP8 means one tick is 1/90 s.
    let timestamp = uint32(frameIndex) * ClockRate div uint32(FrameRate)
    track.setRtpTimestamp(timestamp)
    if track.send(makeFrame(frameIndex)) < 0:
      stderr.writeLine("sending failed")
      quit(1)
    inc frameIndex
    sleep(max(1, 1000 div FrameRate))

when isMainModule:
  main()