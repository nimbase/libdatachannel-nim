<p align="center">
  Nim language 👑 bindings for Libdatachannel<br>A standalone WebRTC Data Channels, WebRTC Media Transport, and WebSockets
</p>

<p align="center">
  <code>nimble install libdatachannel</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/libdatachannel-nim">API reference</a><br>
  <img src="https://github.com/openpeeps/libdatachannel-nim/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/libdatachannel-nim/workflows/docs/badge.svg" alt="Github Actions">
</p>

## 😍 Key Features
- [x] Lightweight WebRTC Data Channel/Media Transport
- [x] Fast Server/Client WebSockets

- [x] High-level API in Nim style!
- [x] Low-level bindings `libdatachannel/bindings`

Targets **libdatachannel v0.24.x**. Every entity of the C API is bound 1:1 in
[`bindings.nim`](src/libdatachannel/bindings.nim), with the struct layouts
verified field-by-field against the real `rtc.h`.

## Build the library
First, you will need to build [libdatachannel](https://libdatachannel.org/) from [GitHub source](https://github.com/paullouisageneau/libdatachannel). See [Building instructions](https://github.com/paullouisageneau/libdatachannel/blob/master/BUILDING.md)

The Nim bindings load the shared library at *run time*, so the C headers do
not have to be installed, only the library itself has to be reachable by the
dynamic loader:

```bash
LD_LIBRARY_PATH=/usr/local/lib nim c -r myapp.nim   # Linux
DYLD_LIBRARY_PATH=/usr/local/lib nim c -r myapp.nim # macOS
```

## Quick start

```nim
import std/[os]
import libdatachannel

# A WebSocket echo server.
let server = newWebSocketServer(Port(8080))
server.onClient = proc(client: WebSocketClient) =
  client.onMessage = proc(data: string; isBinary: bool) =
    client.send(data)

while true:
  sleep(1000)
```

```nim
import std/[os]
import libdatachannel

# A WebSocket client.
let client = newWebSocketClient("ws://127.0.0.1:8080")
client.onOpen = proc() = client.send("Hello!")
client.onMessage = proc(data: string; isBinary: bool) = echo "<- ", data

while true:
  sleep(1000)
```

## Examples

Every example in [`examples/`](examples/) is a single runnable file:

| Example | What it shows |
| --- | --- |
| [`websocket_server.nim`](examples/websocket_server.nim) / [`websocket_client.nim`](examples/websocket_client.nim) | WebSocket server and client, text and binary framing |
| [`peer_connection.nim`](examples/peer_connection.nim) | A complete data channel call between two PeerConnections in one process |
| [`peer_connection_client.nim`](examples/peer_connection_client.nim) / [`peer_connection_server.nim`](examples/peer_connection_server.nim) | The same call across two processes with manual signalling |
| [`track_video.nim`](examples/track_video.nim) | Media transport: VP8 packetizer, depacketizer and frames |
| [`logger.nim`](examples/logger.nim) | Routing libdatachannel's log into `std/logging` |

```bash
# one command, no setup, no copy-pasting
nim c -r examples/peer_connection.nim
```

See [examples/README.md](examples/README.md) for the full walkthrough.

### WebSockets

```bash
# terminal 1
nim c -r examples/websocket_server.nim
# terminal 2
nim c -r examples/websocket_client.nim
```

<details>
<summary>Source of <code>examples/websocket_server.nim</code></summary>

```nim
import std/os
import libdatachannel

const
  BindAddress = "0.0.0.0"
  ListenPort = 8080

proc onClient(client: WebSocketClient) =
  echo "[+] client connected from ", client.remoteAddress()
  # `onClient` fires as soon as the TCP connection is accepted, so anything
  # that depends on the handshake has to wait for `onOpen`.
  client.onOpen = proc() =
    client.send("Welcome to the libdatachannel-nim echo server!")
  client.onMessage = proc(data: string; isBinary: bool) =
    # Echo it straight back, preserving the framing.
    if isBinary:
      client.sendBinary(data)
    else:
      client.send(data)

proc main() =
  enableLogging()
  let server = newWebSocketServer(WebSocketServerConfig(
    port: Port(ListenPort),
    bindAddress: BindAddress,
  ))
  defer: server.close()
  server.onClient = onClient
  echo "WebSocket echo server listening on ws://", BindAddress, ":", server.port
  while true:
    sleep(1000)

main()
```

</details>

<details>
<summary>Source of <code>examples/websocket_client.nim</code></summary>

```nim
import std/os
import libdatachannel

var finished = false

proc main(url: string) =
  let client = newWebSocketClient(url)
  defer: client.close()

  # Callbacks run on libdatachannel's own threads, so they hand control back
  # to the main loop through a flag instead of calling `quit` from there.
  client.onOpen = proc() = client.send("Hello from Nim!")
  client.onMessage = proc(data: string; isBinary: bool) =
    let kind = if isBinary: "binary" else: "text"
    echo "[<] ", data.len, " ", kind, " bytes: ", data
    finished = true
  client.onError = proc(message: string) =
    stderr.writeLine("[!] ", message)
    finished = true

  while not finished:
    sleep(50)

main("ws://127.0.0.1:8080")
```

</details>

### Peer connection and data channel

```bash
nim c -r examples/peer_connection.nim
```

<details>
<summary>Source of <code>examples/peer_connection.nim</code></summary>

```nim
import std/[os, times]
import libdatachannel

const IceServers = @["stun:stun.l.google.com:19302"]

proc waitUntil(condition: proc (): bool; timeoutMs = 30000): bool =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if condition(): return true
    sleep(20)
  false

proc main() =
  let caller = newPeerConnection(PeerConnectionConfig(iceServers: IceServers))
  let callee = newPeerConnection()
  defer: callee.close()
  defer: caller.close()

  # --- signaling: relay descriptions and candidates both ways ---------------
  caller.onLocalDescription = proc(sdp: string; kind: SdpType) =
    callee.setRemoteDescription(sdp, kind)
  callee.onLocalDescription = proc(sdp: string; kind: SdpType) =
    caller.setRemoteDescription(sdp, kind)
  caller.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0: callee.addRemoteCandidate(candidate, mid)
  callee.onLocalCandidate = proc(candidate, mid: string) =
    if candidate.len > 0: caller.addRemoteCandidate(candidate, mid)

  # --- the caller's side of the channel --------------------------------------
  var dc: DataChannel
  callee.onDataChannel = proc(channel: DataChannel) =
    echo "[callee] channel '", channel.label(), "' opened"
    channel.onMessage = proc(data: string; isBinary: bool) =
      echo "[callee] <- ", data
      channel.send("echo: " & data)

  caller.onStateChange = proc(state: rtcState) = echo "[caller] ", state

  dc = caller.createDataChannel("chat")
  dc.onOpen = proc() =
    echo "[caller] sending"
    dc.send("Hello from the caller!")

  # A PeerConnection has nothing to negotiate without a data channel or a
  # track, which is exactly why `createDataChannel` comes first.
  caller.setLocalDescription()

  doAssert waitUntil(proc(): bool = dc.isOpen)
  sleep(500)

main()
```

</details>

### Media transport

```bash
nim c -r examples/track_video.nim
```

<details>
<summary>Source of the media parts of <code>examples/track_video.nim</code></summary>

```nim
# --- receiving side --------------------------------------------------------
receiver.onTrack = proc(track: Track) =
  # Incoming media is depacketized into frames only once a depacketizer is
  # installed; `onFrame` alone would never fire.
  track.setVP8Depacketizer()
  track.setOnFrame(proc(data: string; info: FrameInfo) =
    echo "frame of ", data.len, " bytes, payload type ", info.payloadType,
         ", timestamp ", info.timestamp)
  track.chainRtcpReceivingSession()

# --- sending side ----------------------------------------------------------
# The track has to exist before the offer is created, otherwise the media
# section is missing from the SDP entirely.
let track = sender.addTrack(RTC_CODEC_VP8,
  PacketizerInit(clockRate: 90000, payloadType: 96))
sender.setLocalDescription()

# The packetizer does not advance the RTP timestamp on its own, so drive it.
track.setRtpTimestamp(90000)
track.send(frame)
```

</details>

## API overview

### `PeerConnection`

```nim
let pc = newPeerConnection(PeerConnectionConfig(
  iceServers: @["stun:stun.l.google.com:19302"],
  bindAddress: "0.0.0.0",
  certificateType: RTC_CERTIFICATE_ECDSA,
  portRangeBegin: 50000,
  portRangeEnd: 50100,
  mtu: 1280,
  maxMessageSize: 262144,
))

pc.onLocalDescription = proc(sdp: string; kind: SdpType) = discard
pc.onLocalCandidate = proc(candidate, mid: string) = discard
pc.onStateChange = proc(state: rtcState) = discard
pc.onIceStateChange = proc(state: rtcIceState) = discard
pc.onGatheringStateChange = proc(state: rtcGatheringState) = discard
pc.onSignalingStateChange = proc(state: rtcSignalingState) = discard
pc.onDataChannel = proc(dc: DataChannel) = discard
pc.onTrack = proc(tr: Track) = discard

pc.setLocalDescription()                    # offer or answer
pc.setRemoteDescription(sdp, sdpOffer)
pc.addRemoteCandidate(candidate, mid)

pc.localDescription(); pc.remoteDescription()
pc.localAddress(); pc.remoteAddress()
pc.selectedCandidatePair()
pc.isNegotiationNeeded()

pc.close()
```

### `DataChannel`

```nim
let dc = pc.createDataChannel("chat", DataChannelInit(
  reliability: Reliability(unordered: true, unreliable: true, maxRetransmits: 3),
  protocol: "json",
))

dc.onOpen = proc() = dc.send("ready")
dc.onMessage = proc(data: string; isBinary: bool) = discard
dc.onClosed = proc() = discard
dc.onError = proc(message: string) = discard

dc.send("text message")
dc.sendBinary(bytes)          # openArray[byte], verbatim

dc.label(); dc.protocol(); dc.stream(); dc.reliability()
dc.bufferedAmount(); dc.availableAmount(); dc.maxMessageSize()

dc.close()
```

### `Track`

```nim
let track = pc.addTrack(RTC_CODEC_VP8,
  PacketizerInit(clockRate: 90000, payloadType: 96, cname: "camera"))

track.setVP8Depacketizer()    # or H264/H265/AV1/Opus/AAC/PCMU/PCMA/G722
track.setOnFrame(proc(data: string; info: FrameInfo) = discard)

track.send(frame)
track.setRtpTimestamp(90000)
track.requestKeyframe()
track.requestBitrate(500_000)

track.description(); track.mid(); track.direction()
track.ssrcs(); track.payloadTypesForCodec("VP8"); track.cName(ssrc)
track.secondsToTimestamp(0.020); track.timestampToSeconds(timestamp)
track.chainRtcpReceivingSession()
track.chainRtcpSrReporter()
track.chainRtcpNackResponder()
track.chainPliHandler(callback)
track.chainRembHandler(callback)
track.chainPacingHandler(bitsPerSecond = 1_000_000, sendIntervalMs = 20)
```

### `WebSocketServer` / `WebSocketClient`

```nim
let server = newWebSocketServer(WebSocketServerConfig(
  port: Port(8080),
  enableTls: false,        # wss://
  certificatePemFile: "cert.pem",
  keyPemFile: "key.pem",
  bindAddress: "0.0.0.0",
))
server.onClient = proc(client: WebSocketClient) =
  client.onOpen = proc() = client.path()
  client.onMessage = proc(data: string; isBinary: bool) = client.send(data)
  client.onClosed = proc() = discard
  client.onError = proc(message: string) = discard

server.port
server.close()

let client = newWebSocketClient(WebSocketClientConfig(
  disableTlsVerification: false,
  protocols: @["chat"],
  pingIntervalMs: 5000,
))
client.remoteAddress(); client.path()
client.close()
```

### Logging

```nim
enableLogging()                            # info level to stderr
enableLogging(RTC_LOG_DEBUG)
setLogLevel(RTC_LOG_NONE)
setLogger(proc(level: rtcLogLevel; message: string) = echo level, message)
```

### Global settings

```nim
discard rtcPreload()          # warm the library up, returns true if it was not up
rtcSetThreadPoolSize(4)
rtcSetSctpSettings(addr settings)
rtcCleanup()                  # release everything, at the very end
```

### Low-level bindings

`libdatachannel/bindings` is a straight 1:1 mapping of `rtc.h`, so anything
the high-level API does not cover is still available:

```nim
import libdatachannel/bindings

var config = rtcConfiguration(enableIceTcp: true, mtu: 1280)
let pc = rtcCreatePeerConnection(addr config)
rtcSetMessageCallback(pc, myCdeclCallback)
```

## Gotchas worth knowing

* **Negotiate something.** `setLocalDescription` fails with
  `RTC_ERR_FAILURE` ("No DataChannel or Track to negotiate") unless a
  DataChannel or Track was created first.
* **A DataChannel or Track needs a packetizer.** libdatachannel rejects a
  `NULL` CNAME, so `PacketizerInit.cname` falls back to `defaultPacketizerCname`.
* **Only `chainRtcpReceivingSession` works on a receiving track.** The sender
  reporter needs an RTP configuration, which only the sending side's packetizer
  creates.
* **`onClient` fires before the handshake.** A WebSocket server hands you the
  client as soon as TCP is accepted; read `path()` from `onOpen`.
* **Empty strings mean "unset".** Optional `cstring` fields in the C
  configuration structs are passed as `nil`, never as a pointer to `""`,
  otherwise libdatachannel tries to load an empty certificate file.
* **`close()` everything.** Channels, tracks, peer connections and servers hold
  native resources until they are closed.
* **Callbacks run on libdatachannel's threads.** They never let a Nim
  exception escape into C++, and libdatachannel-nim keeps the objects alive for
  as long as the library may call back into them.
* **A callback that captures its own channel forms a reference cycle**
  (`client.onMessage = proc(...) = client.send(...)`), which Nim reports as
  `CycleCreated`. It is not a leak: `close()` drops the handlers and breaks the
  cycle, so as long as every channel is closed the memory is reclaimed.
* **Memory manager.** Build with `--mm:arc` (or `--gc:refc`). Nim's default
  `--mm:orc` corrupts its heap when Nim code allocates from threads the Nim
  runtime did not create, which is exactly what a WebRTC callback is. The test
  suite runs with ARC for this reason.

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/libdatachannel-nim/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/libdatachannel-nim/fork)

### 🎩 License
MIT license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2025 OpenPeeps & Contributors &mdash; All rights reserved.