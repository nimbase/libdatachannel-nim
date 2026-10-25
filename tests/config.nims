switch("path", "$projectDir/../src")

# libdatachannel invokes Nim callbacks from threads the Nim runtime did not
# create. That is safe with ARC and corrupts the heap with ORC, so the
# memory manager is pinned here: `clue test`, `nim c` and CI all pick it up
# automatically. An explicit `--mm` on the command line still wins.
switch("mm", "arc")

# libdatachannel is loaded through `dynlib` at run time, so there is nothing to
# link against at build time. What these flags buy is a binary that finds
# `libdatachannel.so` on its own, without exporting LD_LIBRARY_PATH first:
#
#   --passC -I              include path, for the rare case of `{.emit.}`-ing
#                           `#include <rtc.h>` into a Nim translation unit
#   --passL -L              library search path, for anything that does link
#   --passL -rpath          run-time search path, the part that actually matters
#
# Set LIBDATACHANNEL_LIB_DIR / LIBDATACHANNEL_INCLUDE_DIR when libdatachannel
# lives somewhere else than the default install prefix.
const
  libDir = getEnv("LIBDATACHANNEL_LIB_DIR", "/usr/local/lib")
  includeDir = getEnv("LIBDATACHANNEL_INCLUDE_DIR", "/usr/local/include")

switch("passC", "-I" & includeDir)
switch("passL", "-L" & libDir)
when not defined(windows):
  # Windows resolves DLLs next to the executable and on PATH instead.
  switch("passL", "-Wl,-rpath," & libDir)