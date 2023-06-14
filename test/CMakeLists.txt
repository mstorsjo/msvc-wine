cmake_minimum_required(VERSION 3.25)
project(hello)

set(hello_SOURCES hello.c)
if (WIN32)
    list(APPEND hello_SOURCES hello.rc)
endif()
add_executable(hello ${hello_SOURCES})


if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC" AND DEFINED MSVCDIR)
    add_library(cxxmodules STATIC "${MSVCDIR}/modules/std.ixx")
    target_compile_options(cxxmodules PUBLIC /std:c++latest)
endif()
