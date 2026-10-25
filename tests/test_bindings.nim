## Tests for the pure Nim layer: enums, SDP helpers, struct sizes.
##
## Nothing here touches the network or the dynamic library, so these run even
## without libdatachannel installed.
##

import std/unittest
import libdatachannel

suite "constants":
  test "MTU and fragment size match rtc.h":
    check RTC_DEFAULT_MTU == 1280
    check int(RTC_DEFAULT_MAX_FRAGMENT_SIZE) == 1280 - 12 - 8 - 40
    check RTC_DEFAULT_MAX_STORED_PACKET_COUNT == 512

  test "deprecated aliases still resolve":
    check RTC_DEFAULT_MAXIMUM_FRAGMENT_SIZE == RTC_DEFAULT_MAX_FRAGMENT_SIZE
    check RTC_DEFAULT_MAXIMUM_PACKET_COUNT_FOR_NACK_CACHE ==
      RTC_DEFAULT_MAX_STORED_PACKET_COUNT

  test "error codes match rtc.h":
    check RTC_ERR_SUCCESS == 0
    check RTC_ERR_INVALID == -1
    check RTC_ERR_FAILURE == -2
    check RTC_ERR_NOT_AVAIL == -3
    check RTC_ERR_TOO_SMALL == -4

suite "enum values":
  test "rtcState values match rtc.h":
    check ord(RTC_NEW) == 0
    check ord(RTC_CONNECTING) == 1
    check ord(RTC_CONNECTED) == 2
    check ord(RTC_DISCONNECTED) == 3
    check ord(RTC_FAILED) == 4
    check ord(RTC_CLOSED) == 5

  test "rtcIceState values match rtc.h":
    check ord(RTC_ICE_NEW) == 0
    check ord(RTC_ICE_CHECKING) == 1
    check ord(RTC_ICE_CONNECTED) == 2
    check ord(RTC_ICE_COMPLETED) == 3
    check ord(RTC_ICE_FAILED) == 4
    check ord(RTC_ICE_DISCONNECTED) == 5
    check ord(RTC_ICE_CLOSED) == 6

  test "rtcGatheringState and rtcSignalingState values match rtc.h":
    check ord(RTC_GATHERING_NEW) == 0
    check ord(RTC_GATHERING_INPROGRESS) == 1
    check ord(RTC_GATHERING_COMPLETE) == 2
    check ord(RTC_SIGNALING_STABLE) == 0
    check ord(RTC_SIGNALING_HAVE_LOCAL_OFFER) == 1
    check ord(RTC_SIGNALING_HAVE_REMOTE_OFFER) == 2
    check ord(RTC_SIGNALING_HAVE_LOCAL_PRANSWER) == 3
    check ord(RTC_SIGNALING_HAVE_REMOTE_PRANSWER) == 4

  test "rtcLogLevel values match rtc.h":
    check ord(RTC_LOG_NONE) == 0
    check ord(RTC_LOG_FATAL) == 1
    check ord(RTC_LOG_ERROR) == 2
    check ord(RTC_LOG_WARNING) == 3
    check ord(RTC_LOG_INFO) == 4
    check ord(RTC_LOG_DEBUG) == 5
    check ord(RTC_LOG_VERBOSE) == 6

  test "rtcCodec values match rtc.h":
    check ord(RTC_CODEC_H264) == 0
    check ord(RTC_CODEC_VP8) == 1
    check ord(RTC_CODEC_VP9) == 2
    check ord(RTC_CODEC_H265) == 3
    check ord(RTC_CODEC_AV1) == 4
    check ord(RTC_CODEC_OPUS) == 128
    check ord(RTC_CODEC_PCMU) == 129
    check ord(RTC_CODEC_PCMA) == 130
    check ord(RTC_CODEC_AAC) == 131
    check ord(RTC_CODEC_G722) == 132

  test "rtcDirection, rtcTransportPolicy and rtcCertificateType":
    check ord(RTC_DIRECTION_UNKNOWN) == 0
    check ord(RTC_DIRECTION_SENDONLY) == 1
    check ord(RTC_DIRECTION_RECVONLY) == 2
    check ord(RTC_DIRECTION_SENDRECV) == 3
    check ord(RTC_DIRECTION_INACTIVE) == 4
    check ord(RTC_TRANSPORT_POLICY_ALL) == 0
    check ord(RTC_TRANSPORT_POLICY_RELAY) == 1
    check ord(RTC_CERTIFICATE_DEFAULT) == 0
    check ord(RTC_CERTIFICATE_ECDSA) == 1
    check ord(RTC_CERTIFICATE_RSA) == 2

  test "NalUnitSeparator and ObuPacketization values match rtc.h":
    check ord(RTC_NAL_SEPARATOR_LENGTH) == 0
    check ord(RTC_NAL_SEPARATOR_LONG_START_SEQUENCE) == 1
    check ord(RTC_NAL_SEPARATOR_SHORT_START_SEQUENCE) == 2
    check ord(RTC_NAL_SEPARATOR_START_SEQUENCE) == 3
    check ord(RTC_OBU_PACKETIZED_OBU) == 0
    check ord(RTC_OBU_PACKETIZED_TEMPORAL_UNIT) == 1

