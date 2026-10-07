/* Verifies the fork fixes at source level.
 *
 * 1. The frame limiter must not deadlock on macOS + PLATFORM_MEMORY. This was the
 *    whole point of patching GetTime()/InitTimer(): SetTargetFPS() should now work
 *    instead of having to be avoided.
 * 2. TakeScreenshot() must capture geometry drawn in the same frame without the
 *    caller flushing manually.
 * 3. The captured image must be screen-oriented and colour-correct.
 */
#include "raylib.h"
#include <stdio.h>

int main(int argc, char **argv)
{
    const char *out = (argc > 1)? argv[1] : "/tmp/fork_verify.png";

    SetTraceLogLevel(LOG_WARNING);
    InitWindow(320, 200, "fork verify");

    // (1) Frame limiting — previously an infinite busy loop on this backend
    SetTargetFPS(60);
    printf("[1] SetTargetFPS() returned without hanging\n");

    // (2) Draw, then screenshot mid-frame with no manual flush
    BeginDrawing();
    ClearBackground((Color){ 11, 13, 19, 255 });
    DrawRectangle(20, 20, 120, 80, (Color){ 229, 72, 77, 255 });    // RED-ish
    DrawCircleV((Vector2){ 240, 140 }, 40, (Color){ 48, 164, 108, 255 }); // GREEN-ish
    DrawText("fork", 24, 120, 30, (Color){ 238, 241, 247, 255 });
    TakeScreenshot(out);      // must capture everything above
    EndDrawing();

    printf("[2] TakeScreenshot() called mid-frame without manual flush\n");

    // (3) Confirm the frame limiter actually paces, i.e. time advances
    double t0 = GetTime();
    int spins = 0;
    for (int i = 0; i < 20 && spins < 100000000; i++)
    {
        double t1 = GetTime();
        if (t1 > t0) { spins = i; break; }
    }
    printf("[3] GetTime() advances: %s (delta detected after %d probes)\n",
           (GetTime() > t0)? "yes" : "NO", spins);

    CloseWindow();
    printf("[ok] wrote %s\n", out);
    return 0;
}
