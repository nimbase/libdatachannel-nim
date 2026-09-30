# Examples

Every example is a single file with no dependencies beyond `libdatachannel`
itself. Build and run one straight from a checkout:

```bash
nim c -r examples/websocket_server.nim
```

`examples/config.nims` adds `src/` to the path, so the command above works
without installing the package.

libdatachannel has to be installed and reachable by the dynamic loader. On
Linux that usually means `LD_LIBRARY_PATH=/usr/local/lib`, or an
`/etc/ld.so.conf.d/` entry:

```bash
LD_LIBRARY_PATH=/usr/local/lib nim c -r examples/websocket_server.nim
```

---

## WebSockets

| File | What it does |
| --- | --- |
| [`websocket_server.nim`](websocket_server.nim) | An echo server that logs every frame and preserves text/binary framing. |
| [`websocket_client.nim`](websocket_client.nim) | Connects to the server, exchanges a text and a binary message, then exits. Takes an optional URL. |

```bash
# terminal 1
nim c -r examples/websocket_server.nim
# terminal 2
nim c -r examples/websocket_client.nim
```

## Peer connections

| File | What it does |
| --- | --- |
| [`peer_connection.nim`](peer_connection.nim) | A full data channel call between two PeerConnections **in one process**. No copy-pasting, one command. Start here. |
| [`peer_connection_client.nim`](peer_connection_client.nim) | The calling side of the classic copy-paste signalling flow. |
| [`peer_connection_server.nim`](peer_connection_server.nim) | The answering side of the same flow. |

```bash
nim c -r examples/peer_connection.nim
```

`peer_connection.nim` wires the two PeerConnections to each other directly:
every description and ICE candidate produced by one is handed to the other,
exactly the way a signalling server would relay them. It is the quickest way
to see a working data channel.

The two-process pair does the same thing with a human in the middle:

```bash
# terminal 1
nim c -r examples/peer_connection_client.nim
#   -> prints an offer, paste it into terminal 2
# terminal 2
nim c -r examples/peer_connection_server.nim "<offer>"
#   -> prints an answer, paste it back into terminal 1
```

Descriptions are base64 encoded so they survive a terminal copy-paste.

## Media

| File | What it does |
| --- | --- |
| [`track_video.nim`](track_video.nim) | Sends synthetic VP8 frames over a Track and depacketizes them on the other side, printing frame counts and RTP timestamps. |

```bash
nim c -r examples/track_video.nim
```

Swap `makeFrame` for frames from a real encoder to move actual media.

## Logging

| File | What it does |
| --- | --- |
| [`logger.nim`](logger.nim) | Pipes libdatachannel's internal log into Nim's `std/logging`. Takes a level: `none`, `fatal`, `error`, `warning`, `info`, `debug`, `verbose`. |

```bash
nim c -r examples/logger.nim debug
```

The same is available from every example through `enableLogging()`:

```nim
enableLogging()                 # info level, to stderr
enableLogging(RTC_LOG_WARNING)  # quieter
setLogLevel(RTC_LOG_NONE)       # silent
setLogger(proc(level, message) = ...)  # somewhere else entirely
```

## Things the examples do on purpose

* **A DataChannel or Track must exist before `setLocalDescription`.**
  libdatachannel refuses to negotiate a connection with nothing to negotiate,
  so every example opens a channel or adds a track first.
* **Callbacks run on libdatachannel's threads.** They hand control back to the
  main loop through a flag instead of calling `quit` from inside a callback.
* **Everything has to be closed.** `close()` on a PeerConnection, WebSocket
  server, DataChannel, Track or WebSocket client releases the underlying id;
  leaving one open keeps it alive for the lifetime of the process.
* **Handshake-dependent data waits for `onOpen`.** A WebSocket server's
  `onClient` fires when the TCP connection is accepted, so `path()` is only
  readable once the handshake completed.