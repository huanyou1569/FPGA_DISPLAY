#include "vx_brush.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static VxBrush b;
static VxBrushSnapshot picture;
static char replies[4096];
static size_t used;
static void receive(void *unused,const char *data,size_t size) {
    (void)unused;
    assert(used+size<sizeof(replies));
    memcpy(replies+used,data,size); used+=size; replies[used]=0;
}
static void cmd(const char *line) {
    char out[512];
    vx_brush_command(&b,line,out,sizeof(out));
    assert(!strcmp(out,"OK\n"));
}
static void one_segment(VxSnake *s,int x,int y,int z,unsigned dir) {
    vx_snake_init(s); vx_snake_start(s,0,0);
    s->length=1; s->food_count=0; s->body[0]=(VxSegment){x,y,z}; s->dir=(uint8_t)dir;
}
static void turns_and_wrap(void) {
    static const uint8_t expected[6][4]={{2,3,4,5},{3,2,4,5},{1,0,4,5},
        {0,1,4,5},{2,3,0,1},{2,3,1,0}};
    const char *ops="LRUD";
    VxSnake s;
    unsigned dir,op;
    for(dir=0;dir<6;++dir) for(op=0;op<4;++op) {
        one_segment(&s,16,16,12,dir);
        vx_snake_turn(&s,ops[op]); assert(s.dir==expected[dir][op]);
        vx_snake_turn(&s,ops[op]); assert(s.dir==expected[dir][op]); // no second turn/reversal before a step
    }
    one_segment(&s,30,16,12,VX_PX);
    assert(!vx_snake_tick(&s,1) && s.body[0].x==30);
    assert(vx_snake_tick(&s,2) && s.body[0].x==0);
    one_segment(&s,0,16,12,VX_NX); vx_snake_tick(&s,2); assert(s.body[0].x==30);
    one_segment(&s,16,30,12,VX_PY); vx_snake_tick(&s,2); assert(s.body[0].y==0);
    one_segment(&s,16,0,12,VX_NY); vx_snake_tick(&s,2); assert(s.body[0].y==30);
    one_segment(&s,16,16,22,VX_PZ); vx_snake_tick(&s,2); assert(s.body[0].z==0);
    one_segment(&s,16,16,0,VX_NZ); vx_snake_tick(&s,2); assert(s.body[0].z==22);
    s.last_revolution=UINT32_MAX; s.step_counter=1;
    assert(vx_snake_tick(&s,0)); // wrap-around counter delta is one
}
static void food_death_and_capacity(void) {
    struct { unsigned before; VxSnake s; unsigned after; } guarded={0};
    VxSnake *s=&guarded.s;
    unsigned i;
    guarded.before=0x12345678; guarded.after=0xabcdef01;
    one_segment(s,16,16,12,VX_PX);
    s->food_count=1; s->food[0]=(VxSegment){18,16,12};
    vx_snake_tick(s,2);
    assert(s->length==2 && s->score==1 && s->high_score==1 && s->food_count>=5);
    s->length=4; s->body[0]=(VxSegment){16,16,12};
    s->body[1]=(VxSegment){18,16,12}; s->body[2]=(VxSegment){20,16,12}; s->body[3]=(VxSegment){22,16,12};
    vx_snake_tick(s,4); assert(!s->alive && s->collisions==1);
    assert(!vx_snake_tick(s,100) && !s->alive && s->body[0].x==16);
    vx_snake_start(s,100,1); assert(s->alive && s->length==5 && s->score==0 && s->high_score==1);
    vx_snake_tick(s,101); assert(s->steps==1); // restart first move at next revolution
    // Capacity guard: an eaten food at full length scores but never writes body[200].
    one_segment(s,0,0,0,VX_PX);
    s->length=VX_SNAKE_MAX;
    for(i=1;i<VX_SNAKE_MAX;++i) s->body[i]=(VxSegment){(int16_t)((i%16)*2),(int16_t)(2+(i/16)*2),2};
    s->food_count=1; s->food[0]=(VxSegment){2,0,0};
    vx_snake_tick(s,2);
    assert(s->alive && s->length==200 && s->score==1);
    assert(guarded.before==0x12345678 && guarded.after==0xabcdef01);
    // Rendering clips a food at the edge, and head overwrites body with yellow.
    s->food_count=1; s->food[0]=(VxSegment){31,31,23};
    vx_snake_render(s,picture.canvas);
    assert(picture.canvas[23][31][31]==1 && picture.canvas[0][0][2]==4);
}
static void modes_and_protocol(void) {
    VxProtocol p={0};
    const char *wire="SNAKE\r\nSTATUS\nJG\nJL\nJU\nSTATUS\nJE\nBRUSH\n";
    size_t i;
    uint32_t rgb[3];
    vx_brush_init(&b); cmd("BRUSH"); cmd("JP");
    assert(b.canvas[12][16][16]==1);
    cmd("SNAKE"); assert(b.mode==VX_SNAKE && !b.active && b.snake.length==5);
    assert(b.snake.food_count==10);
    for(i=0;i<3;++i) assert(b.snake.food[i].z>=10 && b.snake.food[i].z<=14);
    vx_brush_snapshot(&b,&picture);
    assert(!picture.cursor_visible && picture.canvas[12][16][16]==4);
    vx_brush_pack_row(&picture,12*32+16,rgb);
    assert((rgb[0]&(1u<<16)) && (rgb[1]&(1u<<16)) && !(rgb[2]&(1u<<16)));
    vx_brush_tick(&b,1); assert(b.snake.steps==0);
    vx_brush_tick(&b,2); assert(b.snake.steps==1 && b.snake.body[0].x==18);
    cmd("BRUSH"); assert(b.canvas[12][16][16]==1 && b.mode==VX_BRUSH && !b.drawing);
    used=0;
    for(i=0;i<strlen(wire);++i) vx_protocol_feed(&p,&b,(const uint8_t*)wire+i,1,receive,0);
    assert(!strstr(replies,"ERR") && strstr(replies,"MODE:SNAKE") && strstr(replies,"STATE:PLAY"));
    assert(b.mode==VX_BRUSH && b.canvas[12][16][16]==1);
    // A mode change baselines the revolution counter before stepping; no hidden fast-forward.
    b.revolution=500; vx_brush_set_mode(&b,VX_SNAKE); vx_brush_tick(&b,500);
    assert(!b.snake.steps);
    printf("TEST_PASS snake_host: 24 turns, 6 wrap directions, 2-turn cadence, food/growth, collision/death, restart/high-score, capacity guards, render packing, mode/brush preservation, split protocol\n");
}
int main(void) { turns_and_wrap(); food_death_and_capacity(); modes_and_protocol(); return 0; }
