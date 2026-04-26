#ifndef APP_H
#define APP_H

#include "raylib.h"
#include "engine/RenderBuffer.h"
#include "engine/LuaEngine.h"

typedef struct {
    int width;
    int height;
    Framebuffer fb;
    lua_State *L;
} AppEngine;

void App_Init(AppEngine* app, const char* title, int width, int height);
void App_Update(AppEngine* app);
void App_Render(AppEngine* app);
void App_Shutdown(AppEngine* app);

#endif