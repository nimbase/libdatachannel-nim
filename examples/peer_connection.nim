## A complete WebRTC data channel demo that runs entirely in one process.
##
## Two PeerConnections are wired straight to each other: every SDP and ICE
## candidate produced by one is handed to the other, exactly the way a
## signaling server would. No copy-pasting, no network setup, one command:
##
##     nim c -r --path:src examples/peer_connection.nim
##
## This is the same negotiation dance the two-process example performs, minus
## the signaling step.
##

import std/[os, strutils, times]
import libdatachannel

const
  IceServers = @["stun:stun.l.google.com:19302"]

proc waitUntil(condition: proc (): bool; timeoutMs = 30000): bool =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if condition(): return true
    sleep(20)
  false

proc main() =
  enableLogging(RTC_LOG_WARNING)

  let caller = newPeerConnection(PeerConnectionConfig(iceServers: IceServers))
  let callee = newPeerConnection(PeerConnectionConfig(
    bindAddress: "0.0.0.0"))
  defer: callee.close()
  defer: caller.close()

  # --- signaling: relay descriptions and candidates both ways ---------------
  caller.onLocalDescription = proc(sdp: string; kind: SdpType) =
    echo "[signaling] caller ", kind, " -> callee"
    callee.setRemoteDescription(sdp, kind)

  callee.onLocalDescription = proc(sdp: string; kind: SdpType) =
    echo "[signaling] callee ", kind, " -> caller"
    caller.setRemoteDescription(sdp, kind)

  caller.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0: callee.addRemoteCandidate(candidate, mid)

  callee.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0: caller.addRemoteCandidate(candidate, mid)

  # --- call the callee and announce the incoming channel ---------------------
  callee.onDataChannel = proc(dc: DataChannel) =
    echo "[callee] data channel '", dc.label(), "' opened (stream ", dc.stream(), ")"
    dc.onMessage = proc(data: string; isBinary: bool) =
      echo "[callee] <- ", data
      # Echo it back so the caller sees the round trip complete.
      dc.send("echo: " & data)

  caller.onStateChange = proc(state: rtcState) =
    echo "[caller] state: ", state
    if state == RTC_CONNECTED:
      let selected = caller.selectedCandidatePair()
      echo "[caller] connected via ", selected.local

  # --- open the channel, then negotiate -------------------------------------
  let dc = caller.createDataChannel("chat")
  dc.onOpen = proc() =
    echo "[caller] data channel open, sending"
    dc.send("Hello from the caller!")

  # A PeerConnection has nothing to negotiate without a data channel or a
  # track, which is exactly why `createDataChannel` comes first.
  caller.setLocalDescription()

  if not waitUntil(proc(): bool = dc.isOpen):
    stderr.writeLine("the data channel never opened (state: " & $dc.isClosed & ")")
    quit(1)

  echo "[caller] round trip complete, closing"
  sleep(500)

when isMainModule:
  main()