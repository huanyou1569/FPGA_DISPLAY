/* Independent fixed-grid C implementation of Blockout mechanics.
 * References: msfefjiang/tetris3d (gameplay) and janmagura/AI_3D_BlocksGame
 * (integer axis rotations/layer clearing; MIT, copyright (c) 2026 JM).
 * See docs/third-party/AI_3D_BlocksGame-LICENSE.txt and tetris implementation log.
 * Z is vertical here. No browser/Three.js or snake state is used.
 */
#include "vx_tetris.h"
#include <string.h>
static const VxBlock shapes[VX_TPIECES][4]={
    {{0,0,0},{-1,0,0},{1,0,0},{2,0,0}}, // I
    {{0,0,0},{1,0,0},{0,1,0},{1,1,0}}, // O
    {{0,0,0},{-1,0,0},{1,0,0},{0,1,0}}, // T
    {{0,0,0},{-1,0,0},{0,1,0},{1,1,0}}, // S
    {{0,0,0},{1,0,0},{0,1,0},{-1,1,0}}, // Z
    {{0,0,0},{-1,0,0},{1,0,0},{1,1,0}}, // L
    {{0,0,0},{-1,0,0},{1,0,0},{-1,1,0}}, // J
    {{0,0,0},{1,0,0},{0,1,0},{0,0,1}}, // 3-axis corner
    {{0,0,0},{1,0,0},{1,1,0},{1,1,1}}, // 3D stair
    {{0,0,0},{1,0,0},{0,1,0},{0,1,1}}  // opposite stair
};
static uint32_t random32(VxTetris *t) {
    t->rng=t->rng*UINT32_C(1664525)+UINT32_C(1013904223); return t->rng;
}
static unsigned from_bag(VxTetris *t) {
    unsigned i,j; uint8_t a;
    if(!t->bag_left) {
        for(i=0;i<VX_TPIECES;++i) t->bag[i]=(uint8_t)i;
        for(i=VX_TPIECES-1;i>0;--i) {
            j=random32(t)%(i+1); a=t->bag[i]; t->bag[i]=t->bag[j]; t->bag[j]=a;
        }
        t->bag_left=VX_TPIECES;
    }
    return t->bag[--t->bag_left];
}
static int valid(const VxTetris *t,const VxBlock b[4],int px,int py,int pz) {
    unsigned i,j;
    for(i=0;i<4;++i) {
        int x=px+b[i].x,y=py+b[i].y,z=pz+b[i].z;
        if(x<0 || x>=VX_TW || y<0 || y>=VX_TD || z<0 || z>=VX_TH || t->well[z][y][x]) return 0;
        for(j=0;j<i;++j) if(b[i].x==b[j].x && b[i].y==b[j].y && b[i].z==b[j].z) return 0;
    }
    return 1;
}
static void high(VxTetris *t) { if(t->score>t->high_score) t->high_score=t->score; }
static void spawn(VxTetris *t) {
    unsigned i;
    int minx=9,maxx=-9,miny=9,maxy=-9,maxz=-9;
    t->type=t->next; t->next=(uint8_t)from_bag(t);
    memcpy(t->blocks,shapes[t->type],sizeof(t->blocks));
    for(i=0;i<4;++i) {
        if(t->blocks[i].x<minx) minx=t->blocks[i].x;
        if(t->blocks[i].x>maxx) maxx=t->blocks[i].x;
        if(t->blocks[i].y<miny) miny=t->blocks[i].y;
        if(t->blocks[i].y>maxy) maxy=t->blocks[i].y;
        if(t->blocks[i].z>maxz) maxz=t->blocks[i].z;
    }
    t->x=(int8_t)((VX_TW-(maxx-minx+1))/2-minx);
    t->y=(int8_t)((VX_TD-(maxy-miny+1))/2-miny);
    t->z=(int8_t)(VX_TH-1-maxz); t->elapsed=0;
    if(!valid(t,t->blocks,t->x,t->y,t->z)) { t->alive=0; high(t); }
}
void vx_tetris_init(VxTetris *t) { memset(t,0,sizeof(*t)); t->rng=UINT32_C(0x74337264); }
void vx_tetris_start(VxTetris *t) {
    memset(t->well,0,sizeof(t->well));
    t->score=t->planes=t->pieces=t->elapsed=0; t->paused=t->timed=t->bag_left=0; t->alive=1;
    t->next=(uint8_t)from_bag(t); spawn(t);
}
int vx_tetris_move(VxTetris *t,int dx,int dy,int dz) {
    if(!t->alive || t->paused || !valid(t,t->blocks,t->x+dx,t->y+dy,t->z+dz)) return 0;
    t->x=(int8_t)(t->x+dx); t->y=(int8_t)(t->y+dy); t->z=(int8_t)(t->z+dz); return 1;
}
int vx_tetris_rotate(VxTetris *t,char axis,int direction) {
    VxBlock b[4]; unsigned i,k;
    static const int8_t kicks[][3]={{0,0,0},{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{2,0,0},{-2,0,0},{0,2,0},{0,-2,0},{0,0,1}};
    if(!t->alive || t->paused || (direction!=1 && direction!=-1)) return 0;
    for(i=0;i<4;++i) {
        b[i]=t->blocks[i];
        switch(axis) {
        case 'X': b[i].y=(int8_t)(-direction*t->blocks[i].z); b[i].z=(int8_t)(direction*t->blocks[i].y); break;
        case 'Y': b[i].x=(int8_t)(direction*t->blocks[i].z); b[i].z=(int8_t)(-direction*t->blocks[i].x); break;
        case 'Z': b[i].x=(int8_t)(-direction*t->blocks[i].y); b[i].y=(int8_t)(direction*t->blocks[i].x); break;
        default:return 0;
        }
    }
    for(k=0;k<sizeof(kicks)/sizeof(kicks[0]);++k) {
        int x=t->x+kicks[k][0],y=t->y+kicks[k][1],z=t->z+kicks[k][2];
        if(valid(t,b,x,y,z)) {
            memcpy(t->blocks,b,sizeof(b)); t->x=(int8_t)x; t->y=(int8_t)y; t->z=(int8_t)z; return 1;
        }
    }
    return 0;
}
unsigned vx_tetris_clear(VxTetris *t) {
    unsigned read,write=0,x,y,n=0;
    for(read=0;read<VX_TH;++read) {
        int full=1;
        for(y=0;y<VX_TD;++y) for(x=0;x<VX_TW;++x) if(!t->well[read][y][x]) full=0;
        if(full) ++n;
        else { if(write!=read) memcpy(t->well[write],t->well[read],sizeof(t->well[0])); ++write; }
    }
    while(write<VX_TH) memset(t->well[write++],0,sizeof(t->well[0]));
    if(n) { t->score+=100u*n*n*(1u+t->planes/8u); t->planes+=n; high(t); }
    return n;
}
static void lock_piece(VxTetris *t) {
    unsigned i;
    if(!valid(t,t->blocks,t->x,t->y,t->z)) { t->alive=0; high(t); return; }
    for(i=0;i<4;++i) t->well[t->z+t->blocks[i].z][t->y+t->blocks[i].y][t->x+t->blocks[i].x]=(uint8_t)(1+t->type%6);
    ++t->pieces; vx_tetris_clear(t); spawn(t);
}
void vx_tetris_drop(VxTetris *t) {
    if(!t->alive || t->paused) return;
    while(vx_tetris_move(t,0,0,-1)) t->score+=2;
    high(t); lock_piece(t);
}
int vx_tetris_tick(VxTetris *t,uint32_t now_ms) {
    uint32_t delta,interval,level=t->planes/8u;
    if(!t->timed) { t->last_ms=now_ms; t->timed=1; return 0; }
    delta=now_ms-t->last_ms; t->last_ms=now_ms;
    if(!t->alive || t->paused) return 0;
    // One bounded gravity action per call. No pause/re-entry catch-up burst.
    interval=level>=12 ? 200u : 1400u-level*100u;
    if(delta>interval) delta=interval;
    t->elapsed+=delta;
    if(t->elapsed<interval) return 0;
    t->elapsed=0;
    if(!vx_tetris_move(t,0,0,-1)) lock_piece(t);
    return 1;
}
int vx_tetris_command(VxTetris *t,const char *s) {
    if(!strcmp(s,"TG")) { vx_tetris_start(t); return 1; }
    if(!strcmp(s,"TP")) { if(t->alive) { t->paused^=1; t->timed=0; } return 1; }
    if(!strcmp(s,"TH")) { vx_tetris_drop(t); return 1; }
    if(!strcmp(s,"TD")) {
        if(t->alive && !t->paused) { if(vx_tetris_move(t,0,0,-1)) { ++t->score; high(t); } else lock_piece(t); t->elapsed=0; }
        return 1;
    }
    if(!strcmp(s,"TL")) { vx_tetris_move(t,-1,0,0); return 1; }
    if(!strcmp(s,"TR")) { vx_tetris_move(t,1,0,0); return 1; }
    if(!strcmp(s,"TF")) { vx_tetris_move(t,0,-1,0); return 1; }
    if(!strcmp(s,"TB")) { vx_tetris_move(t,0,1,0); return 1; }
    if(strlen(s)==3 && s[0]=='T' && (s[1]=='X'||s[1]=='Y'||s[1]=='Z') && (s[2]=='+'||s[2]=='-')) {
        vx_tetris_rotate(t,s[1],s[2]=='+' ? 1 : -1); return 1;
    }
    return 0;
}
static void cube(uint8_t c[24][32][32],int x,int y,int z,uint8_t colour) {
    unsigned dx,dy,dz;
    for(dz=0;dz<2;++dz) for(dy=0;dy<2;++dy) for(dx=0;dx<2;++dx)
        if(x+(int)dx>=0 && x+(int)dx<32 && y+(int)dy>=0 && y+(int)dy<32 && z+(int)dz>=0 && z+(int)dz<24)
            c[z+dz][y+dy][x+dx]=colour;
}
void vx_tetris_render(const VxTetris *t,uint8_t c[24][32][32]) {
    int x,y,z,drop=0; unsigned i;
    memset(c,0,24u*32u*32u);
    // Sparse cyan well outline, leaving the interior visible in a volume.
    for(z=1;z<=22;++z) { c[z][9][9]=5; c[z][9][22]=5; c[z][22][9]=5; c[z][22][22]=5; }
    for(x=9;x<=22;++x) { c[1][9][x]=5; c[1][22][x]=5; c[22][9][x]=5; c[22][22][x]=5; }
    for(y=9;y<=22;++y) { c[1][y][9]=5; c[1][y][22]=5; c[22][y][9]=5; c[22][y][22]=5; }
    for(z=0;z<VX_TH;++z) for(y=0;y<VX_TD;++y) for(x=0;x<VX_TW;++x)
        if(t->well[z][y][x]) cube(c,10+x*2,10+y*2,2+z*2,t->well[z][y][x]);
    if(t->alive) {
        while(valid(t,t->blocks,t->x,t->y,t->z-drop-1)) ++drop;
        for(i=0;i<4;++i) {
            x=t->x+t->blocks[i].x; y=t->y+t->blocks[i].y; z=t->z-drop+t->blocks[i].z;
            if(drop) c[2+z*2][10+y*2][10+x*2]=3; // blue landing dot per cell
        }
        for(i=0;i<4;++i) cube(c,10+2*(t->x+t->blocks[i].x),10+2*(t->y+t->blocks[i].y),2+2*(t->z+t->blocks[i].z),4);
    }
    // Next-piece preview to the right of the well; normalized to fit 32x32x24.
    { int minx=9,miny=9,minz=9;
      for(i=0;i<4;++i) { if(shapes[t->next][i].x<minx) minx=shapes[t->next][i].x;
        if(shapes[t->next][i].y<miny) miny=shapes[t->next][i].y;
        if(shapes[t->next][i].z<minz) minz=shapes[t->next][i].z; }
      for(i=0;i<4;++i) cube(c,24+2*(shapes[t->next][i].x-minx),10+2*(shapes[t->next][i].y-miny),18+2*(shapes[t->next][i].z-minz),6);
    }
}
