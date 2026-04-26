#ifndef TINHEAD_LUANETWORKING_H
#define TINHEAD_LUANETWORKING_H

#include "lua.h"

void Networking_Init(void);
void Networking_Shutdown(void);

void Networking_Register(lua_State *L);

#endif