#include "engine/RenderBuffer.h"
#include "lauxlib.h"
#include "raylib.h"
#include "lua/LuaGraphics.h"

static Framebuffer *g_fb = NULL;

void GraphicsInit(Framebuffer *fb) {
    g_fb = fb;
}

static int lua_term_getSize(lua_State *L) {
    if (!g_fb) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        return 2;
    }
    lua_pushinteger(L, g_fb->width);
    lua_pushinteger(L, g_fb->height);
    return 2;
}

static int lua_term_getPixel(lua_State *L) {
    if (!g_fb) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 4);
        return 4;
    }

    int x = (int)lua_tointeger(L, 1);
    int y = (int)lua_tointeger(L, 2);

    if (x < 0 || x >= g_fb->width || y < 0 || y >= g_fb->height) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 2);
        return 4;
    }

    Color c = Framebuffer_GetPixel(g_fb, x, y);
    lua_pushinteger(L, (int)c.r);
    lua_pushinteger(L, (int)c.g);
    lua_pushinteger(L, (int)c.b);
    lua_pushinteger(L, 1);
    return 4;
}

static int lua_term_setPixel(lua_State *L) {
    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    int x = (int)lua_tointeger(L, 1);
    int y = (int)lua_tointeger(L, 2);

    Color c = {
        (unsigned char)lua_tointeger(L, 3),
        (unsigned char)lua_tointeger(L, 4),
        (unsigned char)lua_tointeger(L, 5),
        255
    };

    Framebuffer_SetPixel(g_fb, x, y, c);
    lua_pushinteger(L, 1);
    return 1;
}

static int lua_term_fillRect(lua_State *L) {
    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    int x = (int)lua_tointeger(L, 1);
    int y = (int)lua_tointeger(L, 2);
    int w = (int)lua_tointeger(L, 3);
    int h = (int)lua_tointeger(L, 4);

    Color c = {
        (unsigned char)lua_tointeger(L, 5),
        (unsigned char)lua_tointeger(L, 6),
        (unsigned char)lua_tointeger(L, 7),
        255
    };

    Framebuffer_FillRect(g_fb, x, y, w, h, c);
    lua_pushinteger(L, 1);
    return 1;
}

static int lua_term_blit(lua_State *L) {
    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    Framebuffer_Blit(
        g_fb,
        (int)lua_tointeger(L, 1), (int)lua_tointeger(L, 2),
        (int)lua_tointeger(L, 3), (int)lua_tointeger(L, 4),
        (int)lua_tointeger(L, 5), (int)lua_tointeger(L, 6)
    );

    lua_pushinteger(L, 1);
    return 1;
}

static int lua_term_drawLine(lua_State *L) {
    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    int x0 = (int)lua_tointeger(L, 1);
    int y0 = (int)lua_tointeger(L, 2);
    int x1 = (int)lua_tointeger(L, 3);
    int y1 = (int)lua_tointeger(L, 4);

    Color c = {
        (unsigned char)lua_tointeger(L, 5),
        (unsigned char)lua_tointeger(L, 6),
        (unsigned char)lua_tointeger(L, 7),
        255
    };

    Framebuffer_DrawLine(g_fb, x0, y0, x1, y1, c);
    lua_pushinteger(L, 1);
    return 1;
}

void GraphicsRegister(lua_State *L) {
    lua_newtable(L);

    lua_pushcfunction(L, lua_term_setPixel);
    lua_setfield(L, -2, "setPixel");

    lua_pushcfunction(L, lua_term_getSize);
    lua_setfield(L, -2, "getSize");

    lua_pushcfunction(L, lua_term_fillRect);
    lua_setfield(L, -2, "fillRect");

    lua_pushcfunction(L, lua_term_blit);
    lua_setfield(L, -2, "blit");

    lua_pushcfunction(L, lua_term_drawLine);
    lua_setfield(L, -2, "drawLine");

    lua_pushcfunction(L, lua_term_getPixel);
    lua_setfield(L, -2, "getPixel");

    lua_setglobal(L, "term");
}