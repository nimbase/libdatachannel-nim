## High-level WebSocket client and server API.
##

import std/[locks, tables]
from std/net import Port, `$`, `==`
import ./bindings, ./utils, ./channel

## Re-exported so `import libdatachannel` alone is enough to read and print the
## port of a `WebSocketServer`.
export Port, `$`, `==`

type
  WebSocketId* = ChannelId

  WebSocketClientConfig* = object
    ## Nim friendly counterpart of `rtcWsConfiguration`.
    disableTlsVerification*: bool
      ## Do not verify the TLS certificate of a `wss://` endpoint.
    proxyServer*: string
    protocols*: seq[string]
      ## Sub-protocols offered during the handshake.
    tcpConnectionTimeoutMs*: int
      ## 0 means default, negative disables the timeout.
    connectionTimeoutMs*: int
      ## 0 means default, negative disables the timeout.
    pingIntervalMs*: int
      ## 0 means default, negative disables pings.
    maxOutstandingPings*: int
      ## 0 means default, negative disables the limit.
    maxMessageSize*: int
      ## <= 0 means the default.

  WebSocketServerConfig* = object
    ## Nim friendly counterpart of `rtcWsServerConfiguration`.
    port*: Port
      ## 0 lets the OS pick a free port, read it back with `WebSocketServer.port`.
    enableTls*: bool
      ## Serve `wss://` instead of `ws://`.
    certificatePemFile*: string
    keyPemFile*: string
    keyPemPass*: string
    bindAddress*: string
      ## Empty means any address.
    connectionTimeoutMs*: int
      ## 0 means default, negative disables the timeout.
    maxMessageSize*: int
      ## <= 0 means the default.

  WebSocketClient* = ref object of RtcChannel
    ## A WebSocket client. The connection is established in the background,
    ## `onOpen` fires once the handshake completed.
    proxyServer: string
    protocols: cstringArray

  WebSocketServer* = ref object of RootObj
    ## A WebSocket server running on its own thread.
    id*: WebSocketId
    config*: WebSocketServerConfig
    rawConfig*: rtcWsServerConfiguration
    clients*: Table[WebSocketId, WebSocketClient]
    onClient*: proc (client: WebSocketClient) {.closure.}
      ## Fired for every incoming connection, as soon as the TCP connection is
      ## accepted and **before** the WebSocket handshake completed. Wait for
      ## `client.onOpen` before reading `path`.
    strings: seq[string]
    lock: Lock

  WebSocketListener* = enum
    ## Selectable callback slots for the raw `listen` overloads.
    onOpened, onMessage, onClosed, onError

#
#  WebSocket server
#

proc clientTrampoline(wsserver: cint; ws: cint;
                      usePtr: pointer) {.cdecl.} =
  # `runInCallback` runs before the first allocation, and wrapping the client
  # object is one.
  runInCallback:
    if usePtr.isNil or ws < 0: return
    let server = cast[WebSocketServer](usePtr)
    if server.isNil: return
    var newClient = WebSocketClient()
    newClient.id = ws
    initChannel(newClient, ws)
    acquire(server.lock)
    server.clients[ws] = newClient
    release(server.lock)
    # Never call into user code while holding the lock.
    if server.onClient != nil:
      server.onClient(newClient)

proc newWebSocketServer*(config: WebSocketServerConfig): WebSocketServer =
  ## Create a WebSocket server. It starts listening immediately on its own
  ## thread, so this never blocks.
  new(result)
  initLock(result.lock)
  result.config = config
  # The C struct borrows these strings, so they must outlive the server.
  result.strings = @[
    config.certificatePemFile,
    config.keyPemFile,
    config.keyPemPass,
    config.bindAddress]
  result.rawConfig = rtcWsServerConfiguration(
    port: config.port.uint16,
    enableTls: config.enableTls,
    certificatePemFile: cstringOrNil(result.strings[0]),
    keyPemFile: cstringOrNil(result.strings[1]),
    keyPemPass: cstringOrNil(result.strings[2]),
    bindAddress: cstringOrNil(result.strings[3]),
    connectionTimeoutMs: cint(config.connectionTimeoutMs),
    maxMessageSize: cint(config.maxMessageSize))
  result.id = rtcCreateWebSocketServer(addr result.rawConfig, clientTrampoline)
  check result.id
  registerOwner(result.id, result)
  rtcSetUserPointer(result.id, cast[pointer](result))

proc newWebSocketServer*(port: Port = Port(0); enableTls = false): WebSocketServer =
  ## Shorthand for `newWebSocketServer(WebSocketServerConfig(port: ...))`.
  ## Use `newWebSocketServer(config)` for the full set of options.
  newWebSocketServer(WebSocketServerConfig(port: port, enableTls: enableTls))

proc port*(server: WebSocketServer): Port =
  ## The port the server listens on, including an OS-assigned one.
  if int(server.config.port) != 0: return server.config.port
  Port(uint16(rtcGetWebSocketServerPort(server.id)))

