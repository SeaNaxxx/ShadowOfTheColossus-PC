# Add the SotC CPU backend after FEXCore has defined its targets.
cmake_language(EVAL CODE "cmake_language(DEFER DIRECTORY \"${CMAKE_SOURCE_DIR}\" CALL include \"${CMAKE_CURRENT_LIST_DIR}/sotc_cpu.cmake\")")

if(ANDROID AND CMAKE_SYSTEM_NAME STREQUAL "Android")
    # FEX treats Android as Linux while retaining the Android toolchain and Bionic headers.
    set(CMAKE_SYSTEM_NAME Linux)
    add_compile_definitions(_GNU_SOURCE)
    add_compile_options("-include" "${CMAKE_CURRENT_LIST_DIR}/bionic_compat.h")
endif()
