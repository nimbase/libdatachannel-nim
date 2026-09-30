## A WebSocket client that talks to `websocket_server.nim`.
##
##     # terminal 1
##     nim c -r --path:src examples/websocket_server.nim
##     # terminal 2
##     nim c -r --path:src examples/websocket_client.nim
##
## Pass a different URL to connect somewhere else:
##
##     nim c -r --path:src examples/websocket_client.nim wss://example.com/socket
##

import std/[os, strutils]
import libdatachannel

const
  DefaultUrl = "ws://127.0.0.1:8080"
  Greeting = "Welcome to the libdatachannel-nim echo server!"

var finished = false
var failure = ""

proc main(url: string) =
  enableLogging()

  let client = newWebSocketClient(url)
  defer: client.close()

  # Callbacks run on libdatachannel's own threads, so they hand control back to
  # the main loop through a flag instead of calling `quit` from there.
  client.onOpen = proc() =
    echo "[*] connected to ", url
    client.send("Hello from Nim!")

  client.onMessage = proc(data: string; isBinary: bool) =
    let kind = if isBinary: "binary" else: "text"
    echo "[<] ", data.len, " ", kind, " bytes: ", data
    if not isBinary and data == Greeting:
      # Binary payloads go out verbatim, NUL bytes included.
      client.sendBinary("raw\0bytes\0here")
      client.send("Goodbye!")
    elif data == "Goodbye!":
      # The server echoes every message back unchanged.
      echo "[*] round trip complete"
      finished = true

  client.onClosed = proc() =
    echo "[*] server closed the connection"
    finished = true

  client.onError = proc(message: string) =
    stderr.writeLine("[!] ", message)
    failure = message
    finished = true

  echo "Connecting to ", url, " ..."
  while not finished:
    sleep(50)

  if failure.len > 0:
    quit(1)

when isMainModule:
  main(if paramCount() > 0: paramStr(1) else: DefaultUrl)