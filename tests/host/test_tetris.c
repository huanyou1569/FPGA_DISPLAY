#include "vx_brush.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#undef assert
static void fail(const char *message,int line) { fprintf(stderr,"FAIL line %d: %s\n",line,message); fflush(stderr); exit(1); }
#define assert(x) ((x) ? (void)0 : fail(#x,__LINE__))
static VxBrush scene;
static VxBrushSnapshot snap;
static VxTetris t;
static void horizontal_i(void) {
    vx_tetris_init(&t); vx_tetris_start(&t);
    t.blocks[0]=(VxBlock){0,0,0}; t.blocks[1]=(VxBlock){1,0,0};
    t.blocks[2]=(VxBlock){2,0,0}; t.blocks[3]=(VxBlock){3,0,0};
    t.x=0;t.y=0;t.z=5;
}
static void rotations_bag_and_boundaries(void) {
    unsigned seen=0,i,j,axis;
    vx_tetris_init(&t); vx_tetris_start(&t);
    for(i=0;i<VX_TPIECES;++i) {
        VxBlock before[4];
        assert(t.alive && !(seen&(1u<<t.type))); seen|=1u<<t.type;
        t.x=2;t.y=2;t.z=5;
        memcpy(before,t.blocks,sizeof(before));
        for(axis=0;axis<3;++axis) {
            for(j=0;j<4;++j) assert(vx_tetris_rotate(&t,"XYZ"[axis],1));
            assert(!memcmp(before,t.blocks,sizeof(before)) && t.x==2 && t.y==2 && t.z==5);
            assert(vx_tetris_rotate(&t,"XYZ"[axis],1));
            assert(vx_tetris_rotate(&t,"XYZ"[axis],-1));
            assert(!memcmp(before,t.blocks,sizeof(before)));
        }
        vx_tetris_drop(&t); memset(t.well,0,sizeof(t.well));
    }
    assert(seen==(1u<<VX_TPIECES)-1);
    horizontal_i();
    assert(!vx_tetris_move(&t,-1,0,0));
    assert(!vx_tetris_move(&t,0,-1,0));
    t.well[5][0][4]=1; assert(!vx_tetris_move(&t,1,0,0));
    t.y=2;t.x=1;
    assert(vx_tetris_rotate(&t,'Z',1)); // fits after rotation
    assert(vx_tetris_rotate(&t,'Z',1)); // horizontal negative X: wall kick
    for(i=0;i<4;++i) assert(t.x+t.blocks[i].x>=0);
    memset(t.well,1,sizeof(t.well));
    { VxBlock old[4]; memcpy(old,t.blocks,sizeof(old));
      assert(!vx_tetris_rotate(&t,'X',1)); assert(!memcmp(old,t.blocks,sizeof(old))); }
}
static void layer_compaction(void) {
    unsigned z,x,y;
    vx_tetris_init(&t); vx_tetris_start(&t);
    memset(t.well[0],1,sizeof(t.well[0]));
    memset(t.well[1],2,sizeof(t.well[1]));
    t.well[2][3][4]=6; t.well[4][2][1]=5;
    assert(vx_tetris_clear(&t)==2);
    assert(t.well[0][3][4]==6 && t.well[2][2][1]==5 && t.planes==2 && t.score==400);
    for(z=8;z<10;++z) for(y=0;y<6;++y) for(x=0;x<6;++x) assert(!t.well[z][y][x]);
    assert(vx_tetris_clear(&t)==0);
    memset(t.well,1,sizeof(t.well));
    assert(vx_tetris_clear(&t)==10);
    for(z=0;z<10;++z) for(y=0;y<6;++y) for(x=0;x<6;++x) assert(!t.well[z][y][x]);
}
static void gravity_pause_drop_and_gameover(void) {
    horizontal_i();
    assert(!vx_tetris_tick(&t,100)); assert(!vx_tetris_tick(&t,1499));
    assert(vx_tetris_tick(&t,1500) && t.z==4);
    assert(vx_tetris_command(&t,"TP") && t.paused);
    vx_tetris_tick(&t,100000); assert(t.z==4);
    vx_tetris_command(&t,"TP");
    assert(!vx_tetris_tick(&t,100001) && t.z==4);
    assert(!vx_tetris_tick(&t,101400)); assert(vx_tetris_tick(&t,101401) && t.z==3);
    t.last_ms=UINT32_MAX-100;t.elapsed=0;
    assert(!vx_tetris_tick(&t,100) && t.elapsed==201);
    vx_tetris_drop(&t); assert(t.pieces==1 && t.score==6 && t.high_score==6);
    assert(t.well[0][0][0] && t.well[0][0][3]);
    // Fill only spawn region; lock a valid piece below to trigger next-spawn top-out.
    horizontal_i(); t.z=0;
    memset(t.well[9],1,sizeof(t.well[9])); memset(t.well[8],1,sizeof(t.well[8]));
    // leave holes so complete layers cannot clear during lock
    t.well[9][0][0]=0;t.well[8][0][0]=0;
    vx_tetris_drop(&t); assert(!t.alive);
    { uint32_t pieces=t.pieces; vx_tetris_drop(&t); vx_tetris_tick(&t,500000); assert(t.pieces==pieces); }
    vx_tetris_command(&t,"TG"); assert(t.alive && !t.paused && !t.score && !t.planes);
}
static void rendering_protocol_and_snake_isolation(void) {
    char out[512]; VxSnake saved; uint8_t canvas[sizeof(scene.canvas)];
    vx_brush_init(&scene);
    vx_brush_command(&scene,"BRUSH",out,sizeof(out)); vx_brush_command(&scene,"JP",out,sizeof(out));
    memcpy(canvas,scene.canvas,sizeof(canvas));
    vx_brush_command(&scene,"SNAKE",out,sizeof(out)); saved=scene.snake;
    vx_brush_command(&scene,"TETRIS",out,sizeof(out));
    assert(scene.mode==3 && scene.mode_request==3);
    vx_brush_snapshot(&scene,&snap);
    assert(!snap.cursor_visible && snap.canvas[1][9][9]==5);
    assert(vx_tetris_command(&scene.tetris,"TX+"));
    vx_brush_command(&scene,"TH",out,sizeof(out)); assert(!strcmp(out,"OK\n"));
    vx_brush_command(&scene,"STATUS",out,sizeof(out)); assert(strstr(out,"MODE:TETRIS") && strstr(out,"PLANES:") && strstr(out,"STATE:PLAY"));
    assert(!memcmp(&saved,&scene.snake,sizeof(saved)) && !memcmp(canvas,scene.canvas,sizeof(canvas)));
    vx_brush_command(&scene,"BRUSH",out,sizeof(out)); assert(!memcmp(canvas,scene.canvas,sizeof(canvas)));
    // Repeated render and command sequence with buffer canaries catches out-of-range cell drawing.
    { static struct { uint32_t a; uint8_t c[24][32][32]; uint32_t b; } g;
      unsigned i; g.a=0x12345678;g.b=0xabcdef01;
      for(i=0;i<500;++i) {
          if(!t.alive) vx_tetris_start(&t);
          vx_tetris_rotate(&t,"XYZ"[i%3],(i&1)?1:-1);
          vx_tetris_move(&t,(int)(i%3)-1,(int)((i/3)%3)-1,0);
          vx_tetris_render(&t,g.c); vx_tetris_drop(&t);
          assert(g.a==0x12345678 && g.b==0xabcdef01);
      } }
}
int main(void) {
    rotations_bag_and_boundaries(); layer_compaction(); gravity_pause_drop_and_gameover(); rendering_protocol_and_snake_isolation();
    puts("TEST_PASS tetris_host: 10-bag, 3-axis rotations/inverses, wall kicks/collision, multi-layer compaction, gravity/pause/wrap, drop/score/top-out/restart, render guards, snake/brush isolation");
    return 0;
}
