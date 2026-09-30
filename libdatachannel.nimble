# Package

version       = "0.2.0"
author        = "OpenPeeps"
description   = "Standalone WebRTC Data Channels, WebRTC Media Transport, and WebSockets"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"


# Tasks
#
# libdatachannel-nim runs Nim code on threads the Nim runtime did not create.
# That is safe with ARC, and it corrupts the heap with ORC, so every task here
# builds with `--mm:arc`.

task examples, "Build all examples into ./examples/bin":
  mkDir "examples/bin"
  for example in ["websocket_server", "websocket_client",
                  "peer_connection", "peer_connection_client",
                  "peer_connection_server", "track_video", "logger"]:
    exec "nim c --mm:arc --path:src -o:examples/bin/" & example &
          " examples/" & example & ".nim"
    echo "built examples/bin/" & example