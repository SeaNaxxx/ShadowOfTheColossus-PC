# The guest CPU adapter is a shared library so the native probe can load it independently.
set(SOTC_CPU_DIR "${CMAKE_CURRENT_LIST_DIR}")
add_library(sotc_cpu SHARED
    "${SOTC_CPU_DIR}/../src/guest_cpu_fex.cpp"
    "${SOTC_CPU_DIR}/../src/host_call_arm64.S")
target_include_directories(sotc_cpu PRIVATE
    "${SOTC_CPU_DIR}/../src"
    "${CMAKE_SOURCE_DIR}/Source"
    "${CMAKE_BINARY_DIR}/generated")
target_link_libraries(sotc_cpu PRIVATE FEXCore Common JemallocLibs fmt::fmt)
target_link_options(sotc_cpu PRIVATE -Wl,--no-undefined)
target_compile_options(sotc_cpu PRIVATE ${FEX_TUNE_COMPILE_FLAGS})
set_target_properties(sotc_cpu PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET default
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN FALSE)

if(ANDROID)
    # The runtime calls FEXCore directly; FEXServer's client transport is unused.
    get_target_property(sotc_common_sources Common SOURCES)
    list(FILTER sotc_common_sources EXCLUDE REGEX "FEXServerClient\\.cpp$")
    set_target_properties(Common PROPERTIES SOURCES "${sotc_common_sources}")
endif()
