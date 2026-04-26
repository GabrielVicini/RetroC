#include "LuaKeyboard.h"
#include "lauxlib.h"
#include "raylib.h"
#include <ctype.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define INPUT_TEXT_MAX 512
#define INPUT_EVENT_MAX 128
#ifndef KEY_KB_MENU
#define KEY_KB_MENU 348
#endif
#define INPUT_KEY_MAX (KEY_KB_MENU + 1)

typedef enum {
    INPUT_EVENT_KEY_DOWN = 1,
    INPUT_EVENT_KEY_UP,
    INPUT_EVENT_TEXT,
    INPUT_EVENT_MOUSE_MOVE,
    INPUT_EVENT_MOUSE_BUTTON,
    INPUT_EVENT_MOUSE_WHEEL
} InputEventType;

typedef struct {
    InputEventType type;
    int key;
    int button;
    int pressed;
    float x;
    float y;
    float dx;
    float dy;
    float wheel;
    char text[5];
} InputEvent;

static unsigned char g_key_down[INPUT_KEY_MAX];
static unsigned char g_mouse_down[5];
static Vector2 g_mouse_pos;
static Vector2 g_mouse_delta;
static float g_mouse_wheel;
static int g_view_w;
static int g_view_h;

static char g_text[INPUT_TEXT_MAX];
static size_t g_text_len;

static InputEvent g_events[INPUT_EVENT_MAX];
static int g_event_count;

static float ClampFloat(float v, float lo, float hi) {
    return (v < lo) ? lo : ((v > hi) ? hi : v);
}

static int lua_input_lockMouse(lua_State *L) {
    DisableCursor();
    return 0;
}

static void Input_ReadMouse(Vector2 *pos_out, Vector2 *delta_out) {
    Vector2 raw_pos = GetMousePosition();
    Vector2 raw_delta = GetMouseDelta();

    if (pos_out) {
        pos_out->x = ClampFloat(raw_pos.x, 0.0f, (float)(g_view_w - 1));
        pos_out->y = ClampFloat(raw_pos.y, 0.0f, (float)(g_view_h - 1));
    }

    if (delta_out) {
        *delta_out = raw_delta;
    }
}

static void Input_PushEvent(InputEvent ev) {
    if (g_event_count < INPUT_EVENT_MAX) {
        g_events[g_event_count++] = ev;
    }
}

static int Utf8_Encode(unsigned int codepoint, char out[5]) {
    if (codepoint <= 0x7F) {
        out[0] = (char)codepoint;
        out[1] = '\0';
        return 1;
    }
    if (codepoint <= 0x7FF) {
        out[0] = (char)(0xC0 | (codepoint >> 6));
        out[1] = (char)(0x80 | (codepoint & 0x3F));
        out[2] = '\0';
        return 2;
    }
    if (codepoint <= 0xFFFF) {
        out[0] = (char)(0xE0 | (codepoint >> 12));
        out[1] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
        out[2] = (char)(0x80 | (codepoint & 0x3F));
        out[3] = '\0';
        return 3;
    }
    if (codepoint <= 0x10FFFF) {
        out[0] = (char)(0xF0 | (codepoint >> 18));
        out[1] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
        out[2] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
        out[3] = (char)(0x80 | (codepoint & 0x3F));
        out[4] = '\0';
        return 4;
    }
    out[0] = '\0';
    return 0;
}

static void ToUpperCopy(char *out, size_t out_size, const char *in) {
    if (!out || out_size == 0) return;
    if (!in) { out[0] = '\0'; return; }
    size_t i = 0;
    while (in[i] && i + 1 < out_size) {
        out[i] = (char)toupper((unsigned char)in[i]);
        i++;
    }
    out[i] = '\0';
}

