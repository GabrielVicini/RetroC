#ifndef LuaGraphics_h
#define LuaGraphics_h

#include "lua.h"
#include "engine/RenderBuffer.h"

void GraphicsInit(Framebuffer *fb);
void GraphicsRegister(lua_State *L);

#endif