#include "LuaKeyboard.h"
#include "lauxlib.h"
#include "raylib.h"
#include <ctype.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define INPUT_TEXT_MAX 512
#define INPUT_EVENT_MAX 128
#define INPUT_KEY_MAX 512

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
static unsigned char g_mouse_down[3];
static Vector2 g_mouse_pos;
static Vector2 g_mouse_delta;
static float g_mouse_wheel;

static char g_text[INPUT_TEXT_MAX];
static size_t g_text_len;

static InputEvent g_events[INPUT_EVENT_MAX];
static int g_event_count;

static void Input_ClearEvents(void) {
    g_event_count = 0;
}

static void Input_ClearText(void) {
    g_text_len = 0;
    g_text[0] = '\0';
}

static void Input_PushEvent(InputEvent ev) {
    if (g_event_count >= INPUT_EVENT_MAX) {
        return;
    }

    g_events[g_event_count++] = ev;
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
    size_t i = 0;

    if (!out || out_size == 0) {
        return;
    }

    if (!in) {
        out[0] = '\0';
        return;
    }

    while (in[i] && i + 1 < out_size) {
        out[i] = (char)toupper((unsigned char)in[i]);
        i++;
    }
    out[i] = '\0';
}

static int KeyFromString(const char *name) {
    char buf[32];
    size_t len;

    if (!name) {
        return -1;
    }

    ToUpperCopy(buf, sizeof(buf), name);
    len = strlen(buf);

    if (len == 1) {
        char ch = buf[0];
        if (ch >= 'A' && ch <= 'Z') {
            return KEY_A + (ch - 'A');
        }
        if (ch >= '0' && ch <= '9') {
            return KEY_ZERO + (ch - '0');
        }
    }

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

    if (buf[0] == 'F' && len <= 3) {
        char *end = NULL;
        long num = strtol(buf + 1, &end, 10);
        if (end && *end == '\0' && num >= 1 && num <= 12) {
            return KEY_F1 + (int)(num - 1);
        }
    }

    return -1;
}

static int MouseButtonFromString(const char *name) {
    char buf[16];

    if (!name) {
        return -1;
    }

    ToUpperCopy(buf, sizeof(buf), name);

    if (strcmp(buf, "LEFT") == 0) return MOUSE_BUTTON_LEFT;
    if (strcmp(buf, "RIGHT") == 0) return MOUSE_BUTTON_RIGHT;
    if (strcmp(buf, "MIDDLE") == 0) return MOUSE_BUTTON_MIDDLE;

    return -1;
}

static int Lua_CheckKey(lua_State *L, int index) {
    if (lua_isnumber(L, index)) {
        return (int)luaL_checkinteger(L, index);
    }

    if (lua_isstring(L, index)) {
        const char *name = luaL_checkstring(L, index);
        int key = KeyFromString(name);
        if (key >= 0) {
            return key;
        }
        return luaL_error(L, "Unknown key: %s", name);
    }

    return luaL_error(L, "Key must be number or string");
}

static int Lua_CheckMouseButton(lua_State *L, int index) {
    if (lua_isnumber(L, index)) {
        return (int)luaL_checkinteger(L, index);
    }

    if (lua_isstring(L, index)) {
        const char *name = luaL_checkstring(L, index);
        int button = MouseButtonFromString(name);
        if (button >= 0) {
            return button;
        }
        return luaL_error(L, "Unknown mouse button: %s", name);
    }

    return luaL_error(L, "Mouse button must be number or string");
}

void Keyboard_Init(void) {
    memset(g_key_down, 0, sizeof(g_key_down));
    memset(g_mouse_down, 0, sizeof(g_mouse_down));
    g_mouse_pos = GetMousePosition();
    g_mouse_delta = (Vector2){0, 0};
    g_mouse_wheel = 0.0f;
    Input_ClearEvents();
    Input_ClearText();

    for (int key = 0; key < INPUT_KEY_MAX; key++) {
        g_key_down[key] = IsKeyDown(key) ? 1 : 0;
    }

    g_mouse_down[0] = IsMouseButtonDown(MOUSE_BUTTON_LEFT) ? 1 : 0;
    g_mouse_down[1] = IsMouseButtonDown(MOUSE_BUTTON_RIGHT) ? 1 : 0;
    g_mouse_down[2] = IsMouseButtonDown(MOUSE_BUTTON_MIDDLE) ? 1 : 0;
}