suite "pretty printing":
  test "states":
    check $RTC_NEW == "new"
    check $RTC_CONNECTED == "connected"
    check $RTC_CLOSED == "closed"
    check $RTC_ICE_COMPLETED == "completed"
    check $RTC_GATHERING_INPROGRESS == "in-progress"
    check $RTC_SIGNALING_HAVE_LOCAL_OFFER == "have-local-offer"

  test "codecs, directions and log levels":
    check $RTC_CODEC_H265 == "H265"
    check $RTC_CODEC_OPUS == "OPUS"
    check $RTC_DIRECTION_SENDRECV == "sendrecv"
    check $RTC_LOG_WARNING == "warning"
    check $RTC_CERTIFICATE_ECDSA == "ECDSA"

suite "SDP types":
  test "string round trip":
    check $sdpOffer == "offer"
    check $sdpAnswer == "answer"
    check $sdpPrAnswer == "pranswer"
    check $sdpRollback == "rollback"

  test "conversion is case insensitive":
    check toSdpType("offer") == sdpOffer
    check toSdpType("OFFER") == sdpOffer
    check toSdpType("Answer") == sdpAnswer
    check toSdpType("pranswer") == sdpPrAnswer

  test "unknown types raise":
    expect LibDataChannelError:
      discard toSdpType("nope")