static int KeyFromString(const char *name) {
    if (!name || name[0] == '\0') return -1;

    if (name[1] == '\0') {
        char ch = (char)toupper((unsigned char)name[0]);
        if (ch >= 'A' && ch <= 'Z') return KEY_A + (ch - 'A');
        if (ch >= '0' && ch <= '9') return KEY_ZERO + (ch - '0');
        return -1;
    }

    char buf[32];
    ToUpperCopy(buf, sizeof(buf), name);

    if (strcmp(buf, "SPACE") == 0) return KEY_SPACE;
    if (strcmp(buf, "ENTER") == 0) return KEY_ENTER;
    if (strcmp(buf, "ESC") == 0 || strcmp(buf, "ESCAPE") == 0) return KEY_ESCAPE;
    if (strcmp(buf, "TAB") == 0) return KEY_TAB;
    if (strcmp(buf, "BACKSPACE") == 0) return KEY_BACKSPACE;
    if (strcmp(buf, "LEFT") == 0) return KEY_LEFT;
    if (strcmp(buf, "RIGHT") == 0) return KEY_RIGHT;
    if (strcmp(buf, "UP") == 0) return KEY_UP;
    if (strcmp(buf, "DOWN") == 0) return KEY_DOWN;
    if (strcmp(buf, "SHIFT") == 0 || strcmp(buf, "LSHIFT") == 0) return KEY_LEFT_SHIFT;
    if (strcmp(buf, "RSHIFT") == 0) return KEY_RIGHT_SHIFT;
    if (strcmp(buf, "CTRL") == 0 || strcmp(buf, "LCTRL") == 0) return KEY_LEFT_CONTROL;
    if (strcmp(buf, "RCTRL") == 0) return KEY_RIGHT_CONTROL;
    if (strcmp(buf, "ALT") == 0 || strcmp(buf, "LALT") == 0) return KEY_LEFT_ALT;
    if (strcmp(buf, "RALT") == 0) return KEY_RIGHT_ALT;
    if (strcmp(buf, "DEL") == 0 || strcmp(buf, "DELETE") == 0) return KEY_DELETE;
    if (strcmp(buf, "INS") == 0 || strcmp(buf, "INSERT") == 0) return KEY_INSERT;
    if (strcmp(buf, "HOME") == 0) return KEY_HOME;
    if (strcmp(buf, "END") == 0) return KEY_END;
    if (strcmp(buf, "PGUP") == 0 || strcmp(buf, "PAGEUP") == 0) return KEY_PAGE_UP;
    if (strcmp(buf, "PGDN") == 0 || strcmp(buf, "PAGEDOWN") == 0) return KEY_PAGE_DOWN;

    if (buf[0] == 'F') {
        char *end;
        long num = strtol(buf + 1, &end, 10);
        if (*end == '\0' && num >= 1 && num <= 12) return KEY_F1 + (int)(num - 1);
    }

    return -1;
}

static int MouseButtonFromString(const char *name) {
    if (!name) return -1;
    char buf[16];
    ToUpperCopy(buf, sizeof(buf), name);
    if (strcmp(buf, "LEFT") == 0) return MOUSE_BUTTON_LEFT;
    if (strcmp(buf, "RIGHT") == 0) return MOUSE_BUTTON_RIGHT;
    if (strcmp(buf, "MIDDLE") == 0) return MOUSE_BUTTON_MIDDLE;
    if (strcmp(buf, "SIDE") == 0 || strcmp(buf, "BACK") == 0) return MOUSE_BUTTON_SIDE;
    if (strcmp(buf, "EXTRA") == 0 || strcmp(buf, "FORWARD") == 0) return MOUSE_BUTTON_EXTRA;
    return -1;
}

static int Lua_CheckKey(lua_State *L, int index) {
    if (lua_type(L, index) == LUA_TNUMBER) return (int)lua_tointeger(L, index);
    if (lua_type(L, index) == LUA_TSTRING) {
        const char *name = lua_tostring(L, index);
        int key = KeyFromString(name);
        if (key >= 0) return key;
    }
    return -1;
}

static int Lua_CheckMouseButton(lua_State *L, int index) {
    if (lua_type(L, index) == LUA_TNUMBER) return (int)lua_tointeger(L, index);
    if (lua_type(L, index) == LUA_TSTRING) {
        const char *name = lua_tostring(L, index);
        int button = MouseButtonFromString(name);
        if (button >= 0) return button;
    }
    return -1;
}

void Keyboard_Init(void) {
    memset(g_key_down, 0, sizeof(g_key_down));
    memset(g_mouse_down, 0, sizeof(g_mouse_down));
    Input_ReadMouse(&g_mouse_pos, NULL);
    g_mouse_delta = (Vector2){0, 0};
    g_mouse_wheel = 0.0f;
    g_event_count = 0;
    g_text_len = 0;
    g_text[0] = '\0';
}

void Keyboard_SetViewport(int width, int height) {
    g_view_w = width > 0 ? width : 0;
    g_view_h = height > 0 ? height : 0;
}

