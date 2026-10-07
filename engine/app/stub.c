/* C 侧桥：MoonBit ↔ raylib。
 *
 * 职责边界（blueprint B 层）：编码转换 + 调用转发，零游戏语义。
 * - MoonBit String 是 UTF-16，raylib 要 UTF-8 —— 双向转码都在这里
 * - TakeScreenshot 直接可用：fork D3 已内置批次刷新（见 FORK.md）
 *
 * 注意：app/（GPU 链接）与 apphead/（软件光栅链接）各持一份本文件，
 * 两者必须保持一致。
 */

#include "raylib.h"
#include "moonbit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- UTF-16 (MoonBit) → UTF-8 (raylib) ---------- */

static char *utf16_to_utf8(const uint16_t *s, int32_t len)
{
    char *out = (char *)malloc((size_t)len * 4 + 1);
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

/* ---------- UTF-8 (磁盘) → UTF-16 (MoonBit String) ---------- */

static moonbit_string_t utf8_to_mbt(const char *src, int32_t n)
{
    /* 先数 UTF-16 单元数 */
    int32_t units = 0;
    for (int32_t i = 0; i < n; )
    {
        unsigned char c = (unsigned char)src[i];
        int32_t adv;
        uint32_t cp;
        if (c < 0x80) { cp = c; adv = 1; }
        else if ((c >> 5) == 0x6 && i + 1 < n) { cp = ((c & 0x1F) << 6) | ((unsigned char)src[i+1] & 0x3F); adv = 2; }
        else if ((c >> 4) == 0xE && i + 2 < n) { cp = ((c & 0x0F) << 12) | (((unsigned char)src[i+1] & 0x3F) << 6) | ((unsigned char)src[i+2] & 0x3F); adv = 3; }
        else if ((c >> 3) == 0x1E && i + 3 < n) { cp = ((c & 0x07) << 18) | (((unsigned char)src[i+1] & 0x3F) << 12) | (((unsigned char)src[i+2] & 0x3F) << 6) | ((unsigned char)src[i+3] & 0x3F); adv = 4; }
        else { cp = 0xFFFD; adv = 1; } /* 坏字节：替换字符，不崩 */
        units += (cp >= 0x10000) ? 2 : 1;
        i += adv;
    }

    moonbit_string_t out = moonbit_make_string_raw(units);
    uint16_t *dst = (uint16_t *)out;
    int32_t o = 0;
    for (int32_t i = 0; i < n; )
    {
        unsigned char c = (unsigned char)src[i];
        int32_t adv;
        uint32_t cp;
        if (c < 0x80) { cp = c; adv = 1; }
        else if ((c >> 5) == 0x6 && i + 1 < n) { cp = ((c & 0x1F) << 6) | ((unsigned char)src[i+1] & 0x3F); adv = 2; }
        else if ((c >> 4) == 0xE && i + 2 < n) { cp = ((c & 0x0F) << 12) | (((unsigned char)src[i+1] & 0x3F) << 6) | ((unsigned char)src[i+2] & 0x3F); adv = 3; }
        else if ((c >> 3) == 0x1E && i + 3 < n) { cp = ((c & 0x07) << 18) | (((unsigned char)src[i+1] & 0x3F) << 12) | (((unsigned char)src[i+2] & 0x3F) << 6) | ((unsigned char)src[i+3] & 0x3F); adv = 4; }
        else { cp = 0xFFFD; adv = 1; }
        if (cp >= 0x10000)
        {
            cp -= 0x10000;
            dst[o++] = (uint16_t)(0xD800 | (cp >> 10));
            dst[o++] = (uint16_t)(0xDC00 | (cp & 0x3FF));
        }
        else dst[o++] = (uint16_t)cp;
        i += adv;
    }
    return out;
}

/* ---------- 生命周期 ---------- */

static Font g_font;

MOONBIT_EXPORT void mbg_init(moonbit_string_t title, int32_t w, int32_t h, int32_t hidden)
{
    char *t = (char *)mbt_to_cstr(title);
    if (hidden) SetConfigFlags(FLAG_WINDOW_HIDDEN);
    SetTraceLogLevel(LOG_WARNING);
    InitWindow(w, h, t);
    /* SetTargetFPS 在 PLATFORM_MEMORY + macOS 上曾死锁，fork D1 已修（FORK.md）——现在可安全使用 */
    SetTargetFPS(60);
    SetExitKey(KEY_NULL);
    free(t);

    /* 默认位图字体小写字形异常且无 CJK——始终加载 TTF（程序化优先阶段的 UI 底座） */
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
    if (g_font.texture.id != 0 && g_font.texture.id != GetFontDefault().texture.id) UnloadFont(g_font);
    CloseWindow();
}

MOONBIT_EXPORT int32_t mbg_should_close(void)
{
    return WindowShouldClose() ? 1 : 0;
}

/* ---------- 帧与绘制 ---------- */

MOONBIT_EXPORT void mbg_begin_frame(void) { BeginDrawing(); }
MOONBIT_EXPORT void mbg_end_frame(void) { EndDrawing(); }

MOONBIT_EXPORT void mbg_clear(int32_t r, int32_t g, int32_t b)
{
    ClearBackground((Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
}

MOONBIT_EXPORT void mbg_rect(double x, double y, double w, double h, int32_t r, int32_t g, int32_t b)
{
    DrawRectangle((int)x, (int)y, (int)w, (int)h,
                  (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
}

MOONBIT_EXPORT void mbg_circle(double cx, double cy, double radius, int32_t r, int32_t g, int32_t b)
{
    DrawCircleV((Vector2){ (float)cx, (float)cy }, (float)radius,
                (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
}

MOONBIT_EXPORT double mbg_text(moonbit_string_t text, double x, double y, double size,
                               int32_t r, int32_t g, int32_t b)
{
    char *t = (char *)mbt_to_cstr(text);
    Vector2 dim = MeasureTextEx(g_font, t, (float)size, (float)size / 16.0f);
    DrawTextEx(g_font, t, (Vector2){ (float)x, (float)y }, (float)size, (float)size / 16.0f,
               (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 });
    free(t);
    return (double)dim.x;
}

/* ---------- 输入与截图 ---------- */

MOONBIT_EXPORT int32_t mbg_key_down(int32_t key)
{
    return IsKeyDown(key) ? 1 : 0;
}

MOONBIT_EXPORT void mbg_set_fps(int32_t n) { SetTargetFPS(n); }

MOONBIT_EXPORT void mbg_screenshot(moonbit_string_t path)
{
    char *p = (char *)mbt_to_cstr(path);
    TakeScreenshot(p); /* fork D3：内部已 flush 批次 */
    free(p);
}

/* ---------- 文件 IO（UTF-8 磁盘 ↔ UTF-16 String）---------- */

MOONBIT_EXPORT moonbit_string_t mbg_read_file(moonbit_string_t path)
{
    char *p = (char *)mbt_to_cstr(path);
    FILE *f = fopen(p, "rb");
    free(p);
    if (f == NULL) return moonbit_make_string_raw(0);

    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n <= 0 || n > (16 * 1024 * 1024)) { fclose(f); return moonbit_make_string_raw(0); }

    char *buf = (char *)malloc((size_t)n);
    if (buf == NULL) { fclose(f); return moonbit_make_string_raw(0); }
    size_t got = fread(buf, 1, (size_t)n, f);
    fclose(f);

    moonbit_string_t out = utf8_to_mbt(buf, (int32_t)got);
    free(buf);
    return out;
}

MOONBIT_EXPORT int32_t mbg_file_exists(moonbit_string_t path)
{
    char *p = (char *)mbt_to_cstr(path);
    int32_t ok = FileExists(p) ? 1 : 0;
    free(p);
    return ok;
}

/* ---------- 音效合成器（程序化优先 §6.4：参数即资产，零音频文件）---------- */

static bool g_audio_ready = false;
static Sound g_sfx[4]; // 0 jump 1 coin 2 win 3 dead

/* 方波采样生成：freq 从 f0 线性滑到 f1，线性衰减包络 */
static void gen_square_sweep(Sound *out, double f0, double f1, double dur, double vol)
{
    const int rate = 22050;
    int n = (int)(dur * rate);
    short *samples = (short *)malloc(sizeof(short) * n);
    double phase = 0.0;
    for (int i = 0; i < n; i++)
    {
        double t = (double)i / n;
        double f = f0 + (f1 - f0) * t;
        phase += f / rate;
        short sq = (phase - (double)(long long)phase) < 0.5 ? 1 : -1; /* 方波 */
        double env = 1.0 - t; /* 线性衰减 */
        samples[i] = (short)(sq * vol * env * 32000.0);
    }
    Wave w = { 0 };
    w.frameCount = n;
    w.sampleRate = rate;
    w.sampleSize = 16;
    w.channels = 1;
    w.data = samples;
    *out = LoadSoundFromWave(w);
    UnloadWave(w); /* LoadSoundFromWave 已拷贝 */
}

MOONBIT_EXPORT void mbg_audio_init(void)
{
    if (g_audio_ready) return;
    InitAudioDevice();
    if (!IsAudioDeviceReady()) return; /* 无音频硬件：静默降级，不崩 */
    gen_square_sweep(&g_sfx[0], 180.0, 520.0, 0.12, 0.5);  /* jump：上滑 */
    gen_square_sweep(&g_sfx[1], 880.0, 1320.0, 0.09, 0.4); /* coin：亮双音 */
    gen_square_sweep(&g_sfx[2], 523.0, 784.0, 0.45, 0.45); /* win：上行琶音感 */
    gen_square_sweep(&g_sfx[3], 220.0, 60.0, 0.30, 0.5);   /* dead：下滑 */
    g_audio_ready = true;
}

MOONBIT_EXPORT void mbg_sfx(moonbit_string_t name)
{
    if (!g_audio_ready) return;
    char *n = (char *)mbt_to_cstr(name);
    int idx = -1;
    if (strcmp(n, "jump") == 0) idx = 0;
    else if (strcmp(n, "coin") == 0) idx = 1;
    else if (strcmp(n, "win") == 0) idx = 2;
    else if (strcmp(n, "dead") == 0) idx = 3;
    free(n);
    if (idx >= 0 && g_sfx[idx].frameCount > 0) PlaySound(g_sfx[idx]);
}

MOONBIT_EXPORT void mbg_warn(moonbit_string_t msg)
{
    char *m = (char *)mbt_to_cstr(msg);
    fprintf(stderr, "%s\n", m);
    fflush(stderr);
    free(m);
}
