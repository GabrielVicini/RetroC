#include "raylib.h"
#include "engine/RenderBuffer.h"
#include "engine/LuaEngine.h"
#include "lua/LuaGraphics.h"
#include "lua/LuaSystem.h"
#include "lua/LuaKeyboard.h"
#include <stdio.h>

static void BuildResourcePath(char *out, size_t out_size, const char *relative) {
    const char *cwd = GetWorkingDirectory();

    if (!out || out_size == 0) {
        return;
    }

    if (!relative) {
        out[0] = '\0';
        return;
    }

    if (!cwd || !*cwd) {
        snprintf(out, out_size, "%s", relative);
        return;
    }

    snprintf(out, out_size, "%s/%s", cwd, relative);
}

int main(void)
{
    SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT);
    InitWindow(620, 360, "Emulator");

    char resourceRoot[1024];
    BuildResourcePath(resourceRoot, sizeof(resourceRoot), "resources");

    char iconPath[1024];
    BuildResourcePath(iconPath, sizeof(iconPath), "resources/assets/icon.png");
    if (FileExists(iconPath)) {
        Image icon = LoadImage(iconPath);
        if (icon.data) {
            SetWindowIcon(icon);
            UnloadImage(icon);
        } else {
            TraceLog(LOG_WARNING, "Failed to load icon: %s", iconPath);
        }
    } else {
        TraceLog(LOG_WARNING, "Icon not found: %s", iconPath);
    }

    lua_State *L = LuaEngine_Create();

    const int fbWidth = 620;
    const int fbHeight = 360;
    Framebuffer fb = Framebuffer_Create(fbWidth, fbHeight);
    Framebuffer_Clear(&fb, BLACK);

    GraphicsInit(&fb);
    SystemInit(&fb);
    Keyboard_Init();

    LuaEngine_RunStartup(L, resourceRoot);

    SetTargetFPS(120);

    while (!WindowShouldClose()) {

        Keyboard_Update();
        LuaEngine_Update(L);

        BeginDrawing();
        ClearBackground(BLACK);

        Framebuffer_Render(&fb, GetScreenWidth(), GetScreenHeight());
        EndDrawing();
    }

    LuaEngine_Destroy(L);
    Framebuffer_Destroy(&fb);
    CloseWindow();
    return 0;
}
