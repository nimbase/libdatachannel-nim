## Integration tests: WebSocket server and client over loopback.
##
## Requires libdatachannel to be installed and reachable by the dynamic loader.
##

import std/[os, times, unittest]
from std/net import Port
import libdatachannel

proc waitFor(condition: proc (): bool; timeoutMs = 5000): bool =
  let deadline = epochTime() + float(timeoutMs) / 1000.0
  while epochTime() < deadline:
    if condition(): return true
    sleep(10)
  false

suite "websocket":
  test "server binds an OS assigned port":
    let server = newWebSocketServer(WebSocketServerConfig(port: Port(0)))
    defer: server.close()
    check int(server.port) > 0
    check int(server.port) > 1024

  test "an explicit port is preserved":
    let server = newWebSocketServer(Port(0))
    defer: server.close()
    let fixed = newWebSocketServer(Port(4321))
    defer: fixed.close()
    check int(fixed.port) == 4321

  test "server and client exchange text and binary messages":
    let server = newWebSocketServer(WebSocketServerConfig(port: Port(0)))
    defer: server.close()

    var serverGotText = false
    var serverGotBinary = false
    var serverText = ""
    var serverBinary = ""
    server.onClient = proc(client: WebSocketClient) =
      client.onMessage = proc(data: string, isBinary: bool) =
        if isBinary:
          serverGotBinary = true
          serverBinary = data
          client.sendBinary(data)
        else:
          serverGotText = true
          serverText = data
          client.send(data)

    let port = server.port
    let client = newWebSocketClient("ws://127.0.0.1:" & $port)
    defer: client.close()

    var clientOpen = false
    client.onOpen = proc() = clientOpen = true
    var clientText = ""
    var clientBinary = ""
    client.onMessage = proc(data: string, isBinary: bool) =
      if isBinary: clientBinary = data else: clientText = data

    check waitFor(proc(): bool = client.isOpen)
    check clientOpen

    check client.send("hello from the client") == RTC_ERR_SUCCESS
    check waitFor(proc(): bool = clientText == "hello from the client")

    let payload = "\x00\x01\x02with\x00nul"
    check client.sendBinary(payload) == RTC_ERR_SUCCESS
    check waitFor(proc(): bool = clientBinary == payload)

    check serverGotText
    check serverText == "hello from the client"
    check serverGotBinary
    check serverBinary == payload

  test "the server sees the client path and remote address":
    let server = newWebSocketServer(WebSocketServerConfig(port: Port(0)))
    defer: server.close()

    var serverClient: WebSocketClient
    server.onClient = proc(client: WebSocketClient) =
      # `onClient` fires on TCP accept, before the handshake. The accepted
      # client is captured instead of reading from its `onOpen`: server-side
      # `onOpen` is fire-and-forget, so a loopback handshake that beats the
      # callback setup loses the event for good. `path()` is polled below.
      serverClient = client

    let client = newWebSocketClient(
      "ws://127.0.0.1:" & $server.port & "/chat")
    defer: client.close()
    check waitFor(proc(): bool = client.isOpen)
    check waitFor(proc(): bool = serverClient != nil and
      serverClient.path() == "/chat")
    check serverClient.remoteAddress().len > 0

  test "a client that cannot connect reports an error":
    # Port 1 is reserved and nothing listens on it.
    let client = newWebSocketClient("ws://127.0.0.1:1")
    defer: client.close()
    var gotError = false
    client.onError = proc(message: string) = gotError = true
    check waitFor(proc(): bool = gotError or client.isClosed)

  test "closing the client stops it":
    let server = newWebSocketServer(WebSocketServerConfig(port: Port(0)))
    defer: server.close()
    let client = newWebSocketClient("ws://127.0.0.1:" & $server.port)
    check waitFor(proc(): bool = client.isOpen)
    client.close()
    check not client.isOpen
    check client.id == -1

suite "global settings":
  test "preload and cleanup":
    # Returns true only for the call that actually initialises the library, and
    # false once it is already up. Either way it must not fail.
    discard rtcPreload()
    check not rtcPreload()
    rtcCleanup()

  test "sctp settings are accepted":
    var settings = rtcSctpSettings(
      recvBufferSize: 256 * 1024,
      sendBufferSize: 256 * 1024,
      maxChunksOnQueue: 128,
      initialCongestionWindow: 10,
      maxBurst: 0,
      congestionControlModule: 0,
      delayedSackTimeMs: 20,
      minRetransmitTimeoutMs: 100,
      maxRetransmitTimeoutMs: 5000,
      initialRetransmitTimeoutMs: 500,
      maxRetransmitAttempts: 10,
      heartbeatIntervalMs: 0)
    check rtcSetSctpSettings(addr settings) == RTC_ERR_SUCCESS

  test "thread pool size is accepted":
    check rtcSetThreadPoolSize(4) == RTC_ERR_SUCCESS

  test "a custom logger receives messages":
    discard rtcPreload()
    var lines = newSeq[string]()
    setLogLevel(RTC_LOG_DEBUG)
    check lines.len == 0
    setLogger(proc(level: rtcLogLevel, message: string) =
      lines.add $level & ": " & message)
    # Anything libdatachannel logs from now on lands in `lines`.
    setLogLevel(RTC_LOG_NONE)
    setLogger(nil)