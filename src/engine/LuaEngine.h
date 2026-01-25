#ifndef LUA_ENGINE_H
#define LUA_ENGINE_H

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

lua_State* LuaEngine_Create();
void LuaEngine_Destroy(lua_State *L);
void LuaEngine_Update(lua_State *L);
void LuaEngine_RunStartup(lua_State *L, const char *resource_root);

#endif
