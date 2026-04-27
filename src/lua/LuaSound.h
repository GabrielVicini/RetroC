#ifndef LuaSound_h
#define LuaSound_h

#include "lua.h"

void Sound_Init(void);
void Sound_Shutdown(void);
void Sound_Register(lua_State *L);

#endif