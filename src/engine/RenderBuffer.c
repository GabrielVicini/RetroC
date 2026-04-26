#include "RenderBuffer.h"
#include "raylib.h"
#include <string.h>
#include <stdlib.h>

#define INSIDE 0
#define LEFT 1
#define RIGHT 2
#define BOTTOM 4
#define TOP 8

static int ComputeOutCode(int x, int y, int w, int h) {
    int code = INSIDE;
    if (x < 0) code |= LEFT;
    else if (x >= w) code |= RIGHT;
    if (y < 0) code |= TOP;
    else if (y >= h) code |= BOTTOM;
    return code;
}

Framebuffer Framebuffer_Create(int w, int h) {
    Framebuffer fb = {0};
    if (w <= 0 || h <= 0) return fb;

    fb.width = w;
    fb.height = h;
    size_t total = (size_t)w * (size_t)h;
    fb.capacity = total;
    fb.pixels = malloc(total * sizeof(Color));

    if (!fb.pixels) {
        fb.width = 0;
        fb.height = 0;
        fb.capacity = 0;
        return fb;
    }

    union { Color c; uint32_t i; } pun = { .c = BLACK };
    uint32_t cv = pun.i;
    uint32_t *p = (uint32_t*)fb.pixels;
    for (size_t i = 0; i < total; i++) {
        p[i] = cv;
    }

    Image img = GenImageColor(w, h, BLACK);
    fb.texture = LoadTextureFromImage(img);
    UnloadImage(img);

    if (fb.texture.id == 0) {
        free(fb.pixels);
        fb.pixels = NULL;
        fb.width = 0;
        fb.height = 0;
        fb.capacity = 0;
    }

    // FORCE CRISP PIXELS: No blurry bilinear filtering when we scale up
    SetTextureFilter(fb.texture, TEXTURE_FILTER_POINT);

    fb.isDirty = true;
    return fb;
}

void Framebuffer_Render(Framebuffer *fb, int screenW, int screenH) {
    if (!fb || !fb->pixels || fb->texture.id == 0) return;

    if (fb->isDirty) {
        Rectangle rec = { 0, 0, (float)fb->width, (float)fb->height };
        UpdateTextureRec(fb->texture, rec, fb->pixels);
        fb->isDirty = false;
    }

    float scale = (float)screenW / fb->width;
    if ((float)screenH / fb->height < scale) {
        scale = (float)screenH / fb->height;
    }

    float drawW = fb->width * scale;
    float drawH = fb->height * scale;

    float drawX = (screenW - drawW) / 2.0f;
    float drawY = (screenH - drawH) / 2.0f;

    Rectangle src = { 0, 0, (float)fb->width, (float)fb->height };
    Rectangle dest = { drawX, drawY, drawW, drawH };
    Vector2 origin = { 0, 0 };

    ClearBackground(BLACK);

    DrawTexturePro(fb->texture, src, dest, origin, 0.0f, WHITE);
}

void Framebuffer_Destroy(Framebuffer *fb) {
    if (!fb) return;
    if (fb->pixels) free(fb->pixels);
    if (fb->texture.id != 0) UnloadTexture(fb->texture);

    fb->pixels = NULL;
    fb->texture.id = 0;
    fb->width = 0;
    fb->height = 0;
    fb->capacity = 0;
    fb->isDirty = false;
}

void Framebuffer_Resize(Framebuffer *fb, int newW, int newH) {
    if (!fb || (fb->width == newW && fb->height == newH)) return;

    if (fb->texture.id != 0 && newW <= fb->texture.width && newH <= fb->texture.height) {
        fb->width = newW;
        fb->height = newH;

        union { Color c; uint32_t i; } pun = { .c = BLACK };
        uint32_t cv = pun.i;
        uint32_t *p = (uint32_t*)fb->pixels;
        size_t activeTotal = (size_t)newW * (size_t)newH;

        for (size_t i = 0; i < activeTotal; i++) {
            p[i] = cv;
        }

        fb->isDirty = true;
        return;
    }

    Framebuffer_Destroy(fb);
    *fb = Framebuffer_Create(newW, newH);
}

void Framebuffer_Clear(Framebuffer *fb, Color c) {
    if (!fb || !fb->pixels) return;

    size_t total = (size_t)fb->width * (size_t)fb->height;
    union { Color c; uint32_t i; } pun = { .c = c };
    uint32_t cv = pun.i;
    uint32_t *p = (uint32_t*)fb->pixels;

    for (size_t i = 0; i < total; i++) {
        p[i] = cv;
    }
    fb->isDirty = true;
}

