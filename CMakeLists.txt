cmake_minimum_required(VERSION 3.10)
project(RetroC C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(LIB_BASE_DIR "C:/libraries")
set(RAYLIB_DIR "${LIB_BASE_DIR}/raylib")
set(LUAJIT_DIR "${LIB_BASE_DIR}/LuaJIT")

file(GLOB_RECURSE SOURCES
        "src/*.c"
)

add_executable(RetroC ${SOURCES}
        src/engine/App.c
        src/engine/App.h)

target_include_directories(RetroC PUBLIC
        "${RAYLIB_DIR}/src"         # Raylib headers
        "${LUAJIT_DIR}/src"         # LuaJIT headers
        "${CMAKE_SOURCE_DIR}/src"   # Your project headers
)

if (WIN32)
    set(LUA_LIB "${LUAJIT_DIR}/src/lua51.lib")

    set(RAY_LIB "C:/libraries/raylib/projects/VS2022/build/raylib/bin/x64/Release/raylib.lib")

    target_link_libraries(RetroC PRIVATE
            ${LUA_LIB}
            ${RAY_LIB}
            winmm
            gdi32
            opengl32
            shell32
            user32
    )
else()
    find_library(RAYLIB_NAMES raylib)
    find_library(LUA_NAMES luajit-5.1)
    target_link_libraries(RetroC PRIVATE ${RAYLIB_NAMES} ${LUA_NAMES})
endif()

add_custom_command(TARGET RetroC POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/resources"
        "$<TARGET_FILE_DIR:RetroC>/resources"
)

if (WIN32)
    add_custom_command(TARGET RetroC POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${LUAJIT_DIR}/src/lua51.dll"
            "$<TARGET_FILE_DIR:RetroC>/lua51.dll"
    )
endif()