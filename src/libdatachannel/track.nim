## High-level Track API: packetizers and media delivery.
##
## Receiving works through the regular `onMessage` callback inherited from
## `RtcChannel`: libdatachannel v0.24.x exposes no depacketizer or frame
## callback through its C API, so incoming media arrives as raw payloads.
##

import std/strutils
import ./bindings, ./utils, ./channel

type
  TrackId* = ChannelId

  PacketizerInit* = object
    ## Parameters of a media packetizer.
    ssrc*: uint32
      ## Synchronization source identifier, 0 lets libdatachannel pick one.
    cname*: string
    clockRate*: uint32
    payloadType*: uint8
    sequenceNumber*: uint16
    timestamp*: uint32
    maxFragmentSize*: uint16
      ## Maximum fragment size, 0 means the default.
    nalSeparator*: rtcNalUnitSeparator
      ## H264 / H265 only.
    obuPacketization*: rtcObuPacketization
      ## AV1 only.
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

  Track* = ref object of RtcChannel
    ## A WebRTC media track.
    codec*: rtcCodec
      ## Set when the track is created locally or announced by the remote peer.
    cname*: string
      ## The CNAME handed to the packetizer. libdatachannel rejects an empty
      ## one, so this falls back to `defaultPacketizerCname`.
      ## Unused for VP8/VP9, which have no packetizer setter upstream.

const
  defaultPacketizerCname* = "libdatachannel"
    ## CNAME used when `PacketizerInit.cname` is empty. libdatachannel rejects
    ## a `NULL` CNAME, and an empty one would end up as an invalid
    ## `a=cname:` line in the SDP.

proc toRtc(init: PacketizerInit; cname: cstring): rtcPacketizerInit =
  rtcPacketizerInit(
    ssrc: init.ssrc,
    cname: cname,
    payloadType: init.payloadType,
    clockRate: init.clockRate,
    sequenceNumber: init.sequenceNumber,
    timestamp: init.timestamp,
    maxFragmentSize: init.maxFragmentSize,
    nalSeparator: init.nalSeparator,
    obuPacketization: init.obuPacketization,
    playoutDelayId: init.playoutDelayId,
    playoutDelayMin: init.playoutDelayMin,
    playoutDelayMax: init.playoutDelayMax,
    colorSpaceId: init.colorSpaceId,
    colorChromaSitingHorz: init.colorChromaSitingHorz,
    colorChromaSitingVert: init.colorChromaSitingVert,
    colorRange: init.colorRange,
    colorPrimaries: init.colorPrimaries,
    colorTransfer: init.colorTransfer,
    colorMatrix: init.colorMatrix)

template withPacketizerInit(tr: Track, init: PacketizerInit, body: untyped) =
  ## Expose a ready `rtcPacketizerInit` as `rtcInit` to `body`. The CNAME is
  ## stored on the track so the pointer libdatachannel keeps stays valid.
  tr.cname = init.cname
  let cname = cstring(if tr.cname.len > 0: tr.cname else: defaultPacketizerCname)
  var rtcInit {.inject.}: rtcPacketizerInit = init.toRtc(cname)
  body

#
#  Track properties
#

proc description*(tr: Track): string =
  ## The SDP media description of the track.
  if tr.id < 0: return ""
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetTrackDescription(tr.id, cast[cstring](buffer), size))

proc mid*(tr: Track): string =
  ## The media id of the track.
  if tr.id < 0: return ""
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetTrackMid(tr.id, cast[cstring](buffer), size))

proc direction*(tr: Track): rtcDirection =
  ## The direction negotiated for the track.
  if tr.id < 0: return RTC_DIRECTION_UNKNOWN
  var dir = RTC_DIRECTION_UNKNOWN
  check rtcGetTrackDirection(tr.id, addr dir)
  dir

proc payloadTypesForCodec*(tr: Track; codec: string): seq[int] =
  ## All RTP payload types available on the track for `codec`.
  if tr.id < 0: return @[]
  getCInts(proc (buffer: ptr cint; size: cint): cint =
    rtcGetTrackPayloadTypesForCodec(tr.id, cstring(codec), buffer, size))

proc ssrcs*(tr: Track): seq[uint32] =
  ## All synchronization sources used by the track.
  if tr.id < 0: return @[]
  getCUint32s(proc (buffer: ptr uint32; size: cint): cint =
    rtcGetSsrcsForTrack(tr.id, buffer, size))

proc cName*(tr: Track; ssrc: uint32): string =
  ## The CNAME associated with `ssrc` on the track.
  if tr.id < 0: return ""
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetCNameForSsrc(tr.id, ssrc, cast[cstring](buffer), size))

#
#  Sending media
#

proc send*(tr: Track; frame: string): cint =
  ## Send a media frame through the track's packetizer.
  if tr.id < 0: return RTC_ERR_INVALID
  if frame.len == 0: return RTC_ERR_INVALID
  rtcSendMessage(tr.id, cstring(frame), cint(frame.len))

proc requestKeyframe*(tr: Track) =
  ## Ask the remote peer for a new key frame.
  check rtcRequestKeyframe(tr.id)

proc requestBitrate*(tr: Track; bitrate: int) =
  ## Ask the remote encoder to target `bitrate` bits per second.
  check rtcRequestBitrate(tr.id, cuint(max(bitrate, 0)))

#
#  Timestamps
#

