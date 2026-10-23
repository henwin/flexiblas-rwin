# Minimal config for Rtools45's autotools-installed dlfcn-win32 (static).
set(dlfcn-win32_INCLUDEDIR "${CMAKE_FIND_ROOT_PATH}/include")
if(NOT TARGET dlfcn-win32::dl)
  find_library(_DLFCN_LIB NAMES dl REQUIRED)
  add_library(dlfcn-win32::dl STATIC IMPORTED)
  set_target_properties(dlfcn-win32::dl PROPERTIES IMPORTED_LOCATION "${_DLFCN_LIB}"
    INTERFACE_LINK_LIBRARIES "psapi")
endif()
set(dlfcn-win32_FOUND TRUE)