suite "ABI layout":
  # Every one of these is asserted against the real rtc.h of
  # libdatachannel v0.24.6 on x86-64.
  test "rtcConfiguration":
    check sizeof(rtcConfiguration) == 88
    check offsetOf(rtcConfiguration, iceServers) == 0
    check offsetOf(rtcConfiguration, iceServersCount) == 8
    check offsetOf(rtcConfiguration, proxyServer) == 16
    check offsetOf(rtcConfiguration, bindAddress) == 24
    check offsetOf(rtcConfiguration, certificateType) == 32
    check offsetOf(rtcConfiguration, certificatePemFile) == 40
    check offsetOf(rtcConfiguration, keyPemFile) == 48
    check offsetOf(rtcConfiguration, keyPemPass) == 56
    check offsetOf(rtcConfiguration, iceTransportPolicy) == 64
    check offsetOf(rtcConfiguration, enableIceTcp) == 68
    check offsetOf(rtcConfiguration, enableIceUdpMux) == 69
    check offsetOf(rtcConfiguration, disableAutoNegotiation) == 70
    check offsetOf(rtcConfiguration, forceMediaTransport) == 71
    check offsetOf(rtcConfiguration, portRangeBegin) == 72
    check offsetOf(rtcConfiguration, portRangeEnd) == 74
    check offsetOf(rtcConfiguration, mtu) == 76
    check offsetOf(rtcConfiguration, maxMessageSize) == 80
    check offsetOf(rtcConfiguration, disableFingerprintVerification) == 84

  test "rtcReliability and rtcDataChannelInit":
    check sizeof(rtcReliability) == 12
    check offsetOf(rtcReliability, unordered) == 0
    check offsetOf(rtcReliability, unreliable) == 1
    check offsetOf(rtcReliability, maxPacketLifeTime) == 4
    check offsetOf(rtcReliability, maxRetransmits) == 8
    check sizeof(rtcDataChannelInit) == 32
    check offsetOf(rtcDataChannelInit, reliability) == 0
    check offsetOf(rtcDataChannelInit, protocol) == 16
    check offsetOf(rtcDataChannelInit, negotiated) == 24
    check offsetOf(rtcDataChannelInit, manualStream) == 25
    check offsetOf(rtcDataChannelInit, stream) == 26

  test "rtcTrackInit":
    check sizeof(rtcTrackInit) == 56
    check offsetOf(rtcTrackInit, direction) == 0
    check offsetOf(rtcTrackInit, codec) == 4
    check offsetOf(rtcTrackInit, payloadType) == 8
    check offsetOf(rtcTrackInit, ssrc) == 12
    check offsetOf(rtcTrackInit, mid) == 16
    check offsetOf(rtcTrackInit, name) == 24
    check offsetOf(rtcTrackInit, msid) == 32
    check offsetOf(rtcTrackInit, trackId) == 40
    check offsetOf(rtcTrackInit, profile) == 48

  test "rtcPacketizerInit":
    check sizeof(rtcPacketizerInit) == 64
    check offsetOf(rtcPacketizerInit, ssrc) == 0
    check offsetOf(rtcPacketizerInit, cname) == 8
    check offsetOf(rtcPacketizerInit, payloadType) == 16
    check offsetOf(rtcPacketizerInit, clockRate) == 20
    check offsetOf(rtcPacketizerInit, sequenceNumber) == 24
    check offsetOf(rtcPacketizerInit, timestamp) == 28
    check offsetOf(rtcPacketizerInit, maxFragmentSize) == 32
    check offsetOf(rtcPacketizerInit, nalSeparator) == 36
    check offsetOf(rtcPacketizerInit, obuPacketization) == 40
    check offsetOf(rtcPacketizerInit, playoutDelayId) == 44
    check offsetOf(rtcPacketizerInit, playoutDelayMin) == 46
    check offsetOf(rtcPacketizerInit, playoutDelayMax) == 48
    check offsetOf(rtcPacketizerInit, colorSpaceId) == 50
    check offsetOf(rtcPacketizerInit, colorChromaSitingHorz) == 51
    check offsetOf(rtcPacketizerInit, colorChromaSitingVert) == 52
    check offsetOf(rtcPacketizerInit, colorRange) == 53
    check offsetOf(rtcPacketizerInit, colorPrimaries) == 54
    check offsetOf(rtcPacketizerInit, colorTransfer) == 55
    check offsetOf(rtcPacketizerInit, colorMatrix) == 56

  test "rtcWsConfiguration and rtcWsServerConfiguration":
    check sizeof(rtcWsConfiguration) == 48
    check offsetOf(rtcWsConfiguration, disableTlsVerification) == 0
    check offsetOf(rtcWsConfiguration, proxyServer) == 8
    check offsetOf(rtcWsConfiguration, protocols) == 16
    check offsetOf(rtcWsConfiguration, protocolsCount) == 24
    check offsetOf(rtcWsConfiguration, tcpConnectionTimeoutMs) == 28
    check offsetOf(rtcWsConfiguration, connectionTimeoutMs) == 32
    check offsetOf(rtcWsConfiguration, pingIntervalMs) == 36
    check offsetOf(rtcWsConfiguration, maxOutstandingPings) == 40
    check offsetOf(rtcWsConfiguration, maxMessageSize) == 44
    check sizeof(rtcWsServerConfiguration) == 48
    check offsetOf(rtcWsServerConfiguration, port) == 0
    check offsetOf(rtcWsServerConfiguration, enableTls) == 2
    check offsetOf(rtcWsServerConfiguration, certificatePemFile) == 8
    check offsetOf(rtcWsServerConfiguration, keyPemFile) == 16
    check offsetOf(rtcWsServerConfiguration, keyPemPass) == 24
    check offsetOf(rtcWsServerConfiguration, bindAddress) == 32
    check offsetOf(rtcWsServerConfiguration, connectionTimeoutMs) == 40
    check offsetOf(rtcWsServerConfiguration, maxMessageSize) == 44

  test "rtcSctpSettings and rtcSsrcForTypeInit":
    check sizeof(rtcSctpSettings) == 48
    check sizeof(rtcSsrcForTypeInit) == 32

suite "helper procs":
  test "toNimBytes copies raw bytes including NUL":
    var source = "a\0b\0c"
    check toNimBytes(unsafeAddr source[0], source.len) == "a\0b\0c"
    check toNimBytes(nil, 10) == ""
    check toNimBytes(unsafeAddr source[0], 0) == ""

  test "toNimString handles nil":
    check toNimString(nil) == ""
    check toNimString(cstring"hello") == "hello"

  test "errorCode names every documented code":
    check errorCode(RTC_ERR_SUCCESS) == "RTC_ERR_SUCCESS"
    check errorCode(RTC_ERR_INVALID) == "RTC_ERR_INVALID"
    check errorCode(RTC_ERR_FAILURE) == "RTC_ERR_FAILURE"
    check errorCode(RTC_ERR_NOT_AVAIL) == "RTC_ERR_NOT_AVAIL"
    check errorCode(RTC_ERR_TOO_SMALL) == "RTC_ERR_TOO_SMALL"
    check errorCode(-99) == "error -99"