#include "test/nile-print.h"
#include "text_layout.c"

#define LINE_ORIGIN_X   5
#define LINE_ORIGIN_Y   5
#define LINE_WIDTH    100
#define LINE_HEIGHT    10

static float glyph_metrics[] = {
    0, 2,
    10, 0,  10, 0,  10, 0,  5, 1,  10, 0,  10, 0,  5, 1,
    10, 0,  10, 0,  10, 0,  10, 0,  5, 1,  5, 1,
    10, 0,  10, 0,  20, 0, 15, 0,  0, 2,
    5, 0,  30, 0,  0, 2,
    0, 2,
};
static int glyph_metrics_n = sizeof (glyph_metrics) / sizeof (glyph_metrics[0]);

int
main ()
{
    char mem[1000000];
    nile_Process_t *pipeline;
    nile_Process_t *init = nile_startup (mem, sizeof (mem), 1);

    if (!init) {
        printf ("nile_startup failed\n");
        return 1;
    }

    pipeline = nile_Process_pipe (
        text_layout_LayoutText (init, LINE_ORIGIN_X, LINE_ORIGIN_Y,
                                      LINE_WIDTH, LINE_HEIGHT),
        nile_PrintToFile (init, 2, stdout),
        NILE_NULL);

    nile_Process_feed (pipeline, glyph_metrics, glyph_metrics_n);

    nile_sync (init);
    if (nile_error (init)) {
        printf ("nile_error\n");
        return 1;
    }

    nile_shutdown (init);

    return 0;
}
