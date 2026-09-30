## The answering side of a WebRTC data channel call.
##
## Start the client first, it prints a description you pass to this program,
## and it then prints the answer you paste back into the client:
##
##     # terminal 1
##     nim c -r --path:src examples/peer_connection_client.nim
##     # terminal 2, once the client printed its description
##     nim c -r --path:src examples/peer_connection_server.nim "<description>"
##     # terminal 1: paste the answer printed here and press enter
##
## Descriptions are base64 encoded so they survive a copy-paste through a
## terminal. In a real application they would travel over a signalling server,
## a websocket, or an offer/answer URL.
##

import std/[base64, os, strutils]
import libdatachannel

const IceServers = @["stun:stun.l.google.com:19302"]

proc onDataChannel(dc: DataChannel) =
  echo "[server] data channel '", dc.label(), "' opened"
  dc.onMessage = proc(data: string; isBinary: bool) =
    let kind = if isBinary: "binary" else: "text"
    echo "[server] <- ", data.len, " ", kind, " bytes: ", data
    dc.send("echo: " & data)

proc main(offer: string) =
  enableLogging(RTC_LOG_WARNING)

  let pc = newPeerConnection(PeerConnectionConfig(iceServers: IceServers))
  defer: pc.close()

  pc.onDataChannel = onDataChannel
  pc.onStateChange = proc(state: rtcState) =
    echo "[server] state: ", state

  pc.onLocalCandidate = proc(candidate, mid: string) =
    # Trickle ICE is optional: libdatachannel gathers everything before
    # `onLocalDescription` fires, so candidates are already in the SDP.
    discard

  pc.onLocalDescription = proc(sdp: string; kind: SdpType) =
    echo ""
    echo "--- Paste this answer into the client, then press enter there ---"
    echo sdp.encode
    echo "---"
    flushFile(stdout)

  # A PeerConnection has nothing to negotiate without a data channel or a
  # track, which is why this comes before `setRemoteDescription`.
  discard pc.createDataChannel("chat")

  var decoded = ""
  try:
    decoded = offer.decode
  except CatchableError:
    stderr.writeLine("That is not a valid description.")
    quit(1)

  pc.setRemoteDescription(decoded, sdpOffer)
  pc.setLocalDescription(sdpAnswer)

  echo "[server] waiting for the data channel..."
  while true:
    sleep(1000)

when isMainModule:
  if paramCount() < 1:
    stderr.writeLine("usage: peer_connection_server.nim <base64 description>")
    quit(1)
  main(paramStr(1).strip())