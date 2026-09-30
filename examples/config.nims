# Makes `nim c -r examples/foo.nim` work from a checkout, without installing
# the package and without exporting LD_LIBRARY_PATH first.
switch("path", "$projectDir/../src")

# libdatachannel is loaded through `dynlib` at run time, so there is nothing to
# link against at build time. These flags make the examples find it on their
# own; see tests/config.nims for the details.
const
  libDir = getEnv("LIBDATACHANNEL_LIB_DIR", "/usr/local/lib")
  includeDir = getEnv("LIBDATACHANNEL_INCLUDE_DIR", "/usr/local/include")

switch("passC", "-I" & includeDir)
switch("passL", "-L" & libDir)
when not defined(windows):
  # Windows resolves DLLs next to the executable and on PATH instead.
  switch("passL", "-Wl,-rpath," & libDir)