cmake_minimum_required(VERSION 3.10)
project(RetroC C)
set(CMAKE_C_STANDARD 11)

set(RAYLIB_PATH "" CACHE PATH "Path to raylib (root with include/ and lib/)")
set(LUAJIT_SRC_PATH "" CACHE PATH "Path to LuaJIT src directory (contains lua.h)")

if (NOT RAYLIB_PATH)
    message(FATAL_ERROR "RAYLIB_PATH is required. Set it to the raylib root directory.")
endif()
if (NOT LUAJIT_SRC_PATH)
    message(FATAL_ERROR "LUAJIT_SRC_PATH is required. Set it to the LuaJIT src directory.")
endif()

set(LUAJIT_LIB "${LUAJIT_SRC_PATH}/libluajit-5.1.dll.a")
set(LUAJIT_DLL "${LUAJIT_SRC_PATH}/lua51.dll")

add_executable(RetroC
        src/main.c
        src/engine/RenderBuffer.c
        src/engine/LuaEngine.c
        src/lua/LuaKeyboard.c
        src/lua/LuaGraphics.c
        src/lua/LuaSystem.c
)

target_include_directories(RetroC PUBLIC
        ${RAYLIB_PATH}/include
        ${LUAJIT_SRC_PATH} # for lua.h, luajit.h, lauxlib.h, etc.
        ${CMAKE_SOURCE_DIR}/src
)

if (WIN32)
    target_link_directories(RetroC PRIVATE ${RAYLIB_PATH}/lib)
    target_link_libraries(RetroC
            ${LUAJIT_LIB}        # link LuaJIT
            raylib
            opengl32
            gdi32
            winmm
    )
elseif (APPLE)
    target_link_directories(RetroC PRIVATE ${RAYLIB_PATH}/lib)
    target_link_libraries(RetroC
            ${LUAJIT_LIB}
            raylib
            "-framework OpenGL"
            "-framework Cocoa"
            "-framework IOKit"
            "-framework CoreVideo"
    )
else()
    target_link_directories(RetroC PRIVATE ${RAYLIB_PATH}/lib)
    target_link_libraries(RetroC
            ${LUAJIT_LIB}
            raylib
            pthread
            m
            dl
            GL
            X11
            Xrandr
            Xi
    )
endif()

add_custom_command(
        TARGET RetroC POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_SOURCE_DIR}/resources"
        "${CMAKE_BINARY_DIR}/resources"
)

if (WIN32)
    add_custom_command(
            TARGET RetroC POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${LUAJIT_DLL}"
            "$<TARGET_FILE_DIR:RetroC>"
    )
endif()
