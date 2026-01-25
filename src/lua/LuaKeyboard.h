#ifndef Keyboard_H
#define Keyboard_H

#include "lua.h"
#include "lauxlib.h"
#include "engine/RenderBuffer.h"

void Keyboard_Init(Framebuffer *fb);
void Keyboard_Register(lua_State *L);

#endif