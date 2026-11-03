/* Deterministic differential trace for the three existing modes. */
#include "vx_brush.h"
#include <stdio.h>
static VxBrush b;
static VxBrushSnapshot picture;
static unsigned hash(const void *p,size_t size) {
    const unsigned char *c=p;unsigned h=2166136261u;
    while(size--) { h^=*c++; h*=16777619u; } return h;
}
int main(void) {
    static const char *commands[]={"BRUSH","JP","JR","JU","JK","CLEAR","JB1","JD","JB0","JH25","SNAKE","JG","JL","JR","JU","JD","STATUS","DEMO"};
    unsigned i,rng=42;char out[512];
    vx_brush_init(&b);
    for(i=0;i<3000;++i) {
        rng=rng*1664525u+1013904223u;
        vx_brush_tick(&b,i);
        vx_brush_command(&b,commands[(rng>>16)%(sizeof(commands)/sizeof(commands[0]))],out,sizeof(out));
        vx_brush_snapshot(&b,&picture);
        printf("%u %u %u %u %u %08x %08x %08x\n",i,(unsigned)b.mode,b.revision,(unsigned)b.x,(unsigned)b.snake.length,
            hash(&b.snake,sizeof(b.snake)),hash(&picture,sizeof(picture)),hash(out,__builtin_strlen(out)));
    }
    return 0;
}
