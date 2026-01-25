#include "engine/RenderBuffer.h"
#include <stdio.h>
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
    int x = (int)luaL_optinteger(L, 1, 0);
    int y = (int)luaL_optinteger(L, 2, 0);

    if (!g_fb) {
        lua_pushinteger(L, 0); // r
        lua_pushinteger(L, 0); // g
        lua_pushinteger(L, 0); // b
        lua_pushinteger(L, 4); // error: no framebuffer
        return 4;
    }

    // out of bounds?
    if (x < 0 || x >= g_fb->width ||
        y < 0 || y >= g_fb->height)
    {
        lua_pushinteger(L, 0); // r
        lua_pushinteger(L, 0); // g
        lua_pushinteger(L, 0); // b
        lua_pushinteger(L, 2); // error: out of bounds
        return 4;
    }

    // success
    Color c = Framebuffer_GetPixel(g_fb, x, y);

    lua_pushinteger(L, (int)c.r);
    lua_pushinteger(L, (int)c.g);
    lua_pushinteger(L, (int)c.b);
    lua_pushinteger(L, 1); // success
    return 4;
}

static int lua_term_setPixel(lua_State *L) {
    int x = (int)luaL_optinteger(L, 1, 0);
    int y = (int)luaL_optinteger(L, 2, 0);
    int r = (int)luaL_optinteger(L, 3, 255);
    int g = (int)luaL_optinteger(L, 4, 255);
    int b = (int)luaL_optinteger(L, 5, 255);

    // no framebuffer? fail
    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    // out of range color?
    if (r < 0 || r > 255 ||
        g < 0 || g > 255 ||
        b < 0 || b > 255)
    {
        lua_pushinteger(L, 3);
        return 1;
    }

    // out of bounds pixel?
    if (x < 0 || x >= g_fb->width ||
        y < 0 || y >= g_fb->height)
    {
        lua_pushinteger(L, 2);
        return 1;
    }

    // success!
    Color c = { (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 };
    Framebuffer_SetPixel(g_fb, x, y, c);

    lua_pushinteger(L, 1);
    return 1;
}

static int lua_term_fillRect(lua_State *L) {
    int x = (int)luaL_optinteger(L, 1, 0);
    int y = (int)luaL_optinteger(L, 2, 0);
    int w = (int)luaL_optinteger(L, 3, 0);
    int h = (int)luaL_optinteger(L, 4, 0);
    int r = (int)luaL_optinteger(L, 5, 0);
    int g = (int)luaL_optinteger(L, 6, 0);
    int b = (int)luaL_optinteger(L, 7, 0);

    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    Color c = { (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 };
    Framebuffer_FillRect(g_fb, x, y, w, h, c);

    lua_pushinteger(L, 1);
    return 1;
}

static int lua_term_blit(lua_State *L) {
    int sx = (int)luaL_checkinteger(L, 1);
    int sy = (int)luaL_checkinteger(L, 2);
    int w  = (int)luaL_checkinteger(L, 3);
    int h  = (int)luaL_checkinteger(L, 4);
    int dx = (int)luaL_checkinteger(L, 5);
    int dy = (int)luaL_checkinteger(L, 6);

    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    Framebuffer_Blit(g_fb, sx, sy, w, h, dx, dy);

    lua_pushinteger(L, 1);
    return 1;
}

static int lua_term_drawLine(lua_State *L) {
    int x0 = (int)luaL_checkinteger(L, 1);
    int y0 = (int)luaL_checkinteger(L, 2);
    int x1 = (int)luaL_checkinteger(L, 3);
    int y1 = (int)luaL_checkinteger(L, 4);
    int r  = (int)luaL_optinteger(L, 5, 255);
    int g  = (int)luaL_optinteger(L, 6, 255);
    int b  = (int)luaL_optinteger(L, 7, 255);

    if (!g_fb) {
        lua_pushinteger(L, 4);
        return 1;
    }

    Color c = { (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 };
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
