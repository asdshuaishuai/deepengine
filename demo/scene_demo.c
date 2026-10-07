/*********************************************************************************************
*
*   scene_demo.c — raylib probe for an AI-native game engine
*
*   Reads a declarative scene file (markdown + ```mbg fenced ops), renders it with raylib,
*   hot-reloads on change and can capture a deterministic frame for CI verification.
*
*   Ops:
*       bg <r> <g> <b>
*       rect <id> <x> <y> <w> <h> #hex [radius]
*       circle <id> <x> <y> <r> #hex
*       line <id> <x1> <y1> <x2> <y2> <thick> #hex
*       text <id> <x> <y> <size> #hex "content"
*       sprite <id> <x> <y> <size> #hex
*       spin <id> <deg_per_sec>
*       orbit <id> <cx> <cy> <radius> <deg_per_sec> <phase_rad>
*       pulse <id> <min> <max> <hz>
*
*   Flags:
*       --scene <path>       scene file (default: scene.mbg.md next to binary)
*       --shot <path.png>    capture a frame and exit
*       --frames <n>         frame to capture (default 90) / frames to run
*       --hidden             hide the window (for headless capture)
*
*   License: MIT, same spirit as raylib (zlib/libpng). Probe code, not final engine.
*
*********************************************************************************************/

#include "raylib.h"
#include "rlgl.h"      // rlDrawRenderBatchActive: required for deterministic capture

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define MAX_SHAPES      512
#define MAX_LINE        1024
#define CANVAS_W        1280
#define CANVAS_H        800
#define FPS             60.0f
#define PI              3.14159265358979323846f

typedef enum {
    SH_RECT,
    SH_CIRCLE,
    SH_LINE,
    SH_TEXT,
    SH_SPRITE
} ShapeKind;

typedef struct {
    ShapeKind kind;
    char id[48];
    float x, y, w, h;           // rect: x,y,w,h | circle: x,y,r (in w) | line: x,y,w=x2,h=y2
    float radius;               // rect corner radius (px)
    float thick;                // line thickness
    int fontSize;               // text
    char text[192];             // text content
    Color color;
    // animation
    float spin;                 // deg/sec around own center
    int hasOrbit;
    float ocx, ocy, oradius, ospin, ophase;
    int hasPulse;
    float pmin, pmax, phz;
} Shape;

typedef struct {
    Color bg;
    Shape shapes[MAX_SHAPES];
    int count;
    bool ok;
} Scene;

//----------------------------------------------------------------------------------
// Parsing helpers
//----------------------------------------------------------------------------------

