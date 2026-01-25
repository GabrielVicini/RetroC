#ifndef LuaSystem_h
#define LuaSystem_h

#include "lua.h"
#include "engine/RenderBuffer.h"

void SystemInit(Framebuffer *fb);
void SystemRegister(lua_State *L);

#endif