void Keyboard_Update(void) {
    g_event_count = 0;
    g_text_len = 0;
    g_text[0] = '\0';
    g_mouse_delta = (Vector2){0, 0};
    g_mouse_wheel = 0.0f;

    Vector2 frame_delta = {0, 0};
    float frame_wheel = GetMouseWheelMove();

    Input_ReadMouse(&g_mouse_pos, &frame_delta);
    g_mouse_delta.x = frame_delta.x;
    g_mouse_delta.y = frame_delta.y;
    g_mouse_wheel = frame_wheel;

    if (frame_delta.x != 0.0f || frame_delta.y != 0.0f) {
        InputEvent ev = { .type = INPUT_EVENT_MOUSE_MOVE, .x = g_mouse_pos.x, .y = g_mouse_pos.y, .dx = frame_delta.x, .dy = frame_delta.y };
        Input_PushEvent(ev);
    }

    if (frame_wheel != 0.0f) {
        InputEvent ev = { .type = INPUT_EVENT_MOUSE_WHEEL, .wheel = frame_wheel };
        Input_PushEvent(ev);
    }

    const int mouse_buttons[5] = { MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_SIDE, MOUSE_BUTTON_EXTRA };
    for (int i = 0; i < 5; i++) {
        int button = mouse_buttons[i];
        int down = IsMouseButtonDown(button) ? 1 : 0;
        if (down != g_mouse_down[i]) {
            InputEvent ev = { .type = INPUT_EVENT_MOUSE_BUTTON, .button = button, .pressed = down, .x = g_mouse_pos.x, .y = g_mouse_pos.y };
            Input_PushEvent(ev);
            g_mouse_down[i] = (unsigned char)down;
        }
    }

    for (int key = 0; key < INPUT_KEY_MAX; key++) {
        int down = IsKeyDown(key) ? 1 : 0;
        if (down && !g_key_down[key]) {
            InputEvent ev = { .type = INPUT_EVENT_KEY_DOWN, .key = key };
            Input_PushEvent(ev);
        } else if (!down && g_key_down[key]) {
            InputEvent ev = { .type = INPUT_EVENT_KEY_UP, .key = key };
            Input_PushEvent(ev);
        }
        g_key_down[key] = (unsigned char)down;
    }

    int codepoint;
    while ((codepoint = GetCharPressed()) > 0) {
        char utf8[5];
        int len = Utf8_Encode((unsigned int)codepoint, utf8);
        if (len > 0) {
            if (g_text_len + (size_t)len < INPUT_TEXT_MAX - 1) {
                memcpy(g_text + g_text_len, utf8, (size_t)len);
                g_text_len += (size_t)len;
                g_text[g_text_len] = '\0';
            }
            InputEvent ev = { .type = INPUT_EVENT_TEXT };
            memcpy(ev.text, utf8, (size_t)len + 1);
            Input_PushEvent(ev);
        }
    }
}

static int lua_input_keyDown(lua_State *L) {
    int key = Lua_CheckKey(L, 1);
    lua_pushboolean(L, key >= 0 ? IsKeyDown(key) : 0);
    return 1;
}

static int lua_input_keyPressed(lua_State *L) {
    int key = Lua_CheckKey(L, 1);
    lua_pushboolean(L, key >= 0 ? IsKeyPressed(key) : 0);
    return 1;
}

static int lua_input_keyReleased(lua_State *L) {
    int key = Lua_CheckKey(L, 1);
    lua_pushboolean(L, key >= 0 ? IsKeyReleased(key) : 0);
    return 1;
}

static int lua_input_mousePos(lua_State *L) {
    lua_pushnumber(L, g_mouse_pos.x);
    lua_pushnumber(L, g_mouse_pos.y);
    return 2;
}

static int lua_input_mouseDelta(lua_State *L) {
    lua_pushnumber(L, g_mouse_delta.x);
    lua_pushnumber(L, g_mouse_delta.y);
    return 2;
}

static int lua_input_mouseDown(lua_State *L) {
    int button = Lua_CheckMouseButton(L, 1);
    lua_pushboolean(L, button >= 0 ? IsMouseButtonDown(button) : 0);
    return 1;
}

static int lua_input_mousePressed(lua_State *L) {
    int button = Lua_CheckMouseButton(L, 1);
    lua_pushboolean(L, button >= 0 ? IsMouseButtonPressed(button) : 0);
    return 1;
}

static int lua_input_mouseReleased(lua_State *L) {
    int button = Lua_CheckMouseButton(L, 1);
    lua_pushboolean(L, button >= 0 ? IsMouseButtonReleased(button) : 0);
    return 1;
}

