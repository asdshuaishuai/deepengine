/* C side of the MoonBit -> raylib bridge.
 *
 * MoonBit strings are UTF-16, raylib wants UTF-8, so every string crossing the
 * boundary is converted here. Values flow back to MoonBit as Ints and Doubles
 * only, keeping the ABI surface trivial.
 */

#include "raylib.h"
#include "rlgl.h"
#include "moonbit.h"

#include <stdlib.h>
#include <string.h>

#define CANVAS_W 1280
#define CANVAS_H 800

/* ---------- UTF-16 (MoonBit) <-> UTF-8 (raylib) ---------- */

static char *utf16_to_utf8(const uint16_t *s, int32_t len)
{
    /* Worst case: 4 bytes per code unit (surrogate pair input is 2 units -> 4 bytes) */
    char *out = (char *)malloc((size_t)len*4 + 1);
    if (out == NULL) return NULL;

    int n = 0;
    for (int32_t i = 0; i < len; i++)
    {
        uint32_t cp = s[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < len)
        {
            uint32_t lo = s[i + 1];
            if (lo >= 0xDC00 && lo <= 0xDFFF)
            {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                i++;
            }
        }

        if (cp < 0x80) out[n++] = (char)cp;
        else if (cp < 0x800)
        {
            out[n++] = (char)(0xC0 | (cp >> 6));
            out[n++] = (char)(0x80 | (cp & 0x3F));
        }
        else if (cp < 0x10000)
        {
            out[n++] = (char)(0xE0 | (cp >> 12));
            out[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
            out[n++] = (char)(0x80 | (cp & 0x3F));
        }
        else
        {
            out[n++] = (char)(0xF0 | (cp >> 18));
            out[n++] = (char)(0x80 | ((cp >> 12) & 0x3F));
            out[n++] = (char)(0x80 | ((cp >> 6) & 0x3F));
            out[n++] = (char)(0x80 | (cp & 0x3F));
        }
    }
    out[n] = '\0';
    return out;
}

static const char *mbt_to_cstr(moonbit_string_t s)
{
    int32_t len = Moonbit_array_length(s);
    return utf16_to_utf8(s, len);
}

/* ---------- lifecycle ---------- */

static Font g_font;

MOONBIT_EXPORT void mbg_init(moonbit_string_t title)
{
    char *t = (char *)mbt_to_cstr(title);
    SetTraceLogLevel(LOG_WARNING);
    SetConfigFlags(FLAG_VSYNC_HINT);
    InitWindow(CANVAS_W, CANVAS_H, t);
    SetTargetFPS(60);
    SetExitKey(KEY_NULL);
    free(t);

    /* Default bitmap font lacks proper lowercase forms and any CJK coverage,
       so the engine always runs on a real TTF. */
    g_font = GetFontDefault();
    const char *candidates[] = {
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    };
    for (int i = 0; i < 2; i++)
    {
        if (FileExists(candidates[i]))
        {
            g_font = LoadFontEx(candidates[i], 96, NULL, 0);
            break;
        }
    }
    if (g_font.texture.id != 0) SetTextureFilter(g_font.texture, TEXTURE_FILTER_BILINEAR);
    else g_font = GetFontDefault();
}

MOONBIT_EXPORT void mbg_close(void)
{
    if (g_font.texture.id != GetFontDefault().texture.id) UnloadFont(g_font);
    CloseWindow();
}

MOONBIT_EXPORT int32_t mbg_should_close(void)
{
    return WindowShouldClose() ? 1 : 0;
}

/* ---------- frame ---------- */

MOONBIT_EXPORT void mbg_begin_frame(void)
{
    BeginDrawing();
}

MOONBIT_EXPORT void mbg_end_frame(void)
{
    EndDrawing();
}

MOONBIT_EXPORT void mbg_clear(int32_t r, int32_t g, int32_t b)
{
    ClearBackground((Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
}

MOONBIT_EXPORT double mbg_time(void)
{
    return GetTime();
}

MOONBIT_EXPORT int32_t mbg_fps(void)
{
    return GetFPS();
}

/* ---------- shapes ---------- */

MOONBIT_EXPORT void mbg_rect(double x, double y, double w, double h,
                             double radius, int32_t r, int32_t g, int32_t b)
{
    Color col = { (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 };
    Rectangle rec = { (float)x, (float)y, (float)w, (float)h };
    if (radius > 0.0)
    {
        double smallest = (w < h) ? w : h;
        DrawRectangleRounded(rec, (float)(radius/smallest), 8, col);
    }
    else DrawRectangleRec(rec, col);
}

MOONBIT_EXPORT void mbg_circle(double x, double y, double radius, int32_t r, int32_t g, int32_t b)
{
    DrawCircleV((Vector2){ (float)x, (float)y }, (float)radius,
                (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
}

MOONBIT_EXPORT void mbg_line(double x1, double y1, double x2, double y2,
                             double thick, int32_t r, int32_t g, int32_t b)
{
    DrawLineEx((Vector2){ (float)x1, (float)y1 }, (Vector2){ (float)x2, (float)y2 }, (float)thick,
               (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
}

/* Draws text centered on (cx, cy); returns the measured width so MoonBit can
 * lay out without duplicating font metrics. */
MOONBIT_EXPORT double mbg_text(moonbit_string_t text, double cx, double cy,
                              double size, int32_t r, int32_t g, int32_t b)
{
    char *t = (char *)mbt_to_cstr(text);
    Vector2 dim = MeasureTextEx(g_font, t, (float)size, (float)size/16.0f);
    Vector2 pos = { (float)cx, (float)cy };
    DrawTextEx(g_font, t, pos, (float)size, (float)size/16.0f,
               (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
    free(t);
    return (double)dim.x;
}

/* ---------- input ---------- */

MOONBIT_EXPORT int32_t mbg_key_pressed(int32_t key)
{
    return IsKeyPressed(key) ? 1 : 0;
}

/* ---------- deterministic capture ---------- */

MOONBIT_EXPORT void mbg_screenshot(moonbit_string_t path)
{
    char *p = (char *)mbt_to_cstr(path);
    rlDrawRenderBatchActive();   // flush pending draws before reading the framebuffer
    TakeScreenshot(p);
    free(p);
}
