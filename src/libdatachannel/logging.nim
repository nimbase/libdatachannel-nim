## Global logging for libdatachannel.
##
## The library logs from its own threads, so output goes to `stderr` instead of
## relying on the C `stdout` stream. Call `enableLogging()` once at startup to
## see what libdatachannel is doing.
##

import std/locks
import ./bindings, ./utils

type
  Logger* = proc (level: rtcLogLevel; message: string) {.closure.}
    ## Signature of a custom log sink.

var
  logLock: Lock
  customLogger: Logger

proc defaultLogger(level: rtcLogLevel; message: string) =
  stderr.writeLine("[libdatachannel] " & $level & ": " & message)

proc loggerTrampoline(level: rtcLogLevel; message: cstring) {.cdecl.} =
  # Runs on whichever libdatachannel thread produced the line, and building the
  # Nim string allocates, so the thread has to be prepared first.
  runInCallback:
    acquire(logLock)
    let sink = customLogger
    release(logLock)
    # `enableLogging` installs the trampoline without a custom sink, so fall
    # back to the built-in logger instead of dropping the message.
    if sink.isNil: defaultLogger(level, $message)
    else: sink(level, $message)

proc setLogger*(logger: Logger) {.raises: [].} =
  ## Install a custom log sink. Pass `nil` to go back to the built-in
  ## `stderr` logger.
  acquire(logLock)
  customLogger = logger
  release(logLock)
  if logger.isNil:
    rtcInitLogger(RTC_LOG_WARNING, loggerTrampoline)
  else:
    rtcInitLogger(RTC_LOG_VERBOSE, loggerTrampoline)

proc setLogLevel*(level: rtcLogLevel) {.raises: [].} =
  ## Set the verbosity, keeping the sink that is currently installed.
  acquire(logLock)
  let sink = customLogger
  release(logLock)
  if sink.isNil:
    rtcInitLogger(level, nil)
  else:
    rtcInitLogger(level, loggerTrampoline)

proc setLogLevel*(level: rtcLogLevel; logger: Logger) {.raises: [].} =
  ## Set the verbosity and install a sink in one call.
  acquire(logLock)
  customLogger = logger
  release(logLock)
  if logger.isNil:
    rtcInitLogger(level, nil)
  else:
    rtcInitLogger(level, loggerTrampoline)

proc enableLogging*(level: rtcLogLevel = RTC_LOG_INFO) {.raises: [].} =
  ## Log everything at `level` or above to `stderr`.
  acquire(logLock)
  customLogger = nil
  release(logLock)
  if level == RTC_LOG_NONE:
    rtcInitLogger(level, nil)
  else:
    rtcInitLogger(level, loggerTrampoline)