static int lua_input_mouseWheel(lua_State *L) {
    lua_pushnumber(L, g_mouse_wheel);
    return 1;
}

static int lua_input_readText(lua_State *L) {
    lua_pushstring(L, g_text);
    g_text_len = 0;
    g_text[0] = '\0';
    return 1;
}

static void Lua_PushEventTable(lua_State *L, const InputEvent *ev) {
    switch (ev->type) {
        case INPUT_EVENT_KEY_DOWN:
            lua_createtable(L, 0, 2);
            lua_pushstring(L, "key_down"); lua_setfield(L, -2, "type");
            lua_pushinteger(L, ev->key); lua_setfield(L, -2, "key");
            break;
        case INPUT_EVENT_KEY_UP:
            lua_createtable(L, 0, 2);
            lua_pushstring(L, "key_up"); lua_setfield(L, -2, "type");
            lua_pushinteger(L, ev->key); lua_setfield(L, -2, "key");
            break;
        case INPUT_EVENT_TEXT:
            lua_createtable(L, 0, 2);
            lua_pushstring(L, "text"); lua_setfield(L, -2, "type");
            lua_pushstring(L, ev->text); lua_setfield(L, -2, "text");
            break;
        case INPUT_EVENT_MOUSE_MOVE:
            lua_createtable(L, 0, 5);
            lua_pushstring(L, "mouse_move"); lua_setfield(L, -2, "type");
            lua_pushnumber(L, ev->x); lua_setfield(L, -2, "x");
            lua_pushnumber(L, ev->y); lua_setfield(L, -2, "y");
            lua_pushnumber(L, ev->dx); lua_setfield(L, -2, "dx");
            lua_pushnumber(L, ev->dy); lua_setfield(L, -2, "dy");
            break;
        case INPUT_EVENT_MOUSE_BUTTON:
            lua_createtable(L, 0, 5);
            lua_pushstring(L, "mouse_button"); lua_setfield(L, -2, "type");
            lua_pushinteger(L, ev->button); lua_setfield(L, -2, "button");
            lua_pushboolean(L, ev->pressed); lua_setfield(L, -2, "pressed");
            lua_pushnumber(L, ev->x); lua_setfield(L, -2, "x");
            lua_pushnumber(L, ev->y); lua_setfield(L, -2, "y");
            break;
        case INPUT_EVENT_MOUSE_WHEEL:
            lua_createtable(L, 0, 2);
            lua_pushstring(L, "mouse_wheel"); lua_setfield(L, -2, "type");
            lua_pushnumber(L, ev->wheel); lua_setfield(L, -2, "wheel");
            break;
        default:
            lua_createtable(L, 0, 1);
            lua_pushstring(L, "unknown"); lua_setfield(L, -2, "type");
            break;
    }
}

static int lua_input_poll(lua_State *L) {
    lua_createtable(L, g_event_count, 0);
    for (int i = 0; i < g_event_count; i++) {
        Lua_PushEventTable(L, &g_events[i]);
        lua_rawseti(L, -2, i + 1);
    }
    return 1;
}

void Keyboard_Register(lua_State *L) {
    lua_newtable(L);
    lua_pushcfunction(L, lua_input_keyDown); lua_setfield(L, -2, "keyDown");
    lua_pushcfunction(L, lua_input_keyPressed); lua_setfield(L, -2, "keyPressed");
    lua_pushcfunction(L, lua_input_keyReleased); lua_setfield(L, -2, "keyReleased");
    lua_pushcfunction(L, lua_input_mousePos); lua_setfield(L, -2, "mousePos");
    lua_pushcfunction(L, lua_input_mouseDelta); lua_setfield(L, -2, "mouseDelta");
    lua_pushcfunction(L, lua_input_mouseDown); lua_setfield(L, -2, "mouseDown");
    lua_pushcfunction(L, lua_input_mousePressed); lua_setfield(L, -2, "mousePressed");
    lua_pushcfunction(L, lua_input_mouseReleased); lua_setfield(L, -2, "mouseReleased");
    lua_pushcfunction(L, lua_input_mouseWheel); lua_setfield(L, -2, "mouseWheel");
    lua_pushcfunction(L, lua_input_lockMouse); lua_setfield(L, -2, "lockMouse");
    lua_pushcfunction(L, lua_input_readText); lua_setfield(L, -2, "readText");
    lua_pushcfunction(L, lua_input_poll); lua_setfield(L, -2, "poll");
    lua_setglobal(L, "input");
}