proc client*(server: WebSocketServer; id: WebSocketId): WebSocketClient =
  ## Look up a connected client by its libdatachannel id.
  acquire(server.lock)
  result = server.clients[id]
  release(server.lock)

proc close*(server: WebSocketServer) =
  ## Stop the server, disconnect every client and release its id.
  if server.isNil or server.id < 0: return
  acquire(server.lock)
  let clients = server.clients
  server.clients.clear()
  release(server.lock)
  # Stop accepting first, then release the websockets the server created for
  # its clients: `rtcDeleteWebSocketServer` leaves those in libdatachannel's
  # WebSocket map, only `rtcDeleteWebSocket` removes them.
  let id = server.id
  rtcSetUserPointer(id, nil)
  discard rtcDeleteWebSocketServer(id)
  unregisterOwner(id)
  server.onClient = nil
  server.id = -1
  for _, client in clients:
    client.close()

#
#  WebSocket client
#

proc newWebSocketClient*(url: string;
    config: WebSocketClientConfig): WebSocketClient =
  ## Start connecting to `url`. `onOpen` fires once the handshake completed.
  new(result)
  # Keep the strings the C struct borrowed alive for the whole connection.
  result.proxyServer = config.proxyServer
  result.protocols = toCStringArray(config.protocols)
  var rawConfig = rtcWsConfiguration(
    disableTlsVerification: config.disableTlsVerification,
    proxyServer: cstringOrNil(result.proxyServer),
    protocols: result.protocols,
    protocolsCount: cint(config.protocols.len),
    tcpConnectionTimeoutMs: cint(config.tcpConnectionTimeoutMs),
    connectionTimeoutMs: cint(config.connectionTimeoutMs),
    pingIntervalMs: cint(config.pingIntervalMs),
    maxOutstandingPings: cint(config.maxOutstandingPings),
    maxMessageSize: cint(config.maxMessageSize))
  var id = rtcCreateWebSocketEx(cstring(url), addr rawConfig)
  check id
  result.id = id
  initChannel(result, id)

proc newWebSocketClient*(url: string; disableTlsVerification = false): WebSocketClient =
  ## Shorthand for `newWebSocketClient(url, WebSocketClientConfig(...))`.
  ## Use the config overload for the full set of options.
  newWebSocketClient(url,
    WebSocketClientConfig(disableTlsVerification: disableTlsVerification))

proc remoteAddress*(client: WebSocketClient): string =
  ## The remote address of the connection, empty while it is still
  ## connecting.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetWebSocketRemoteAddress(client.id, cast[cstring](buffer), size))

proc path*(client: WebSocketClient): string =
  ## The request path the client connected to, empty until the handshake
  ## completed. On a server side client, read it from `onOpen`.
  getCString(proc (buffer: pointer; size: cint): cint =
    rtcGetWebSocketPath(client.id, cast[cstring](buffer), size))

proc close*(ws: WebSocketClient) =
  ## Close the connection and release the id.
  if ws.isNil or ws.id < 0: return
  # Free the owned array before detaching: `detachChannel` drops the last
  # reference this module holds, so `ws` must not be touched afterwards.
  if ws.protocols != nil:
    freeCStringArray(ws.protocols)
    ws.protocols = nil
  let id = ws.id
  discard rtcClose(id)
  # Detach before deleting, see `RtcChannel.close`.
  detachChannel(ws)
  discard rtcDeleteWebSocket(id)

#
#  Raw channel helpers
#

proc send*(id: WebSocketId; message: string) =
  ## Send a text message through a raw libdatachannel WebSocket id.
  check rtcSendMessage(id, cstring(message), cint(0 - message.len))

proc message*(id: WebSocketId; message: string) =
  ## Alias for `send`.
  id.send(message)

proc listen*(ws: WebSocketClient; listener: WebSocketListener;
             callback: rtcOpenCallbackFunc | rtcClosedCallbackFunc) =
  ## Listen for open/closed events using a raw libdatachannel callback.
  case listener
  of onOpened: check rtcSetOpenCallback(ws.id, callback)
  of onClosed: check rtcSetClosedCallback(ws.id, callback)
  else: raise newException(LibDataChannelError,
    "listener " & $listener & " needs a matching callback signature")

proc listen*(ws: WebSocketClient; listener: WebSocketListener;
             callback: rtcMessageCallbackFunc) =
  ## Listen for messages using a raw libdatachannel callback.
  case listener
  of onMessage: check rtcSetMessageCallback(ws.id, callback)
  else: raise newException(LibDataChannelError,
    "listener " & $listener & " needs a matching callback signature")

proc listen*(ws: WebSocketClient; listener: WebSocketListener;
             callback: rtcErrorCallbackFunc) =
  ## Listen for errors using a raw libdatachannel callback.
  case listener
  of onError: check rtcSetErrorCallback(ws.id, callback)
  else: raise newException(LibDataChannelError,
    "listener " & $listener & " needs a matching callback signature")