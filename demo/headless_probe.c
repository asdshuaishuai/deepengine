/* Headless probe: render a scene with no window, no GPU, no display.
 * This is what lets an agent verify its own output on a server.
 *
 * NOTE: SetTargetFPS() is deliberately not called — on macOS + PLATFORM_MEMORY it
 * deadlocks (see DECLARATION.md §8.1). Frames are driven by count instead, which is
 * what makes the output deterministic anyway. */
#include "raylib.h"
#include "rlgl.h"
#include <stdio.h>

int main(void)
{
    SetTraceLogLevel(LOG_WARNING);
    InitWindow(640, 400, "headless");

    for (int frame = 0; frame < 30; frame++)
    {
        BeginDrawing();
        ClearBackground((Color){ 11, 13, 19, 255 });
        DrawRectangleRounded((Rectangle){ 40, 40, 260, 140 }, 0.2f, 8, (Color){ 25, 30, 44, 255 });
        DrawRectangle(40, 40, 5, 140, (Color){ 229, 72, 77, 255 });
        DrawCircleV((Vector2){ 420, 200 }, 40.0f + (float)frame, (Color){ 124, 102, 220, 255 });
        DrawText("headless render", 64, 90, 28, (Color){ 238, 241, 247, 255 });
        EndDrawing();
    }

    // Flush the render batch before reading pixels (see DECLARATION.md §8.3)
    rlDrawRenderBatchActive();
    TakeScreenshot("/Volumes/data/dev/coding/deepcodeUI/deepEngine/shots/headless.png");
    CloseWindow();
    printf("headless render complete\n");
    return 0;
}
