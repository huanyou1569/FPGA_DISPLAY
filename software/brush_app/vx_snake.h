#ifndef VX_SNAKE_H
#define VX_SNAKE_H
#include <stdint.h>
#define VX_SNAKE_MAX 200
#define VX_FOOD_MAX 10
enum { VX_PX, VX_NX, VX_PY, VX_NY, VX_PZ, VX_NZ };
typedef struct { int16_t x,y,z; } VxSegment;
typedef struct {
    VxSegment body[VX_SNAKE_MAX], food[VX_FOOD_MAX];
    uint16_t length, score, high_score;
    uint8_t food_count, dir, alive, step_counter, turned;
    uint32_t rng, last_revolution, steps, collisions;
} VxSnake;
void vx_snake_init(VxSnake *s);
void vx_snake_start(VxSnake *s, uint32_t revolution, int immediate);
int vx_snake_tick(VxSnake *s, uint32_t revolution);
void vx_snake_turn(VxSnake *s, char command);
void vx_snake_render(const VxSnake *s, uint8_t canvas[24][32][32]);
#endif