void Framebuffer_FillRect(Framebuffer *fb, int x, int y, int w, int h, Color c) {
    if (!fb || !fb->pixels) return;

    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > fb->width) w = fb->width - x;
    if (y + h > fb->height) h = fb->height - y;
    if (w <= 0 || h <= 0) return;

    union { Color c; uint32_t i; } pun = { .c = c };
    uint32_t cv = pun.i;
    uint32_t *pixels = (uint32_t*)fb->pixels;

    for (int yy = y; yy < y + h; yy++) {
        uint32_t *row = pixels + yy * fb->width + x;
        for (int xx = 0; xx < w; xx++) {
            row[xx] = cv;
        }
    }
    fb->isDirty = true;
}

void Framebuffer_Blit(Framebuffer *fb, int sx, int sy, int w, int h, int dx, int dy) {
    if (w <= 0 || h <= 0 || !fb || !fb->pixels) return;

    if (sx < 0) { w += sx; dx -= sx; sx = 0; }
    if (sy < 0) { h += sy; dy -= sy; sy = 0; }
    if (sx + w > fb->width) w = fb->width - sx;
    if (sy + h > fb->height) h = fb->height - sy;

    if (dx < 0) { w += dx; sx -= dx; dx = 0; }
    if (dy < 0) { h += dy; sy -= dy; dy = 0; }
    if (dx + w > fb->width) w = fb->width - dx;
    if (dy + h > fb->height) h = fb->height - dy;

    if (w <= 0 || h <= 0) return;

    int pitch = fb->width;
    int yStart, yEnd, yStep;

    if (dy > sy) {
        yStart = h - 1;
        yEnd = -1;
        yStep = -1;
    } else {
        yStart = 0;
        yEnd = h;
        yStep = 1;
    }

    for (int j = yStart; j != yEnd; j += yStep) {
        Color *srcRow = fb->pixels + (sy + j) * pitch + sx;
        Color *dstRow = fb->pixels + (dy + j) * pitch + dx;
        memmove(dstRow, srcRow, w * sizeof(Color));
    }
    fb->isDirty = true;
}

Color Framebuffer_GetPixel(Framebuffer *fb, int x, int y) {
    Color c = { 0, 0, 0, 255 };
    if (!fb || !fb->pixels || x < 0 || y < 0 || x >= fb->width || y >= fb->height) return c;
    return fb->pixels[y * fb->width + x];
}

void Framebuffer_DrawLine(Framebuffer *fb, int x0, int y0, int x1, int y1, Color c) {
    if (!fb || !fb->pixels) return;

    int w = fb->width;
    int h = fb->height;
    int outcode0 = ComputeOutCode(x0, y0, w, h);
    int outcode1 = ComputeOutCode(x1, y1, w, h);
    bool accept = false;

    while (true) {
        if (!(outcode0 | outcode1)) {
            accept = true;
            break;
        } else if (outcode0 & outcode1) {
            break;
        } else {
            int x, y;
            int outcodeOut = outcode0 ? outcode0 : outcode1;

            if (outcodeOut & TOP) {
                x = x0 + (int)((float)(x1 - x0) * (0.0f - (float)y0) / (float)(y1 - y0));
                y = 0;
            } else if (outcodeOut & BOTTOM) {
                x = x0 + (int)((float)(x1 - x0) * ((float)h - 1.0f - (float)y0) / (float)(y1 - y0));
                y = h - 1;
            } else if (outcodeOut & RIGHT) {
                y = y0 + (int)((float)(y1 - y0) * ((float)w - 1.0f - (float)x0) / (float)(x1 - x0));
                x = w - 1;
            } else if (outcodeOut & LEFT) {
                y = y0 + (int)((float)(y1 - y0) * (0.0f - (float)x0) / (float)(x1 - x0));
                x = 0;
            }

            if (outcodeOut == outcode0) {
                x0 = x;
                y0 = y;
                outcode0 = ComputeOutCode(x0, y0, w, h);
            } else {
                x1 = x;
                y1 = y;
                outcode1 = ComputeOutCode(x1, y1, w, h);
            }
        }
    }

    if (accept) {
        int dx = abs(x1 - x0);
        int sx = x0 < x1 ? 1 : -1;
        int dy = -abs(y1 - y0);
        int sy = y0 < y1 ? 1 : -1;
        int err = dx + dy;

        union { Color c; uint32_t i; } pun = { .c = c };
        uint32_t cv = pun.i;
        uint32_t *pixels = (uint32_t*)fb->pixels;

        while (true) {
            pixels[y0 * w + x0] = cv;

            if (x0 == x1 && y0 == y1) break;
            int e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
        fb->isDirty = true;
    }
}

void Framebuffer_SetPixel(Framebuffer *fb, int x, int y, Color c) {
    if (!fb || !fb->pixels || x < 0 || y < 0 || x >= fb->width || y >= fb->height) return;
    union { Color c; uint32_t i; } pun = { .c = c };
    ((uint32_t*)fb->pixels)[y * fb->width + x] = pun.i;
    fb->isDirty = true;
}