void Keyboard_Update(void) {
    g_mouse_pos = GetMousePosition();
    {
        Vector2 delta = GetMouseDelta();
        g_mouse_delta.x += delta.x;
        g_mouse_delta.y += delta.y;
    }
    g_mouse_wheel += GetMouseWheelMove();

    if (g_mouse_delta.x != 0.0f || g_mouse_delta.y != 0.0f) {
        InputEvent ev = {0};
        ev.type = INPUT_EVENT_MOUSE_MOVE;
        ev.x = g_mouse_pos.x;
        ev.y = g_mouse_pos.y;
        ev.dx = g_mouse_delta.x;
        ev.dy = g_mouse_delta.y;
        Input_PushEvent(ev);
    }

    if (g_mouse_wheel != 0.0f) {
        InputEvent ev = {0};
        ev.type = INPUT_EVENT_MOUSE_WHEEL;
        ev.wheel = g_mouse_wheel;
        Input_PushEvent(ev);
    }

    const int mouse_buttons[3] = { MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE };
    for (int i = 0; i < 3; i++) {
        int button = mouse_buttons[i];
        int down = IsMouseButtonDown(button) ? 1 : 0;
        if (down != g_mouse_down[i]) {
            InputEvent ev = {0};
            ev.type = INPUT_EVENT_MOUSE_BUTTON;
            ev.button = button;
            ev.pressed = down;
            ev.x = g_mouse_pos.x;
            ev.y = g_mouse_pos.y;
            Input_PushEvent(ev);
            g_mouse_down[i] = (unsigned char)down;
        }
    }

    for (int key = 0; key < INPUT_KEY_MAX; key++) {
        int down = IsKeyDown(key) ? 1 : 0;
        if (down && !g_key_down[key]) {
            InputEvent ev = {0};
            ev.type = INPUT_EVENT_KEY_DOWN;
            ev.key = key;
            Input_PushEvent(ev);
        } else if (!down && g_key_down[key]) {
            InputEvent ev = {0};
            ev.type = INPUT_EVENT_KEY_UP;
            ev.key = key;
            Input_PushEvent(ev);
        }
        g_key_down[key] = (unsigned char)down;
    }

    for (int codepoint = GetCharPressed(); codepoint > 0; codepoint = GetCharPressed()) {
        char utf8[5];
        int len = Utf8_Encode((unsigned int)codepoint, utf8);
        if (len > 0) {
            if (g_text_len + (size_t)len + 1 < INPUT_TEXT_MAX) {
                memcpy(g_text + g_text_len, utf8, (size_t)len);
                g_text_len += (size_t)len;
                g_text[g_text_len] = '\0';
            }

            InputEvent ev = {0};
            ev.type = INPUT_EVENT_TEXT;
            memcpy(ev.text, utf8, (size_t)len + 1);
            Input_PushEvent(ev);
        }
    }
}

static int lua_input_keyDown(lua_State *L) {
    int key = Lua_CheckKey(L, 1);
    lua_pushboolean(L, IsKeyDown(key));
    return 1;
}

static int lua_input_keyPressed(lua_State *L) {
    int key = Lua_CheckKey(L, 1);
    lua_pushboolean(L, IsKeyPressed(key));
    return 1;
}

static int lua_input_keyReleased(lua_State *L) {
    int key = Lua_CheckKey(L, 1);
    lua_pushboolean(L, IsKeyReleased(key));
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
    g_mouse_delta = (Vector2){0, 0};
    return 2;
}

static int lua_input_mouseDown(lua_State *L) {
    int button = Lua_CheckMouseButton(L, 1);
    lua_pushboolean(L, IsMouseButtonDown(button));
    return 1;
}

static int lua_input_mousePressed(lua_State *L) {
    int button = Lua_CheckMouseButton(L, 1);
    lua_pushboolean(L, IsMouseButtonPressed(button));
    return 1;
}

static int lua_input_mouseReleased(lua_State *L) {
    int button = Lua_CheckMouseButton(L, 1);
    lua_pushboolean(L, IsMouseButtonReleased(button));
    return 1;
}

