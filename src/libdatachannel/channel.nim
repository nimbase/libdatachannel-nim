## The common base of every bidirectional channel: DataChannel, Track and
## WebSocket. All of them share the same `open`/`closed`/`error`/`message`
## callbacks and the same send/receive API.
##

import std/[locks, tables]
import ./bindings, ./utils

type
  ChannelId* = cint
    ## The libdatachannel handle of a channel.

  RtcChannel* = ref object of RootObj
    ## Common API of a DataChannel, a Track or a WebSocket.
    ##
    ## Channels are ref counted and are kept alive by libdatachannel as long
    ## as they are open. Always `close()` them when you are done.
    id*: ChannelId
    userData*: pointer
      ## Free for use by the application, passed to nothing by libdatachannel.
    onOpen*: proc() {.closure.}
      ## Called when the channel is open and ready to send.
    onClosed*: proc() {.closure.}
      ## Called when the channel has been closed.
    onError*: proc(message: string) {.closure.}
      ## Called when the channel reported an error.
    onMessage*: proc(data: string; isBinary: bool) {.closure.}
      ## Called for every incoming message. `isBinary` is `false` for text.
    onBufferedAmountLow*: proc() {.closure.}
      ## Called when the buffered amount dropped below the configured
      ## threshold.
    onAvailable*: proc() {.closure.}
      ## Called when data became available on the incoming queue.

#
#  Object registry
#
# libdatachannel invokes the callbacks from its own threads and only passes a
# `void *` that we control, so we have to keep the Nim objects alive ourselves
# for as long as libdatachannel may call back into them. PeerConnections and
# WebSocketServers get the same treatment: `rtcDeletePeerConnection` returns
# before every worker thread is necessarily done, and a callback that is
# already in flight would otherwise dereference a freed object.
#

var
  registryLock: Lock
  channelRegistry = initTable[ChannelId, RtcChannel]()
  ownerRegistry = initTable[cint, RootRef]()

initLock(registryLock)
  # Module level initialisers run before any thread exists, so this is safe.

proc registerChannel(ch: RtcChannel) =
  acquire(registryLock)
  channelRegistry[ch.id] = ch
  release(registryLock)

proc unregisterChannel(id: ChannelId) =
  acquire(registryLock)
  channelRegistry.del(id)
  release(registryLock)

proc isChannelRegistered*(id: ChannelId): bool =
  ## Whether `id` is a live channel known to this module.
  acquire(registryLock)
  result = channelRegistry.hasKey(id)
  release(registryLock)

proc registerOwner*(id: cint; obj: RootRef) =
  ## Keep `obj` alive until `unregisterOwner` is called for `id`.
  acquire(registryLock)
  ownerRegistry[id] = obj
  release(registryLock)

proc unregisterOwner*(id: cint) =
  ## Release the reference taken by `registerOwner`.
  acquire(registryLock)
  ownerRegistry.del(id)
  release(registryLock)

proc releaseAllChannels*() =
  ## Drop every reference libdatachannel-nim still holds on channels,
  ## PeerConnections and WebSocketServers. Only useful right before
  ## `rtcCleanup()`.
  acquire(registryLock)
  channelRegistry.clear()
  ownerRegistry.clear()
  release(registryLock)

#
#  Callback trampolines
#
# They only ever run when libdatachannel hands us a non-nil user pointer, which
# we set in `initChannel` and clear in `detachChannel`.
#

#  Every trampoline below prepares the thread *before* its first allocation,
#  not just around the user handler: constructing the wrapper objects a
#  DataChannel, Track or WebSocket needs is already a heap allocation.

