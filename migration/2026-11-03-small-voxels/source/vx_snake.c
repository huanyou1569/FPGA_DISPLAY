/* Port of reference Core/user_code/snake_game.c game rules.
 * STM32 HAL, WS2812 and 50+50 phase expansion are replaced by the PL canvas.
 * Unsigned RNG, bounded body growth, safe food placement and frozen DEAD state.
 */
#include "vx_snake.h"
#include <stdlib.h>
#include <string.h>

static const int8_t vectors[6][3]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
static const uint8_t turns[6][4]={
    {VX_PY,VX_NY,VX_PZ,VX_NZ},{VX_NY,VX_PY,VX_PZ,VX_NZ},
    {VX_NX,VX_PX,VX_PZ,VX_NZ},{VX_PX,VX_NX,VX_PZ,VX_NZ},
    {VX_PY,VX_NY,VX_PX,VX_NX},{VX_PY,VX_NY,VX_NX,VX_PX}};
static int overlaps(VxSegment a, VxSegment b) {
    return abs(a.x-b.x)<2 && abs(a.y-b.y)<2 && abs(a.z-b.z)<2;
}
static unsigned random15(VxSnake *s) {
    s->rng=s->rng*UINT32_C(1103515245)+UINT32_C(12345);
    return (unsigned)((s->rng>>16)&0x7fffu);
}
static int food_free(const VxSnake *s, VxSegment p) {
    unsigned i;
    for(i=0;i<s->length;++i) if(overlaps(p,s->body[i])) return 0;
    for(i=0;i<s->food_count;++i) if(overlaps(p,s->food[i])) return 0;
    return 1;
}
static int spawn(VxSnake *s, int prefer_xy) {
    unsigned attempt,x,y,z;
    VxSegment p;
    if(s->food_count>=VX_FOOD_MAX) return 0;
    for(attempt=0;attempt<1000;++attempt) {
        p.x=(int16_t)(random15(s)%32); p.y=(int16_t)(random15(s)%32);
        p.z=(int16_t)((prefer_xy && attempt<500) ? 10+random15(s)%5 : random15(s)%24);
        if(food_free(s,p)) { s->food[s->food_count++]=p; return 1; }
    }
    // Deterministic search replaces the original overlap-prone random fallback.
    for(z=0;z<24;z+=2) for(y=0;y<32;y+=2) for(x=0;x<32;x+=2) {
        p.x=(int16_t)x; p.y=(int16_t)y; p.z=(int16_t)z;
        if(food_free(s,p)) { s->food[s->food_count++]=p; return 1; }
    }
    return 0;
}
void vx_snake_init(VxSnake *s) { memset(s,0,sizeof(*s)); s->rng=12345; }
void vx_snake_start(VxSnake *s, uint32_t revolution, int immediate) {
    unsigned i;
    s->length=5; s->score=0; s->alive=1; s->dir=VX_PX;
    s->food_count=0; s->steps=0; s->collisions=0; s->turned=0;
    s->step_counter=(uint8_t)(immediate ? 1 : 0); s->last_revolution=revolution;
    for(i=0;i<5;++i) { s->body[i].x=(int16_t)(16-i); s->body[i].y=16; s->body[i].z=12; }
    for(i=0;i<VX_FOOD_MAX;++i) if(!spawn(s,i<3)) break;
}
void vx_snake_turn(VxSnake *s, char command) {
    unsigned op;
    if(!s->alive || s->turned) return; // one accepted turn per step; key repeats cannot reverse through two turns
    switch(command) { case 'L':op=0;break; case 'R':op=1;break; case 'U':op=2;break; case 'D':op=3;break; default:return; }
    s->dir=turns[s->dir][op]; s->turned=1;
}
static void step(VxSnake *s) {
    VxSegment head=s->body[0];
    unsigned i,food_index=s->food_count;
    int grow;
    head.x=(int16_t)((head.x+vectors[s->dir][0]*2+32)%32);
    head.y=(int16_t)((head.y+vectors[s->dir][1]*2+32)%32);
    head.z=(int16_t)((head.z+vectors[s->dir][2]*2+24)%24);
    // Match the reference: ignore the old head and vacating tail for collision.
    for(i=1;i+1<s->length;++i) if(overlaps(head,s->body[i])) {
        s->alive=0; ++s->collisions;
        if(s->score>s->high_score) s->high_score=s->score;
        return;
    }
    for(i=0;i<s->food_count;++i) if(overlaps(head,s->food[i])) { food_index=i; break; }
    grow=food_index<s->food_count && s->length<VX_SNAKE_MAX;
    if(grow) ++s->length;
    for(i=s->length-1;i>0;--i) s->body[i]=s->body[i-1];
    s->body[0]=head;
    if(food_index<s->food_count) {
        s->food[food_index]=s->food[--s->food_count];
        ++s->score;
        if(s->score>s->high_score) s->high_score=s->score;
    }
    while(s->food_count<5) if(!spawn(s,0)) break;
    s->turned=0; ++s->steps;
}
int vx_snake_tick(VxSnake *s, uint32_t revolution) {
    uint32_t elapsed=revolution-s->last_revolution;
    int changed=0;
    s->last_revolution=revolution;
    // Bound catch-up after a delayed main loop. Normal polling sees 0 or 1 turn.
    if(elapsed>8) elapsed=8;
    while(elapsed-- && s->alive) {
        if(++s->step_counter>=2) { s->step_counter=0; step(s); changed=1; }
    }
    return changed;
}
static void box(uint8_t canvas[24][32][32], VxSegment p, uint8_t colour) {
    // One canvas voxel maps to about 3 PL voxels per axis (8/3 scale).
    if(p.x>=0 && p.x<32 && p.y>=0 && p.y<32 && p.z>=0 && p.z<24)
        canvas[p.z][p.y][p.x]=colour;
}
void vx_snake_render(const VxSnake *s, uint8_t canvas[24][32][32]) {
    unsigned i;
    memset(canvas,0,24u*32u*32u);
    for(i=0;i<s->food_count;++i) box(canvas,s->food[i],1); // palette red
    for(i=1;i<s->length;++i) box(canvas,s->body[i],2); // green
    if(s->length) box(canvas,s->body[0],4); // yellow, including DEAD final frame
}