static int lua_input_mouseWheel(lua_State *L) {
    lua_pushnumber(L, g_mouse_wheel);
    g_mouse_wheel = 0.0f;
    return 1;
}

static int lua_input_readText(lua_State *L) {
    lua_pushstring(L, g_text);
    Input_ClearText();
    return 1;
}

static void Lua_PushEventTable(lua_State *L, const InputEvent *ev) {
    lua_newtable(L);

    switch (ev->type) {
        case INPUT_EVENT_KEY_DOWN:
            lua_pushstring(L, "key_down");
            lua_setfield(L, -2, "type");
            lua_pushinteger(L, ev->key);
            lua_setfield(L, -2, "key");
            break;
        case INPUT_EVENT_KEY_UP:
            lua_pushstring(L, "key_up");
            lua_setfield(L, -2, "type");
            lua_pushinteger(L, ev->key);
            lua_setfield(L, -2, "key");
            break;
        case INPUT_EVENT_TEXT:
            lua_pushstring(L, "text");
            lua_setfield(L, -2, "type");
            lua_pushstring(L, ev->text);
            lua_setfield(L, -2, "text");
            break;
        case INPUT_EVENT_MOUSE_MOVE:
            lua_pushstring(L, "mouse_move");
            lua_setfield(L, -2, "type");
            lua_pushnumber(L, ev->x);
            lua_setfield(L, -2, "x");
            lua_pushnumber(L, ev->y);
            lua_setfield(L, -2, "y");
            lua_pushnumber(L, ev->dx);
            lua_setfield(L, -2, "dx");
            lua_pushnumber(L, ev->dy);
            lua_setfield(L, -2, "dy");
            break;
        case INPUT_EVENT_MOUSE_BUTTON:
            lua_pushstring(L, "mouse_button");
            lua_setfield(L, -2, "type");
            lua_pushinteger(L, ev->button);
            lua_setfield(L, -2, "button");
            lua_pushboolean(L, ev->pressed);
            lua_setfield(L, -2, "pressed");
            lua_pushnumber(L, ev->x);
            lua_setfield(L, -2, "x");
            lua_pushnumber(L, ev->y);
            lua_setfield(L, -2, "y");
            break;
        case INPUT_EVENT_MOUSE_WHEEL:
            lua_pushstring(L, "mouse_wheel");
            lua_setfield(L, -2, "type");
            lua_pushnumber(L, ev->wheel);
            lua_setfield(L, -2, "wheel");
            break;
        default:
            lua_pushstring(L, "unknown");
            lua_setfield(L, -2, "type");
            break;
    }
}

static int lua_input_poll(lua_State *L) {
    lua_newtable(L);
    for (int i = 0; i < g_event_count; i++) {
        Lua_PushEventTable(L, &g_events[i]);
        lua_rawseti(L, -2, i + 1);
    }
    Input_ClearEvents();
    return 1;
}

void Keyboard_Register(lua_State *L) {
    lua_newtable(L);

    lua_pushcfunction(L, lua_input_keyDown);
    lua_setfield(L, -2, "keyDown");

    lua_pushcfunction(L, lua_input_keyPressed);
    lua_setfield(L, -2, "keyPressed");

    lua_pushcfunction(L, lua_input_keyReleased);
    lua_setfield(L, -2, "keyReleased");

    lua_pushcfunction(L, lua_input_mousePos);
    lua_setfield(L, -2, "mousePos");

    lua_pushcfunction(L, lua_input_mouseDelta);
    lua_setfield(L, -2, "mouseDelta");

    lua_pushcfunction(L, lua_input_mouseDown);
    lua_setfield(L, -2, "mouseDown");

    lua_pushcfunction(L, lua_input_mousePressed);
    lua_setfield(L, -2, "mousePressed");

    lua_pushcfunction(L, lua_input_mouseReleased);
    lua_setfield(L, -2, "mouseReleased");

    lua_pushcfunction(L, lua_input_mouseWheel);
    lua_setfield(L, -2, "mouseWheel");

    lua_pushcfunction(L, lua_input_readText);
    lua_setfield(L, -2, "readText");

    lua_pushcfunction(L, lua_input_poll);
    lua_setfield(L, -2, "poll");

    lua_setglobal(L, "input");
}
