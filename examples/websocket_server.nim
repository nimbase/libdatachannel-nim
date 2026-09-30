## A WebSocket echo server.
##
## Run it, then point `websocket_client.nim` at the port it prints:
##
##     nim c -r --path:src examples/websocket_server.nim
##
## Call `enableLogging()` (already done here) to see libdatachannel's own log
## output, or drop it to stay quiet.
##

import std/os
import libdatachannel

const
  BindAddress = "0.0.0.0"
  ListenPort = 8080

proc onClient(client: WebSocketClient) =
  echo "[+] client connected from ", client.remoteAddress(),
       " (", client.path(), ")"
  # `onClient` fires as soon as the TCP connection is accepted, so anything
  # that depends on the handshake has to wait for `onOpen`.
  client.onOpen = proc() =
    echo "[*] handshake complete"
    client.send("Welcome to the libdatachannel-nim echo server!")
  client.onMessage = proc(data: string; isBinary: bool) =
    let kind = if isBinary: "binary" else: "text"
    echo "[*] ", data.len, " ", kind, " bytes: ", data
    # Echo it straight back, preserving the framing.
    if isBinary:
      client.sendBinary(data)
    else:
      client.send(data)
  client.onClosed = proc() =
    echo "[-] client disconnected"
  client.onError = proc(message: string) =
    stderr.writeLine("[!] client error: " & message)

proc main() =
  enableLogging()

  let server = newWebSocketServer(WebSocketServerConfig(
    port: Port(ListenPort),
    bindAddress: BindAddress,
  ))
  defer: server.close()
  server.onClient = onClient

  echo "WebSocket echo server listening on ws://", BindAddress, ":", server.port
  echo "Press Ctrl+C to quit."

  while true:
    sleep(1000)

when isMainModule:
  main()