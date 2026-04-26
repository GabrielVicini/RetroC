#include "lua/LuaSystem.h"
#include "engine/RenderBuffer.h"
#include "raylib.h"
#include "lauxlib.h"
#include <time.h>

void SystemInit(Framebuffer *fb) {
    (void)fb;
}

static int lua_sys_getPSTime(lua_State *L) {
    lua_pushnumber(L, GetTime());
    return 1;
}

static int lua_sys_wait(lua_State *L) {
    lua_pushnumber(L, GetTime() + lua_tonumber(L, 1));
    return lua_yield(L, 1);
}

static int lua_sys_unixTime(lua_State *L) {
    lua_pushinteger(L, (lua_Integer)time(NULL));
    return 1;
}

static int lua_sys_getFPS(lua_State *L) {
    lua_pushinteger(L, GetFPS());
    return 1;
}

static int lua_sys_getFrameTime(lua_State *L) {
    lua_pushnumber(L, GetFrameTime());
    return 1;
}

void SystemRegister(lua_State *L) {
    lua_newtable(L);

    lua_pushcfunction(L, lua_sys_getPSTime);
    lua_setfield(L, -2, "getPSTime");

    lua_pushcfunction(L, lua_sys_unixTime);
    lua_setfield(L, -2, "getUnixTime");

    lua_pushcfunction(L, lua_sys_wait);
    lua_setfield(L, -2, "wait");

    lua_pushcfunction(L, lua_sys_getFPS);
    lua_setfield(L, -2, "getFPS");

    lua_pushcfunction(L, lua_sys_getFrameTime);
    lua_setfield(L, -2, "getFrameTime");

    lua_setglobal(L, "sys");
}