#include "engine/RenderBuffer.h"
#include <stdio.h>
#include "raylib.h"

static Framebuffer *g_fb = NULL;

void Keyboard_Init(Framebuffer *fb) {
    g_fb = fb;
}