proc onOpenTrampoline(id: cint; usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let ch = cast[RtcChannel](usePtr)
    if ch.isNil or ch.onOpen.isNil: return
    ch.onOpen()

proc onClosedTrampoline(id: cint; usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let ch = cast[RtcChannel](usePtr)
    if ch.isNil or ch.onClosed.isNil: return
    ch.onClosed()

proc onErrorTrampoline(id: cint; error: cstring; usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let ch = cast[RtcChannel](usePtr)
    if ch.isNil or ch.onError.isNil: return
    ch.onError($error)

proc onMessageTrampoline(id: cint; message: cstring; size: cint;
                         usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let ch = cast[RtcChannel](usePtr)
    if ch.isNil or ch.onMessage.isNil: return
    # A negative size marks a text message, whose length is `-size - 1` and
    # which is NUL terminated. A positive size marks a binary message.
    if size < 0:
      ch.onMessage(toNimBytes(message, -size - 1), false)
    else:
      ch.onMessage(toNimBytes(message, size), true)

proc onBufferedAmountLowTrampoline(id: cint; usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let ch = cast[RtcChannel](usePtr)
    if ch.isNil or ch.onBufferedAmountLow.isNil: return
    ch.onBufferedAmountLow()

proc onAvailableTrampoline(id: cint; usePtr: pointer) {.cdecl.} =
  runInCallback:
    if usePtr.isNil: return
    let ch = cast[RtcChannel](usePtr)
    if ch.isNil or ch.onAvailable.isNil: return
    ch.onAvailable()

#
#  RtcChannel lifecycle
#

proc initChannel*(ch: RtcChannel; id: ChannelId) {.raises: [].} =
  ## Bind a freshly allocated Nim object to an existing libdatachannel id and
  ## install the callback trampolines.
  doAssert id >= 0
  ch.id = id
  ch.userData = nil
  rtcSetUserPointer(id, cast[pointer](ch))
  discard rtcSetOpenCallback(id, onOpenTrampoline)
  discard rtcSetClosedCallback(id, onClosedTrampoline)
  discard rtcSetErrorCallback(id, onErrorTrampoline)
  discard rtcSetMessageCallback(id, onMessageTrampoline)
  discard rtcSetBufferedAmountLowCallback(id, onBufferedAmountLowTrampoline)
  discard rtcSetAvailableCallback(id, onAvailableTrampoline)
  registerChannel(ch)

proc detachChannel*(ch: RtcChannel) {.raises: [].} =
  ## Stop routing libdatachannel callbacks to `ch` and release our reference.
  if ch.isNil or ch.id < 0:
    # Already detached: `ch.id` is -1 and the libdatachannel id is gone, so
    # calling back into the library would throw.
    return
  let id = ch.id
  rtcSetUserPointer(id, nil)
  discard rtcSetOpenCallback(id, nil)
  discard rtcSetClosedCallback(id, nil)
  discard rtcSetErrorCallback(id, nil)
  discard rtcSetMessageCallback(id, nil)
  discard rtcSetBufferedAmountLowCallback(id, nil)
  discard rtcSetAvailableCallback(id, nil)
  # Dropping the handlers breaks the reference cycle that appears whenever a
  # callback captures the channel it belongs to, which is the common case.
  ch.onOpen = nil
  ch.onClosed = nil
  ch.onError = nil
  ch.onMessage = nil
  ch.onBufferedAmountLow = nil
  ch.onAvailable = nil
  # Unregistering may drop the last reference this module holds and free `ch`,
  # so invalidate it first and never touch it again afterwards.
  ch.id = -1
  unregisterChannel(id)

#
#  RtcChannel API
#

proc isOpen*(ch: RtcChannel): bool {.raises: [].} =
  ## Whether the channel is open and ready to send.
  ch.id >= 0 and rtcIsOpen(ch.id)

proc isClosed*(ch: RtcChannel): bool {.raises: [].} =
  ## Whether the channel has been closed. A detached channel counts as closed.
  ch.id < 0 or rtcIsClosed(ch.id)

proc send*(ch: RtcChannel; data: string): cint {.discardable.} =
  ## Send `data` as a **text** message. Returns `RTC_ERR_SUCCESS` on success or
  ## a negative libdatachannel error code.
  if ch.id < 0: return RTC_ERR_INVALID
  rtcSendMessage(ch.id, cstring(data), cint(0 - data.len))

proc sendBinary*(ch: RtcChannel; data: openArray[byte]): cint {.discardable.} =
  ## Send the raw bytes of `data` as a **binary** message.
  if ch.id < 0: return RTC_ERR_INVALID
  if data.len == 0: return rtcSendMessage(ch.id, nil, 0)
  rtcSendMessage(ch.id, cast[cstring](unsafeAddr data[0]), cint(data.len))

proc sendBinary*(ch: RtcChannel; data: string): cint {.discardable.} =
  ## Send the raw bytes of `data` as a **binary** message, without validating
  ## that it holds only text.
  if ch.id < 0: return RTC_ERR_INVALID
  if data.len == 0: return rtcSendMessage(ch.id, nil, 0)
  rtcSendMessage(ch.id, cstring(data), cint(data.len))

proc sendText*(ch: RtcChannel; data: string): cint {.discardable.} =
  ## Explicit alias for `send`.
  ch.send(data)

proc send*(ch: RtcChannel; data: openArray[byte]): cint {.discardable.} =
  ## Explicit alias for `sendBinary`.
  ch.sendBinary(data)

proc maxMessageSize*(ch: RtcChannel): cint {.raises: [].} =
  ## Maximum size of a message accepted on the incoming queue.
  if ch.id < 0: return 0
  rtcMaxMessageSize(ch.id)

proc bufferedAmount*(ch: RtcChannel): cint {.raises: [].} =
  ## Total size buffered for sending.
  if ch.id < 0: return 0
  rtcGetBufferedAmount(ch.id)

proc availableAmount*(ch: RtcChannel): cint {.raises: [].} =
  ## Total size available on the incoming queue.
  if ch.id < 0: return 0
  rtcGetAvailableAmount(ch.id)

proc setBufferedAmountLowThreshold*(ch: RtcChannel; amount: cint) =
  ## Set the threshold that triggers `onBufferedAmountLow`.
  if ch.id < 0: return
  discard rtcSetBufferedAmountLowThreshold(ch.id, amount)

proc receiveMessage*(ch: RtcChannel; maxSize: cint = 0): tuple[data: string,
                                                             isBinary: bool,
                                                             size: cint] =
  ## Pop the oldest message from the incoming queue without going through
  ## `onMessage`. An empty `data` is returned when the queue is empty.
  if ch.id < 0 or rtcGetAvailableAmount(ch.id) <= 0:
    return (data: "", isBinary: false, size: RTC_ERR_NOT_AVAIL)
  var size = if maxSize > 0: maxSize else: rtcGetAvailableAmount(ch.id)
  var buf = newString(size)
  let code = rtcReceiveMessage(ch.id, cast[cstring](addr buf[0]), addr size)
  if code < 0: return (data: "", isBinary: false, size: code)
  result.isBinary = size >= 0
  if result.isBinary:
    buf.setLen(size)
  else:
    buf.setLen(-size - 1)
  result.data = buf
  result.size = size

proc close*(ch: RtcChannel) {.raises: [].} =
  ## Close the channel and release the underlying libdatachannel id.
  ## Works for DataChannels, Tracks and WebSockets alike.
  if ch.isNil or ch.id < 0: return
  let id = ch.id
  discard rtcClose(id)
  # Detach *before* deleting: `rtcDelete` erases the id from libdatachannel's
  # maps, and every `rtcSet*Callback` on a vanished id throws inside the
  # library.
  detachChannel(ch)
  discard rtcDelete(id)