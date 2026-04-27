#include "engine/App.h"
#include "lua/LuaGraphics.h"
#include "lua/LuaSystem.h"
#include "lua/LuaKeyboard.h"
#include "lua/LuaNetworking.h"
#include <stdio.h>
#include <string.h>

#define MAX_PATH_SIZE 1024

static void BuildResourcePath(char *out, const char *relative) {
    const char *cwd = GetWorkingDirectory();
    if (!cwd || !*cwd) {
        snprintf(out, MAX_PATH_SIZE, "%s", relative);
    } else {
        snprintf(out, MAX_PATH_SIZE, "%s/%s", cwd, relative);
    }
}



void App_Init(AppEngine* app, const char* title, int width, int height) {
    app->width = width;
    app->height = height;

    SetConfigFlags(FLAG_WINDOW_RESIZABLE);
    InitWindow(width, height, title);
    SetExitKey(KEY_NULL); // Tells raylib to stop nuking the app on ESC


    char resourceRoot[MAX_PATH_SIZE];
    BuildResourcePath(resourceRoot, "resources");

    char iconPath[MAX_PATH_SIZE];
    BuildResourcePath(iconPath, "resources/assets/icon.png");

    Image icon = LoadImage(iconPath);
    if (icon.data) {
        SetWindowIcon(icon);
        UnloadImage(icon);
    }

    app->L = LuaEngine_Create();
    app->fb = Framebuffer_Create(width, height);
    Framebuffer_Clear(&app->fb, BLACK);

    GraphicsInit(&app->fb);
    SystemInit(&app->fb);

    Keyboard_SetViewport(width, height);
    Keyboard_Init();

    Networking_Init();

    LuaEngine_RunStartup(app->L, resourceRoot);

    SetTargetFPS(0);
}

void App_Update(AppEngine* app) {
    if (IsWindowResized()) {
        Keyboard_SetViewport(app->fb.width, app->fb.height);
    }

    Keyboard_Update();
    LuaEngine_Update(app->L);
}

void App_Render(AppEngine* app) {
    BeginDrawing();
    ClearBackground(BLACK);


    Framebuffer_Render(&app->fb, GetScreenWidth(), GetScreenHeight());

    EndDrawing();
}

void App_Shutdown(AppEngine* app) {
    LuaEngine_Destroy(app->L);
    Framebuffer_Destroy(&app->fb);
    Networking_Shutdown();
    CloseWindow();
}