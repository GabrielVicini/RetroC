#ifndef Keyboard_H
#define Keyboard_H

#include "lua.h"

void Keyboard_Init(void);
void Keyboard_Update(void);
void Keyboard_Register(lua_State *L);

#endif
