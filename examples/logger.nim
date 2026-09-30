## Route libdatachannel's internal logging into Nim's logging system.
##
##     nim c -r --path:src examples/logger.nim
##

import std/[locks, logging, os, strutils, times]
import libdatachannel

proc main() =
  addHandler(newConsoleLogger())
  setLogFilter(lvlAll)

  var level = RTC_LOG_WARNING
  if paramCount() > 0:
    case paramStr(1).toLowerAscii
    of "none": level = RTC_LOG_NONE
    of "fatal": level = RTC_LOG_FATAL
    of "error": level = RTC_LOG_ERROR
    of "warning": level = RTC_LOG_WARNING
    of "info": level = RTC_LOG_INFO
    of "debug": level = RTC_LOG_DEBUG
    of "verbose": level = RTC_LOG_VERBOSE
    else:
      stderr.writeLine("unknown level: ", paramStr(1))
      quit(1)

  setLogger(proc(lvl: rtcLogLevel; message: string) =
    case lvl
    of RTC_LOG_ERROR, RTC_LOG_FATAL: error(message)
    of RTC_LOG_WARNING: warn(message)
    of RTC_LOG_INFO: info(message)
    else: debug(message))

  echo "libdatachannel ", RTC_VERSION, " logging at level ", level
  discard rtcPreload()

when isMainModule:
  main()
