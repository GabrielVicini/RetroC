#include "engine/RenderBuffer.h"
#include <stdio.h>
#include "raylib.h"
#include "lua/LuaSystem.h"
#include "lauxlib.h"

#include <time.h>

static Framebuffer *g_fb = NULL;

void SystemInit(Framebuffer *fb) {
    g_fb = fb;
}

static int lua_sys_getPSTime(lua_State *L) {
    lua_pushnumber(L, GetTime()); // seconds as double
    return 1;
}

static int lua_sys_wait(lua_State *L) {
    double seconds = luaL_checknumber(L, 1);
    double wakeTime = GetTime() + seconds;

    lua_pushnumber(L, wakeTime);
    return lua_yield(L, 1);
}

static int lua_sys_unixTime(lua_State *L) {
    time_t t = time(NULL);
    lua_pushinteger(L, (lua_Integer)t);
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

    lua_setglobal(L, "sys");
}
