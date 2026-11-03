#ifndef VX_BRUSH_H
#define VX_BRUSH_H
#include <stddef.h>
#include <stdint.h>
#include "vx_display_timing.h"
#include "vx_snake.h"
#include "vx_tetris.h"
enum { VX_DEMO, VX_BRUSH, VX_SNAKE, VX_TETRIS };

#define VX_X 32
#define VX_Y 32
#define VX_Z 24
#define VX_ROWS (VX_Y * VX_Z)

typedef struct {
    uint8_t canvas[VX_Z][VX_Y][VX_X]; /* 0 empty, 1..6 pigment; never cursor */
    uint8_t x, y, z, colour, angle, held, drawing, active, blink;
    uint8_t mode;
    VxSnake snake;
    int mode_request; /* -1 none, 0 demo, 1 brush, 2 snake, 3 tetris */
    uint32_t revision, voxels, revolution, rpm, phase_us, uploaded_frames;
    VxTetris tetris; /* appended: existing brush/snake field layout is preserved */
} VxBrush;
typedef struct {
    uint8_t canvas[VX_Z][VX_Y][VX_X];
    uint8_t x, y, z, colour, drawing, cursor_visible;
} VxBrushSnapshot;

void vx_brush_init(VxBrush *b);
void vx_brush_set_active(VxBrush *b, int active);
void vx_brush_set_mode(VxBrush *b, unsigned mode);
const char *vx_mode_name(unsigned mode);
void vx_brush_tick(VxBrush *b, uint32_t revolution);
void vx_brush_snapshot(const VxBrush *b, VxBrushSnapshot *s);
void vx_brush_pack_row(const VxBrushSnapshot *s, unsigned row, uint32_t rgb[3]);
size_t vx_brush_status(const VxBrush *b, char *out, size_t capacity);
size_t vx_brush_command(VxBrush *b, const char *command, char *out, size_t capacity);

#define VX_LINE_MAX 96
typedef struct { char line[VX_LINE_MAX]; size_t length; int discard; } VxProtocol;
typedef void (*VxReply)(void *context, const char *data, size_t size);
void vx_protocol_feed(VxProtocol *p, VxBrush *b, const uint8_t *data, size_t size,
                      VxReply reply, void *context);
#endif
