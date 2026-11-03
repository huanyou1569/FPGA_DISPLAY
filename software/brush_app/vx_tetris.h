#ifndef VX_TETRIS_H
#define VX_TETRIS_H
#include <stdint.h>
#define VX_TW 6
#define VX_TD 6
#define VX_TH 10
#define VX_TPIECES 10
typedef struct { int8_t x,y,z; } VxBlock;
typedef struct {
    uint8_t well[VX_TH][VX_TD][VX_TW];
    VxBlock blocks[4];
    int8_t x,y,z;
    uint8_t type,next,bag[VX_TPIECES],bag_left,alive,paused,timed;
    uint32_t score,high_score,planes,pieces,rng,last_ms,elapsed;
} VxTetris;
void vx_tetris_init(VxTetris *t);
void vx_tetris_start(VxTetris *t);
int vx_tetris_tick(VxTetris *t,uint32_t now_ms);
int vx_tetris_command(VxTetris *t,const char *command);
int vx_tetris_move(VxTetris *t,int dx,int dy,int dz);
int vx_tetris_rotate(VxTetris *t,char axis,int direction);
unsigned vx_tetris_clear(VxTetris *t);
void vx_tetris_drop(VxTetris *t);
void vx_tetris_render(const VxTetris *t,uint8_t canvas[24][32][32]);
#endif