proc secondsToTimestamp*(tr: Track; seconds: float): uint32 =
  ## Convert seconds to an RTP timestamp using the track's clock rate.
  var ts: uint32
  check rtcTransformSecondsToTimestamp(tr.id, seconds, addr ts)
  ts

proc timestampToSeconds*(tr: Track; timestamp: uint32): float =
  ## Convert an RTP timestamp to seconds using the track's clock rate.
  var seconds: cdouble
  check rtcTransformTimestampToSeconds(tr.id, timestamp, addr seconds)
  seconds

proc currentTimestamp*(tr: Track): uint32 =
  ## The current RTP timestamp of the track.
  var ts: uint32
  check rtcGetCurrentTrackTimestamp(tr.id, addr ts)
  ts

proc setRtpTimestamp*(tr: Track; timestamp: uint32) =
  ## Set the RTP timestamp used for the next outgoing frame.
  check rtcSetTrackRtpTimestamp(tr.id, timestamp)

proc lastSenderReportTimestamp*(tr: Track): uint32 =
  ## The timestamp of the last RTCP sender report.
  var ts: uint32
  check rtcGetLastTrackSenderReportTimestamp(tr.id, addr ts)
  ts

#
#  Chained handlers
#

proc chainRtcpReceivingSession*(tr: Track) =
  ## Chain an RTCP receiving session on the track.
  check rtcChainRtcpReceivingSession(tr.id)

proc chainRtcpSrReporter*(tr: Track) =
  ## Chain an RTCP sender report recorder on the track.
  check rtcChainRtcpSrReporter(tr.id)

proc chainRtcpNackResponder*(tr: Track;
    maxStoredPacketsCount = int(RTC_DEFAULT_MAX_STORED_PACKET_COUNT)) =
  ## Chain an RTCP NACK responder so lost packets are requested.
  check rtcChainRtcpNackResponder(tr.id, cuint(max(maxStoredPacketsCount, 0)))

proc chainPliHandler*(tr: Track; callback: rtcPliHandlerCallbackFunc) =
  ## Chain a handler reacting to picture loss indications.
  check rtcChainPliHandler(tr.id, callback)

proc chainRembHandler*(tr: Track; callback: rtcRembHandlerCallbackFunc) =
  ## Chain a handler reacting to the receiver estimated maximum bitrate.
  check rtcChainRembHandler(tr.id, callback)

#
#  Packetizers
#

proc setH264Packetizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the H264 packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetH264Packetizer(tr.id, addr rtcInit)

proc setH265Packetizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the H265 packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetH265Packetizer(tr.id, addr rtcInit)

proc setAV1Packetizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the AV1 packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetAV1Packetizer(tr.id, addr rtcInit)

proc setOpusPacketizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the Opus packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetOpusPacketizer(tr.id, addr rtcInit)

proc setAACPacketizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the AAC packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetAACPacketizer(tr.id, addr rtcInit)

proc setPCMUPacketizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the PCMU packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetPCMUPacketizer(tr.id, addr rtcInit)

proc setPCMAPacketizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the PCMA packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetPCMAPacketizer(tr.id, addr rtcInit)

proc setG722Packetizer*(tr: Track, init: PacketizerInit = PacketizerInit()) =
  ## Set the G722 packetizer on the track.
  withPacketizerInit(tr, init):
    check rtcSetG722Packetizer(tr.id, addr rtcInit)

proc setNeedsToSendRtcpSr*(tr: Track) =
  ## Force the sender reporter to emit an RTCP sender report.
  ## Deprecated in the C API, kept for completeness.
  check rtcSetNeedsToSendRtcpSr(tr.id)

#
#  SDP helpers
#

proc payloadTypesForCodec*(sdp: string; codec: string): seq[int] =
  ## All RTP payload types for `codec` present in `sdp`.
  ##
  ## Parsed from the `a=rtpmap:` lines of `sdp`: the C API only maps codecs
  ## per track (`rtcGetTrackPayloadTypesForCodec`), not per SDP string.
  result = @[]
  let wanted = codec.toLowerAscii()
  const prefix = "a=rtpmap:"
  for rawLine in sdp.splitLines():
    let line = rawLine.strip()
    if not line.startsWith(prefix): continue
    let rest = line[prefix.len .. ^1]
    let spaceIdx = rest.find(' ')
    if spaceIdx <= 0: continue
    var pt = -1
    try:
      pt = parseInt(rest[0 ..< spaceIdx])
    except ValueError:
      continue
    let encoding = rest[spaceIdx + 1 .. ^1].split('/')[0].strip().toLowerAscii()
    if pt >= 0 and encoding == wanted:
      result.add pt

proc ssrcsForType*(mediaType: string; sdp: string): seq[uint32] =
  ## All SSRCs for `mediaType` ("audio" or "video") present in `sdp`.
  getCUint32s(proc (buffer: ptr uint32; size: cint): cint =
    rtcGetSsrcsForType(cstring(mediaType), cstring(sdp), buffer, size))

proc setSsrcForType*(mediaType: string; sdp: string; ssrc: uint32;
                     name = "", msid = "", trackId = ""): string =
  ## Return a copy of `sdp` with the SSRC of `mediaType` replaced.
  var n = cstringOrNil(name)
  var m = cstringOrNil(msid)
  var t = cstringOrNil(trackId)
  var init = rtcSsrcForTypeInit(ssrc: ssrc, name: n, msid: m, trackId: t)
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcSetSsrcForType(cstring(mediaType), cstring(sdp),
      cast[cstring](buffer), size, addr init))