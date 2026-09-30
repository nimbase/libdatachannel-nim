## The calling side of a WebRTC data channel call.
##
##     # terminal 1
##     nim c -r --path:src examples/peer_connection_client.nim
##     #   -> prints a description, paste it into
##     # terminal 2
##     nim c -r --path:src examples/peer_connection_server.nim "<description>"
##     #   -> paste the answer printed there back here and press enter
##
## See `peer_connection.nim` for the same thing without any copy-pasting.
##

import std/[base64, os, strutils]
import libdatachannel

const IceServers = @["stun:stun.l.google.com:19302"]

proc main() =
  enableLogging(RTC_LOG_WARNING)

  let pc = newPeerConnection(PeerConnectionConfig(iceServers: IceServers))
  defer: pc.close()

  var dc: DataChannel

  pc.onLocalDescription = proc(sdp: string; kind: SdpType) =
    echo ""
    echo "--- Paste this offer into the server, then press enter there ---"
    echo sdp.encode
    echo "---"
    flushFile(stdout)

  pc.onLocalCandidate = proc(candidate, mid: string) =
    # Trickle ICE is optional: libdatachannel gathers everything before
    # `onLocalDescription` fires, so candidates are already in the SDP.
    discard

  pc.onStateChange = proc(state: rtcState) =
    echo "[client] state: ", state
    if state == RTC_CONNECTED:
      let selected = pc.selectedCandidatePair()
      echo "[client] connected via ", selected.local

  pc.onDataChannel = proc(channel: DataChannel) =
    echo "[client] remote channel '", channel.label(), "'"

  # A PeerConnection has nothing to negotiate without a data channel or a
  # track, which is why this comes before `setLocalDescription`.
  dc = pc.createDataChannel("chat")
  dc.onOpen = proc() =
    echo "[client] data channel open, sending"
    dc.send("Hello from the client!")

  dc.onMessage = proc(data: string; isBinary: bool) =
    let kind = if isBinary: "binary" else: "text"
    echo "[client] <- ", data.len, " ", kind, " bytes: ", data

  pc.setLocalDescription()

  # Wait for the user to paste the answer.
  echo ""
  echo "--- Paste the answer from the server and press enter ---"
  stdout.flushFile()
  let answer = stdin.readLine().strip()
  if answer.len == 0:
    stderr.writeLine("No answer given.")
    quit(1)

  pc.setRemoteDescription(answer.decode, sdpAnswer)

  echo "[client] waiting for the data channel..."
  while true:
    sleep(1000)

when isMainModule:
  main()