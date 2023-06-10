cmake_minimum_required(VERSION 3.25)
project(hello)

set(hello_SOURCES hello.c)
if (WIN32)
    list(APPEND hello_SOURCES hello.rc)
endif()
add_executable(hello ${hello_SOURCES})
