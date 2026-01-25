#include "RenderBuffer.h"
#include "raylib.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

Framebuffer Framebuffer_Create(int w, int h) {
    Framebuffer fb;
    fb.width = w;
    fb.height = h;

    fb.pixels = malloc(w * h * sizeof(Color));

    for (int i = 0; i < w * h; i++)
        fb.pixels[i] = BLACK;

    Image img = GenImageColor(w, h, BLACK);
    fb.texture = LoadTextureFromImage(img);

    UnloadImage(img);

    return fb;
}

void Framebuffer_Destroy(Framebuffer *fb) {
    if (fb->pixels)
        free(fb->pixels);

    UnloadTexture(fb->texture);

    fb->pixels = NULL;
}

void Framebuffer_Resize(Framebuffer *fb, int newW, int newH) {
    UnloadTexture(fb->texture);
    free(fb->pixels);

    *fb = Framebuffer_Create(newW, newH);
}

void Framebuffer_Clear(Framebuffer *fb, Color c) {
    int total = fb->width * fb->height;
    for (int i = 0; i < total; i++)
        fb->pixels[i] = c;
}

void Framebuffer_FillRect(Framebuffer *fb, int x, int y, int w, int h, Color c) {
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > fb->width)  w = fb->width  - x;
    if (y + h > fb->height) h = fb->height - y;
    if (w <= 0 || h <= 0) return;

    for (int yy = y; yy < y + h; yy++) {
        Color *row = fb->pixels + yy * fb->width + x;
        for (int xx = 0; xx < w; xx++) {
            row[xx] = c;
        }
    }
}

void Framebuffer_Blit(Framebuffer *fb,
                      int sx, int sy, int w, int h,
                      int dx, int dy)
{
    if (w <= 0 || h <= 0) return;
    if (!fb || !fb->pixels) return;

    // basic clipping to framebuffer bounds

    // clip source rect
    if (sx < 0)          { w += sx; dx -= sx; sx = 0; }
    if (sy < 0)          { h += sy; dy -= sy; sy = 0; }
    if (sx + w > fb->width)  w = fb->width  - sx;
    if (sy + h > fb->height) h = fb->height - sy;

    // clip dest rect
    if (dx < 0)          { w += dx; sx -= dx; dx = 0; }
    if (dy < 0)          { h += dy; sy -= dy; dy = 0; }
    if (dx + w > fb->width)  w = fb->width  - dx;
    if (dy + h > fb->height) h = fb->height - dy;

    if (w <= 0 || h <= 0) return;

    int pitch = fb->width;

    // copy direction (handle overlap)
    int yStart, yEnd, yStep;
    if (dy > sy) {
        // moving down: copy bottom-up
        yStart = h - 1;
        yEnd   = -1;
        yStep  = -1;
    } else {
        // moving up or same: copy top-down
        yStart = 0;
        yEnd   = h;
        yStep  = 1;
    }

    for (int j = yStart; j != yEnd; j += yStep) {
        Color *srcRow = fb->pixels + (sy + j) * pitch + sx;
        Color *dstRow = fb->pixels + (dy + j) * pitch + dx;
        memmove(dstRow, srcRow, w * sizeof(Color));
    }
}

Color Framebuffer_GetPixel(Framebuffer *fb, int x, int y) {
    // safe default (black, opaque)
    Color c = { 0, 0, 0, 255 };

    if (!fb || !fb->pixels)
        return c;

    if (x < 0 || y < 0 || x >= fb->width || y >= fb->height)
        return c;

    return fb->pixels[y * fb->width + x];
}


void Framebuffer_DrawLine(Framebuffer *fb,
                          int x0, int y0,
                          int x1, int y1,
                          Color c)
{
    if (!fb || !fb->pixels) return;

    int dx = abs(x1 - x0);
    int sx = x0 < x1 ? 1 : -1;
    int dy = -abs(y1 - y0);
    int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;

    while (1) {
        Framebuffer_SetPixel(fb, x0, y0, c);

        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}



void Framebuffer_SetPixel(Framebuffer *fb, int x, int y, Color c) {
    if (x < 0 || y < 0 || x >= fb->width || y >= fb->height)
        return;

    fb->pixels[y * fb->width + x] = c;
}

void Framebuffer_Render(Framebuffer *fb, int screenW, int screenH) {
    UpdateTexture(fb->texture, fb->pixels);


    Rectangle src = {
        0, 0,
        (float)fb->width,
        (float)fb->height
    };


    Rectangle dest = {
        0, 0,
        (float)screenW,
        (float)screenH
    };

    Vector2 origin = {0, 0};

    DrawTexturePro(
        fb->texture,
        src,
        dest,
        origin,
        0.0f,
        WHITE
    );
}
