#include "LuaEngine.h"
#include "../lua/LuaGraphics.h"
#include "../lua/LuaSystem.h"
#include "../lua/LuaKeyboard.h"
#include "raylib.h"
#include <stdio.h>

static lua_State* update_thread = NULL;
static double update_thread_wake = 0.0;

static void LuaEngine_AppendPackagePath(lua_State *L, const char *resource_root) {
    if (!resource_root || !*resource_root) return;

    lua_getglobal(L, "package");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return;
    }

    lua_getfield(L, -1, "path");
    const char *cur = lua_tostring(L, -1);

    lua_pop(L, 1);
    lua_pushfstring(L, "%s/rom/?.lua;%s/rom/?/init.lua;%s", resource_root, resource_root, cur ? cur : "");
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);
}

lua_State* LuaEngine_Create() {
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    GraphicsRegister(L);
    SystemRegister(L);
    Keyboard_Register(L);
    return L;
}

void LuaEngine_Destroy(lua_State *L) {
    lua_close(L);
}

void LuaEngine_RunStartup(lua_State *L, const char *resource_root) {
    const char *root = (resource_root && *resource_root) ? resource_root : "resources";
    lua_pushstring(L, root);
    lua_setglobal(L, "ENGINE_ROOT");
    char kernelPath[1024];
    snprintf(kernelPath, sizeof(kernelPath), "%s/rom/kernel.lua", root);

    LuaEngine_AppendPackagePath(L, root);

    if (!FileExists(kernelPath)) {
        // USE TRACELOG SO WE ACTUALLY SEE IT
        TraceLog(LOG_FATAL, "LUA ERROR: Kernel file not found at %s", kernelPath);
        return;
    }

    if (luaL_dofile(L, kernelPath) != LUA_OK) {
        // THIS WILL CATCH THE TYPO/PATH ERROR
        TraceLog(LOG_FATAL, "LUA COMPILE ERROR: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
        return;
    }

    update_thread = lua_newthread(L);
    lua_getglobal(update_thread, "main");

    if (!lua_isfunction(update_thread, -1)) {
        TraceLog(LOG_FATAL, "LUA ERROR: No main() function found in kernel.lua!");
        lua_pop(update_thread, 1);
        update_thread = NULL;
        return;
    }

    update_thread_wake = 0.0;
}

void LuaEngine_Update(lua_State *L) {
    (void)L;
    if (!update_thread) return;

    double now = GetTime();
    if (now < update_thread_wake) return;

    int status = lua_resume(update_thread, 0);

    if (status == LUA_YIELD) {
        if (lua_gettop(update_thread) > 0 && lua_isnumber(update_thread, -1)) {
            update_thread_wake = now + lua_tonumber(update_thread, -1);
        } else {
            update_thread_wake = 0.0;
        }
        lua_settop(update_thread, 0);
    } else {
        // IF LUA CRASHES DURING THE LOOP, PRINT IT
        if (status != 0) {
            TraceLog(LOG_FATAL, "LUA RUNTIME ERROR: %s", lua_tostring(update_thread, -1));
        }
        update_thread = NULL;
    }
}