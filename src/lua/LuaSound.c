#include "LuaSound.h"
#include "lauxlib.h"
#include "raylib.h"
#include <stdlib.h>

void Sound_Init(void) {
    InitAudioDevice();
}

void Sound_Shutdown(void) {
    if (IsAudioDeviceReady()) {
        CloseAudioDevice();
    }
}

static int lua_snd_load(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);

    Sound *snd = (Sound*)lua_newuserdata(L, sizeof(Sound));
    *snd = LoadSound(path);
    
    if (snd->stream.buffer == NULL) {
        lua_pushnil(L);
        return 1;
    }
    return 1;
}

static int lua_snd_play(lua_State *L) {
    Sound *snd = (Sound*)lua_touserdata(L, 1);
    if (snd && snd->stream.buffer) PlaySound(*snd);
    return 0;
}

static int lua_snd_stop(lua_State *L) {
    Sound *snd = (Sound*)lua_touserdata(L, 1);
    if (snd && snd->stream.buffer) StopSound(*snd);
    return 0;
}

static int lua_snd_setVolume(lua_State *L) {
    Sound *snd = (Sound*)lua_touserdata(L, 1);
    float vol = (float)luaL_checknumber(L, 2);
    if (snd && snd->stream.buffer) SetSoundVolume(*snd, vol);
    return 0;
}

static int lua_snd_unload(lua_State *L) {
    Sound *snd = (Sound*)lua_touserdata(L, 1);
    if (snd && snd->stream.buffer != NULL) {
        UnloadSound(*snd);
        snd->stream.buffer = NULL;
    }
    return 0;
}

static int lua_mus_load(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    
    Music *mus = (Music*)lua_newuserdata(L, sizeof(Music));
    *mus = LoadMusicStream(path);
    
    if (mus->stream.buffer == NULL) {
        lua_pushnil(L);
        return 1;
    }
    return 1;
}

static int lua_mus_play(lua_State *L) {
    Music *mus = (Music*)lua_touserdata(L, 1);
    if (mus && mus->stream.buffer) PlayMusicStream(*mus);
    return 0;
}

static int lua_mus_update(lua_State *L) {
    Music *mus = (Music*)lua_touserdata(L, 1);
    if (mus && mus->stream.buffer) UpdateMusicStream(*mus);
    return 0;
}

static int lua_mus_stop(lua_State *L) {
    Music *mus = (Music*)lua_touserdata(L, 1);
    if (mus && mus->stream.buffer) StopMusicStream(*mus);
    return 0;
}

static int lua_mus_setVolume(lua_State *L) {
    Music *mus = (Music*)lua_touserdata(L, 1);
    float vol = (float)luaL_checknumber(L, 2);
    if (mus && mus->stream.buffer) SetMusicVolume(*mus, vol);
    return 0;
}

static int lua_mus_unload(lua_State *L) {
    Music *mus = (Music*)lua_touserdata(L, 1);
    if (mus && mus->stream.buffer != NULL) {
        UnloadMusicStream(*mus);
        mus->stream.buffer = NULL;
    }
    return 0;
}

void Sound_Register(lua_State *L) {
    lua_newtable(L);

    lua_pushcfunction(L, lua_snd_load); lua_setfield(L, -2, "load");
    lua_pushcfunction(L, lua_snd_play); lua_setfield(L, -2, "play");
    lua_pushcfunction(L, lua_snd_stop); lua_setfield(L, -2, "stop");
    lua_pushcfunction(L, lua_snd_setVolume); lua_setfield(L, -2, "setVolume");
    lua_pushcfunction(L, lua_snd_unload); lua_setfield(L, -2, "unload");

    lua_pushcfunction(L, lua_mus_load); lua_setfield(L, -2, "loadMusic");
    lua_pushcfunction(L, lua_mus_play); lua_setfield(L, -2, "playMusic");
    lua_pushcfunction(L, lua_mus_update); lua_setfield(L, -2, "updateMusic");
    lua_pushcfunction(L, lua_mus_stop); lua_setfield(L, -2, "stopMusic");
    lua_pushcfunction(L, lua_mus_setVolume); lua_setfield(L, -2, "setMusicVolume");
    lua_pushcfunction(L, lua_mus_unload); lua_setfield(L, -2, "unloadMusic");

    lua_setglobal(L, "sound");
}