## Nim bindings for libdatachannel: a standalone C++ library for WebRTC
## DataChannels, WebRTC media transport and WebSockets.
##
## `import libdatachannel` gives you both layers:
##
## * the **high-level API** (`PeerConnection`, `DataChannel`, `Track`,
##   `WebSocketClient`, `WebSocketServer`) written in Nim style, and
## * the **low-level bindings** (`libdatachannel/bindings`), a 1:1 mapping of
##   the C API for when you need full control.
##
## ```nim
## import std/[os]
## import libdatachannel
##
## let server = newWebSocketServer(Port(1234))
## server.onClient = proc(client: WebSocketClient) =
##   client.onMessage = proc(data: string, isBinary: bool) =
##     client.send(data)
##
## while true:
##   sleep(1000)
## ```
##

import ./libdatachannel/bindings
import ./libdatachannel/utils
import ./libdatachannel/channel
import ./libdatachannel/datachannel
import ./libdatachannel/track
import ./libdatachannel/peerconnection
import ./libdatachannel/websockets
import ./libdatachannel/logging

export bindings, utils, channel, datachannel, track, peerconnection,
  websockets, logging