static char *trim(char *s)
{
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
    char *end = s + strlen(s);
    while (end > s && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n')) *--end = '\0';
    return s;
}

static bool parse_hex_color(const char *s, Color *out)
{
    if (s == NULL || s[0] != '#') return false;

    unsigned int r = 0, g = 0, b = 0, a = 255;
    size_t len = strlen(s);

    if (len == 4)       // #rgb shorthand
    {
        if (sscanf(s + 1, "%1x%1x%1x", &r, &g, &b) != 3) return false;
        r *= 17; g *= 17; b *= 17;
    }
    else if (len == 7 || len == 9)
    {
        if (len == 7)
        {
            if (sscanf(s + 1, "%2x%2x%2x", &r, &g, &b) != 3) return false;
        }
        else
        {
            if (sscanf(s + 1, "%2x%2x%2x%2x", &r, &g, &b, &a) != 4) return false;
        }
    }
    else return false;

    *out = (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a };
    return true;
}

static bool parse_quoted(const char *s, char *out, size_t outSize)
{
    const char *start = strchr(s, '"');
    if (start == NULL) return false;
    const char *end = strrchr(start + 1, '"');
    if (end == NULL) return false;

    size_t len = (size_t)(end - start - 1);
    if (len >= outSize) len = outSize - 1;
    memcpy(out, start + 1, len);
    out[len] = '\0';
    return true;
}

static Shape *find_shape(Scene *scene, const char *id)
{
    for (int i = 0; i < scene->count; i++)
    {
        if (strcmp(scene->shapes[i].id, id) == 0) return &scene->shapes[i];
    }
    return NULL;
}

static Shape *push_shape(Scene *scene, ShapeKind kind, const char *id)
{
    if (scene->count >= MAX_SHAPES) return NULL;

    Shape *s = &scene->shapes[scene->count++];
    memset(s, 0, sizeof(*s));
    s->kind = kind;
    snprintf(s->id, sizeof(s->id), "%s", id);
    s->color = WHITE;
    s->fontSize = 20;
    return s;
}

//----------------------------------------------------------------------------------
// Scene loading
//----------------------------------------------------------------------------------

static bool load_scene(const char *path, Scene *scene, char *errMsg, size_t errSize)
{
    FILE *f = fopen(path, "rb");
    if (f == NULL)
    {
        snprintf(errMsg, errSize, "cannot open scene: %s", path);
        return false;
    }

    Scene fresh = { 0 };
    fresh.bg = (Color){ 11, 13, 19, 255 };
    fresh.ok = true;

    char line[MAX_LINE];
    bool inFence = false;
    int lineNo = 0;

    while (fgets(line, sizeof(line), f) != NULL)
    {
        lineNo++;
        char *s = trim(line);

        // Fence tracking: ops are only honored inside ```mbg blocks
        if (strncmp(s, "```", 3) == 0)
        {
            inFence = !inFence;
            continue;
        }
        if (!inFence) continue;
        if (s[0] == '\0') continue;
        if (s[0] == '#' && (s[1] == ' ' || s[1] == '\0')) continue;   // op-level comment

        // Tokenize first word
        char op[32] = { 0 };
        int consumed = 0;
        if (sscanf(s, "%31s%n", op, &consumed) != 1) continue;
        char *rest = trim(s + consumed);

        if (strcmp(op, "bg") == 0)
        {
            int r = 0, g = 0, b = 0;
            if (sscanf(rest, "%d %d %d", &r, &g, &b) == 3)
            {
                fresh.bg = (Color){ (unsigned char)r, (unsigned char)g, (unsigned char)b, 255 };
            }
            continue;
        }

        if (strcmp(op, "spin") == 0 || strcmp(op, "orbit") == 0 || strcmp(op, "pulse") == 0)
        {
            char id[48] = { 0 };
            if (sscanf(rest, "%47s%n", id, &consumed) != 1) continue;
            Shape *target = find_shape(&fresh, id);
            if (target == NULL)
            {
                snprintf(errMsg, errSize, "line %d: unknown id '%s'", lineNo, id);
                continue;
            }
            char *args = trim(rest + consumed);

            if (strcmp(op, "spin") == 0)
            {
                sscanf(args, "%f", &target->spin);
            }
            else if (strcmp(op, "orbit") == 0)
            {
                target->hasOrbit = 1;
                sscanf(args, "%f %f %f %f %f", &target->ocx, &target->ocy, &target->oradius, &target->ospin, &target->ophase);
            }
            else
            {
                target->hasPulse = 1;
                sscanf(args, "%f %f %f", &target->pmin, &target->pmax, &target->phz);
            }
            continue;
        }

        // Shape ops: <op> <id> <numbers...> #color [extra]
        char id[48] = { 0 };
        if (sscanf(rest, "%47s%n", id, &consumed) != 1) continue;
        char *args = trim(rest + consumed);
        char *argsRaw = args;   // kept intact for quoted strings that follow the color token

        // Quoted content must be extracted before the color token is stripped,
        // because stripping replaces '#' with '\0' and truncates the rest of the line
        char quoted[192] = { 0 };
        bool hasQuoted = parse_quoted(argsRaw, quoted, sizeof(quoted));

        // Pull the color token out of the argument list
        Color color = WHITE;
        {
            char *hash = strchr(args, '#');
            if (hash != NULL)
            {
                char colorTok[16] = { 0 };
                sscanf(hash, "%15s", colorTok);
                if (!parse_hex_color(colorTok, &color))
                {
                    snprintf(errMsg, errSize, "line %d: bad color '%s'", lineNo, colorTok);
                }
                *hash = '\0';
                args = trim(args);
            }
        }

        if (strcmp(op, "rect") == 0)
        {
            Shape *sh = push_shape(&fresh, SH_RECT, id);
            if (sh == NULL) break;
            sscanf(args, "%f %f %f %f %f", &sh->x, &sh->y, &sh->w, &sh->h, &sh->radius);
            sh->color = color;
        }
        else if (strcmp(op, "circle") == 0)
        {
            Shape *sh = push_shape(&fresh, SH_CIRCLE, id);
            if (sh == NULL) break;
            sscanf(args, "%f %f %f", &sh->x, &sh->y, &sh->w);   // w holds radius
            sh->color = color;
        }
        else if (strcmp(op, "line") == 0)
        {
            Shape *sh = push_shape(&fresh, SH_LINE, id);
            if (sh == NULL) break;
            sscanf(args, "%f %f %f %f %f", &sh->x, &sh->y, &sh->w, &sh->h, &sh->thick);
            sh->color = color;
        }
        else if (strcmp(op, "text") == 0)
        {
            Shape *sh = push_shape(&fresh, SH_TEXT, id);
            if (sh == NULL) break;
            sscanf(args, "%f %f %d", &sh->x, &sh->y, &sh->fontSize);
            if (hasQuoted) snprintf(sh->text, sizeof(sh->text), "%s", quoted);
            else
            {
                snprintf(errMsg, errSize, "line %d: text op needs \"quoted\" content", lineNo);
            }
            sh->color = color;
        }
        else if (strcmp(op, "sprite") == 0)
        {
            Shape *sh = push_shape(&fresh, SH_SPRITE, id);
            if (sh == NULL) break;
            sscanf(args, "%f %f %f", &sh->x, &sh->y, &sh->w);   // w holds pixel size
            if (sh->w <= 0.0f) sh->w = 64.0f;
            sh->color = color;
        }
        else
        {
            snprintf(errMsg, errSize, "line %d: unknown op '%s'", lineNo, op);
        }
    }

    fclose(f);
    *scene = fresh;
    return true;
}

//----------------------------------------------------------------------------------
// Rendering
//----------------------------------------------------------------------------------

static void draw_scene_2d(Scene *scene, Texture2D spriteTex, Font font, float t)
{
    ClearBackground(scene->bg);

    for (int i = 0; i < scene->count; i++)
    {
        Shape *s = &scene->shapes[i];

        float px = s->x;
        float py = s->y;
        if (s->hasOrbit)
        {
            float ang = s->ophase + t*s->ospin*(PI/180.0f);
            px = s->ocx + cosf(ang)*s->oradius;
            py = s->ocy + sinf(ang)*s->oradius;
        }

        float scale = 1.0f;
        if (s->hasPulse) scale = s->pmin + (s->pmax - s->pmin)*(0.5f + 0.5f*sinf(t*s->phz*2.0f*PI));

        float rot = s->spin*t;

        switch (s->kind)
        {
            case SH_RECT:
            {
                Rectangle rec = { px, py, s->w, s->h };
                if (rot != 0.0f)
                {
                    Vector2 pivot = { s->w/2.0f, s->h/2.0f };
                    DrawRectanglePro(rec, pivot, rot, s->color);
                }
                else if (s->radius > 0.0f)
                {
                    float roundness = s->radius/((s->w < s->h)? s->w : s->h);
                    DrawRectangleRounded(rec, roundness, 8, s->color);
                }
                else DrawRectangleRec(rec, s->color);
            } break;
            case SH_CIRCLE:
            {
                DrawCircleV((Vector2){ px, py }, s->w*scale, s->color);
            } break;
            case SH_LINE:
            {
                DrawLineEx((Vector2){ px, py }, (Vector2){ s->w, s->h }, s->thick, s->color);
            } break;
            case SH_TEXT:
            {
                float fontSize = (float)s->fontSize*scale;
                Vector2 size = MeasureTextEx(font, s->text, fontSize, fontSize/16.0f);
                Vector2 origin = { size.x/2.0f, size.y/2.0f };
                Vector2 pos = { px + size.x/2.0f, py + size.y/2.0f };
                DrawTextPro(font, s->text, pos, origin, rot, fontSize, fontSize/16.0f, s->color);
            } break;
            case SH_SPRITE:
            {
                float drawSize = s->w*scale;
                Vector2 origin = { drawSize/2.0f, drawSize/2.0f };
                Rectangle src = { 0, 0, (float)spriteTex.width, (float)spriteTex.height };
                Rectangle dst = { px + drawSize/2.0f, py + drawSize/2.0f, drawSize, drawSize };
                DrawTexturePro(spriteTex, src, dst, origin, rot, s->color);
            } break;
            default: break;
        }
    }
}

static void draw_showcase_3d(Camera3D *camera, float t)
{
    ClearBackground((Color){ 11, 13, 19, 255 });

    UpdateCamera(camera, CAMERA_ORBITAL);

    BeginMode3D(*camera);

    DrawGrid(20, 1.0f);

    for (int x = -2; x <= 2; x++)
    {
        for (int z = -2; z <= 2; z++)
        {
            float h = 1.0f + 0.9f*sinf(t*1.6f + (float)(x + z));
            Color c = ColorFromHSV(fmodf(t*40.0f + (float)(x*30 + z*45), 360.0f), 0.62f, 0.95f);
            Vector3 pos = { (float)x*2.2f, h/2.0f, (float)z*2.2f };
            DrawCube(pos, 1.4f, h, 1.4f, c);
            DrawCubeWires(pos, 1.4f, h, 1.4f, Fade(BLACK, 0.35f));
        }
    }

    EndMode3D();
}

//----------------------------------------------------------------------------------
// Frame capture
//----------------------------------------------------------------------------------

// Captures the current frame and writes it to `path`.
//
// This is a thin wrapper now. Earlier it had to read pixels and post-process them
// because rlReadScreenPixels() produced a flipped, colour-swapped image on the
// software backend; that is fixed in the engine fork (FORK.md D2), as is the
// missing batch flush that made screenshots come out empty (D3). Keeping the
// fixes at the source removes ~110 lines of per-call workaround here.
static bool capture_frame(const char *path)
{
    TakeScreenshot(path);
    return FileExists(path);
}

//----------------------------------------------------------------------------------
// Program
//----------------------------------------------------------------------------------

static double file_mtime(const char *path)
{
    struct stat st;
    if (stat(path, &st) != 0) return -1.0;
    return (double)st.st_mtime + (double)st.st_mtimespec.tv_nsec*1e-9;
}

int main(int argc, char **argv)
{
    const char *scenePath = NULL;
    const char *shotPath = NULL;
    const char *fontPath = NULL;
    int shotFrame = 90;
    int startMode = 2;
    bool hidden = false;

    for (int i = 1; i < argc; i++)
    {
        if (strcmp(argv[i], "--scene") == 0 && i + 1 < argc) scenePath = argv[++i];
        else if (strcmp(argv[i], "--shot") == 0 && i + 1 < argc) shotPath = argv[++i];
        else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) shotFrame = atoi(argv[++i]);
        else if (strcmp(argv[i], "--font") == 0 && i + 1 < argc) fontPath = argv[++i];
        else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) startMode = atoi(argv[++i]);
        else if (strcmp(argv[i], "--hidden") == 0) hidden = true;
    }

    char defaultScene[1024];
    if (scenePath == NULL)
    {
        // Scene file sits next to the binary by convention
        const char *slash = strrchr(argv[0], '/');
        int dirLen = (slash != NULL)? (int)(slash - argv[0] + 1) : 0;
        snprintf(defaultScene, sizeof(defaultScene), "%.*s%s", dirLen, argv[0], "scene.mbg.md");
        scenePath = defaultScene;
    }

    if (hidden) SetConfigFlags(FLAG_WINDOW_HIDDEN);
    SetConfigFlags(FLAG_VSYNC_HINT);
    InitWindow(CANVAS_W, CANVAS_H, "deepEngine probe — raylib + declarative scene");

    // Frame limiting works on every backend now. On macOS + PLATFORM_MEMORY this used
    // to hang at 100% CPU because the platform timer was missing (FORK.md D1), so it
    // had to be compiled out; the fix lives in the engine instead of here.
    SetTargetFPS(60);
    SetExitKey(KEY_NULL);   // ESC handled manually so it can also leave 3D mode

    // Text font: prefer an explicit TTF, else the first system font that exists.
    // Bundled fonts ship with the final engine; system lookup keeps the probe portable.
    const char *systemFonts[] = {
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Geneva.ttf",
    };
    Font font = GetFontDefault();
    const char *resolvedFont = "default bitmap font";
    if (fontPath != NULL)
    {
        font = LoadFontEx(fontPath, 96, NULL, 0);
        resolvedFont = fontPath;
    }
    else
    {
        for (int i = 0; i < (int)(sizeof(systemFonts)/sizeof(systemFonts[0])); i++)
        {
            if (FileExists(systemFonts[i]))
            {
                font = LoadFontEx(systemFonts[i], 96, NULL, 0);
                resolvedFont = systemFonts[i];
                break;
            }
        }
    }
    if (font.texture.id == 0) { font = GetFontDefault(); resolvedFont = "default bitmap font"; }
    else SetTextureFilter(font.texture, TEXTURE_FILTER_BILINEAR);
    TraceLog(LOG_INFO, "font: %s (%d glyphs)", resolvedFont, font.glyphCount);

    // Procedural sprite texture: white checked pattern, tinted per shape color
    Image img = GenImageChecked(64, 64, 8, 8, (Color){ 255, 255, 255, 255 }, (Color){ 150, 150, 150, 255 });
    Texture2D spriteTex = LoadTextureFromImage(img);
    UnloadImage(img);
    SetTextureFilter(spriteTex, TEXTURE_FILTER_BILINEAR);

    Scene scene = { 0 };
    char errMsg[256] = { 0 };
    bool sceneOk = load_scene(scenePath, &scene, errMsg, sizeof(errMsg));
    double sceneMtime = file_mtime(scenePath);

    if (sceneOk) TraceLog(LOG_INFO, "scene: %d ops from %s", scene.count, scenePath);
    else TraceLog(LOG_ERROR, "%s", errMsg);

    Camera3D camera = { 0 };
    camera.position = (Vector3){ 0.0f, 9.0f, 14.0f };
    camera.target = (Vector3){ 0.0f, 1.0f, 0.0f };
    camera.up = (Vector3){ 0.0f, 1.0f, 0.0f };
    camera.fovy = 55.0f;
    camera.projection = CAMERA_PERSPECTIVE;

    int mode = startMode;       // 2 = declarative scene, 3 = 3d showcase
    bool paused = false;
    long framesCounter = 0;
    int lastReload = 0;
    char status[256] = "ready";

    while (!WindowShouldClose())
    {
        // -------- hot reload (file mtime watcher) --------
        double mtime = file_mtime(scenePath);
        if (mtime > 0 && (mtime != sceneMtime))
        {
            sceneMtime = mtime;
            Scene next = { 0 };
            char err[256] = { 0 };
            if (load_scene(scenePath, &next, err, sizeof(err)))
            {
                scene = next;
                sceneOk = true;
                lastReload = (int)framesCounter;
                snprintf(status, sizeof(status), "reloaded %d ops @frame %ld", scene.count, framesCounter);
            }
            else snprintf(status, sizeof(status), "reload failed: %s", err);
        }

        // -------- input --------
        if (IsKeyPressed(KEY_R))
        {
            sceneOk = load_scene(scenePath, &scene, errMsg, sizeof(errMsg));
            lastReload = (int)framesCounter;
        }
        if (IsKeyPressed(KEY_S) && shotPath == NULL) capture_frame("shot.png");
        if (IsKeyPressed(KEY_SPACE)) paused = !paused;
        if (IsKeyPressed(KEY_THREE)) mode = 3;
        if (IsKeyPressed(KEY_ONE) || IsKeyPressed(KEY_TWO)) mode = 2;
        if (IsKeyPressed(KEY_ESCAPE))
        {
            if (mode == 3) mode = 2;
            else break;
        }

        float t = (float)framesCounter/FPS;   // deterministic clock

        BeginDrawing();

        if (mode == 3) draw_showcase_3d(&camera, t);
        else if (sceneOk) draw_scene_2d(&scene, spriteTex, font, t);
        else
        {
            ClearBackground((Color){ 30, 12, 14, 255 });
            DrawTextEx(font, errMsg, (Vector2){ 40, 40 }, 24, 1.0f, (Color){ 229, 72, 77, 255 });
        }

        // -------- hud --------
        DrawRectangle(0, 0, CANVAS_W, 34, Fade(BLACK, 0.45f));
        DrawTextEx(font, TextFormat("deepEngine probe  |  raylib %s  |  %s  |  %d ops  |  %.0f fps",
                                    RAYLIB_VERSION, (mode == 3)? "mode: 3d showcase" : "mode: declarative scene",
                                    scene.count, (float)GetFPS()),
                   (Vector2){ 12, 8 }, 19, 0.5f, (Color){ 200, 208, 224, 255 });
        if (framesCounter - lastReload < 120 && lastReload > 0)
        {
            DrawRectangle(0, 36, CANVAS_W, 26, Fade(ColorAlpha((Color){ 48, 164, 108, 255 }, 0.8f), 0.8f));
            DrawTextEx(font, status, (Vector2){ 12, 39 }, 18, 0.5f, (Color){ 240, 255, 248, 255 });
        }

        // -------- deterministic capture --------
        if (shotPath != NULL && framesCounter >= shotFrame)
        {
            capture_frame(shotPath);
            EndDrawing();
            TraceLog(LOG_INFO, "captured frame %ld -> %s", framesCounter, shotPath);
            break;
        }

        EndDrawing();
        if (!paused) framesCounter++;
    }

    UnloadTexture(spriteTex);
    if (font.texture.id != GetFontDefault().texture.id) UnloadFont(font);
    CloseWindow();
    TraceLog(LOG_INFO, "deepEngine probe: clean exit");
    return 0;
}
