/* Port of VX-Display brush_mode.c business rules. STM32 timer/WS2812/DMA
 * rendering is replaced by a packed RGB111 snapshot for the FPGA filler.
 * Source: VX-Display-main/vx-display/Core/user_code/{brush_mode,volume_math}.c
 */
#include "vx_brush.h"
#include <stdio.h>
#include <string.h>

static const uint8_t palette[6] = {4,2,1,6,3,5}; /* RGB, yellow, cyan, magenta */
static const int16_t sin100[100] = {
    0,2057,4107,6140,8149,10126,12062,13952,15786,17557,
    19260,20886,22431,23886,25247,26509,27666,28714,29648,30466,
    31163,31738,32187,32509,32702,32767,32702,32509,32187,31738,
    31163,30466,29648,28714,27666,26509,25247,23886,22431,20886,
    19260,17557,15786,13952,12062,10126,8149,6140,4107,2057,
    0,-2057,-4107,-6140,-8149,-10126,-12062,-13952,-15786,-17557,
    -19260,-20886,-22431,-23886,-25247,-26509,-27666,-28714,-29648,-30466,
    -31163,-31738,-32187,-32509,-32702,-32767,-32702,-32509,-32187,-31738,
    -31163,-30466,-29648,-28714,-27666,-26509,-25247,-23886,-22431,-20886,
    -19260,-17557,-15786,-13952,-12062,-10126,-8149,-6140,-4107,-2057
};
static size_t text(char *out, size_t capacity, const char *s) {
    int n;
    if (!capacity) return 0;
    n=snprintf(out,capacity,"%s",s);
    return n < 0 ? 0 : ((size_t)n < capacity ? (size_t)n : capacity-1);
}
void vx_brush_init(VxBrush *b) {
    memset(b,0,sizeof(*b));
    b->x=16; b->y=16; b->z=12; b->angle=51;
    b->revision=1; b->mode_request=-1;
    vx_snake_init(&b->snake);
    vx_tetris_init(&b->tetris);
}
void vx_brush_set_active(VxBrush *b, int active) {
    vx_brush_set_mode(b,active ? VX_BRUSH : VX_DEMO);
}
const char *vx_mode_name(unsigned mode) {
    if(mode==VX_TETRIS) return "TETRIS";
    return mode==VX_BRUSH ? "BRUSH" : (mode==VX_SNAKE ? "SNAKE" : "DEMO");
}
void vx_brush_set_mode(VxBrush *b, unsigned mode) {
    if(mode>VX_TETRIS) return;
    if (b->mode != mode) {
        b->mode=(uint8_t)mode;
        b->active=(uint8_t)(mode==VX_BRUSH);
        b->drawing=0; b->held=0; /* enter with pen lifted, matching the PC UI */
        if(mode==VX_SNAKE) vx_snake_start(&b->snake,b->revolution,0);
        if(mode==VX_TETRIS) vx_tetris_start(&b->tetris);
        ++b->revision;
    }
}
void vx_brush_tick(VxBrush *b, uint32_t revolution) {
    uint8_t blink=(uint8_t)(revolution & 3u);
    b->revolution=revolution;
    if(b->mode==VX_SNAKE && vx_snake_tick(&b->snake,revolution)) ++b->revision;
    if (b->blink != blink) {
        b->blink=blink;
        if (b->active) ++b->revision;
    }
}
static void stamp(VxBrush *b) {
    // One canvas voxel displays as about 3 PL voxels per axis (8/3 scale).
    uint8_t *p=&b->canvas[b->z][b->y][b->x];
    if(!*p) { *p=(uint8_t)(b->colour+1); ++b->voxels; }
}
static int direction(int q15) { return q15>16384 ? 1 : (q15 < -16384 ? -1 : 0); }
static uint8_t step(uint8_t v, int delta, unsigned dimension) {
    int next=(int)v+delta;
    return (uint8_t)(next<0 ? 0 : ((unsigned)next>dimension-2 ? dimension-2 : (unsigned)next));
}
static void move(VxBrush *b, char command) {
    int cv=sin100[(b->angle+25)%100], sv=sin100[b->angle];
    int dx=0,dy=0,dz=0;
    if(b->held && (command=='U' || command=='D')) dz=command=='U' ? 1 : -1;
    else if(command=='L' || command=='R') {
        dx=direction(sv); dy=direction(cv);
        if(command=='R') { dx=-dx; dy=-dy; }
    } else {
        dx=direction(cv); dy=direction(-sv);
        if(command=='D') { dx=-dx; dy=-dy; }
    }
    b->x=step(b->x,dx,VX_X); b->y=step(b->y,dy,VX_Y); b->z=step(b->z,dz,VX_Z);
    if(b->drawing) stamp(b);
    ++b->revision;
}
void vx_brush_snapshot(const VxBrush *b, VxBrushSnapshot *s) {
    if(b->mode==VX_TETRIS) {
        vx_tetris_render(&b->tetris,s->canvas);
        s->x=s->y=s->z=s->colour=s->drawing=s->cursor_visible=0;
        return;
    }
    if(b->mode==VX_SNAKE) {
        vx_snake_render(&b->snake,s->canvas);
        s->x=s->y=s->z=s->colour=s->drawing=s->cursor_visible=0;
        return;
    }
    memcpy(s->canvas,b->canvas,sizeof(s->canvas));
    s->x=b->x; s->y=b->y; s->z=b->z; s->colour=b->colour;
    s->drawing=b->drawing;
    s->cursor_visible=(uint8_t)(b->active && (b->drawing || b->blink<2));
}
void vx_brush_pack_row(const VxBrushSnapshot *s, unsigned row, uint32_t rgb[3]) {
    unsigned x,y,z;
    rgb[0]=rgb[1]=rgb[2]=0;
    if(row>=VX_ROWS) return;
    y=row%VX_Y; z=row/VX_Y;
    for(x=0;x<VX_X;++x) {
        uint8_t ci=s->canvas[z][y][x];
        unsigned colour=(ci>0 && ci<=6) ? palette[ci-1] : 0;
        if(s->cursor_visible && x==s->x && y==s->y && z==s->z)
            colour=s->drawing ? palette[s->colour] : 7;
        if(colour&4) rgb[0] |= UINT32_C(1)<<x;
        if(colour&2) rgb[1] |= UINT32_C(1)<<x;
        if(colour&1) rgb[2] |= UINT32_C(1)<<x;
    }
}
size_t vx_brush_status(const VxBrush *b, char *out, size_t capacity) {
    int n;
    if(!capacity) return 0;
    n=snprintf(out,capacity,
        "RPM:%lu DLY:%lu F:0 S:0 MODE:%s BX:%u BY:%u BZ:%u A:%u CL:%u BTN:%u DR:%u SWP:%lu VOX:%lu TARGET_RPS:%u SLICES:%u\n",
        (unsigned long)b->rpm,(unsigned long)b->phase_us,vx_mode_name(b->mode),
        (unsigned)b->x,(unsigned)b->y,(unsigned)b->z,(unsigned)b->angle,
        (unsigned)b->colour,(unsigned)b->held,(unsigned)b->drawing,
        (unsigned long)b->uploaded_frames,(unsigned long)b->voxels,
        (unsigned)VX_TARGET_RPS,(unsigned)VX_ANGLE_SLICES);
    if(n>=0 && (size_t)n<capacity && b->mode==VX_TETRIS) {
        size_t used=(size_t)n;
        if(used && out[used-1]=='\n') --used;
        n=snprintf(out+used,capacity-used,
            " SCORE:%lu HIGH:%lu STATE:%s PLANES:%lu LEVEL:%lu PIECE:%u NEXT:%u BLOCKS:%lu\n",
            (unsigned long)b->tetris.score,(unsigned long)b->tetris.high_score,
            !b->tetris.alive ? "OVER" : (b->tetris.paused ? "PAUSE" : "PLAY"),
            (unsigned long)b->tetris.planes,(unsigned long)(1+b->tetris.planes/8),
            (unsigned)b->tetris.type,(unsigned)b->tetris.next,(unsigned long)b->tetris.pieces);
        return n<0 ? used : (used+(size_t)n<capacity ? used+(size_t)n : capacity-1);
    }
    if(n>=0 && (size_t)n<capacity && b->mode==VX_SNAKE) {
        size_t used=(size_t)n;
        if(used && out[used-1]=='\n') --used;
        n=snprintf(out+used,capacity-used,
            " SCORE:%u HIGH:%u STATE:%s LEN:%u DIR:%u H:(%d,%d,%d) SP:%lu\n",
            (unsigned)b->snake.score,(unsigned)b->snake.high_score,b->snake.alive ? "PLAY" : "DEAD",
            (unsigned)b->snake.length,(unsigned)b->snake.dir,
            b->snake.body[0].x,b->snake.body[0].y,b->snake.body[0].z,(unsigned long)b->snake.steps);
        return n<0 ? used : (used+(size_t)n<capacity ? used+(size_t)n : capacity-1);
    }
    return n<0 ? 0 : ((size_t)n<capacity ? (size_t)n : capacity-1);
}
size_t vx_brush_command(VxBrush *b, const char *command, char *out, size_t capacity) {
    if(*command==':') ++command;
    if(!strcmp(command,"STATUS")) return vx_brush_status(b,out,capacity);
    if(!strcmp(command,"TETRIS")) {
        vx_brush_set_mode(b,VX_TETRIS); b->mode_request=VX_TETRIS;
        return text(out,capacity,"OK\n");
    }
    if(b->mode==VX_TETRIS && command[0]=='T') {
        if(!vx_tetris_command(&b->tetris,command)) return text(out,capacity,"ERR:COMMAND\n");
        ++b->revision; return text(out,capacity,"OK\n");
    }
    if(!strcmp(command,"SNAKE")) {
        vx_brush_set_mode(b,VX_SNAKE); b->mode_request=VX_SNAKE;
        return text(out,capacity,"OK\n");
    }
    if(!strcmp(command,"BRUSH")) {
        vx_brush_set_active(b,1); b->drawing=0; b->held=0;
        b->mode_request=1; ++b->revision;
        return text(out,capacity,"OK\n");
    }
    if(!strcmp(command,"CLEAR")) {
        if(b->mode==VX_SNAKE || b->mode==VX_TETRIS) return text(out,capacity,"ERR:MODE\n");
        memset(b->canvas,0,sizeof(b->canvas)); b->voxels=0;
        if(b->active && b->drawing) stamp(b);
        ++b->revision;
        return text(out,capacity,"OK\n");
    }
    if(!strcmp(command,"JE") || !strcmp(command,"DEMO")) {
        vx_brush_set_active(b,0); b->mode_request=0;
        return text(out,capacity,"OK\n");
    }
    if(command[0]!='J') return text(out,capacity,"ERR:UNSUPPORTED\n");
    if(b->mode==VX_SNAKE) {
        if(!strcmp(command,"JG")) {
            vx_snake_start(&b->snake,b->revolution,1); ++b->revision;
        } else if(strlen(command)==2 && strchr("LRUD",command[1])) {
            vx_snake_turn(&b->snake,command[1]);
        } else if(!strcmp(command,"JB0")) { /* harmless PC modifier release */ }
        else return text(out,capacity,"ERR:MODE\n");
        return text(out,capacity,"OK\n");
    }
    if(!b->active) return text(out,capacity,"ERR:MODE\n");
    if(command[1]=='H' && command[2]) {
        unsigned angle=0;
        const char *p=command+2;
        for(;*p;++p) {
            if(*p<'0'||*p>'9') return text(out,capacity,"ERR:ANGLE\n");
            angle=(angle*10u+(unsigned)(*p-'0'))%100u;
        }
        b->angle=(uint8_t)angle;
    } else if(!strcmp(command,"JB0") || !strcmp(command,"JB1")) {
        b->held=(uint8_t)(command[2]-'0');
    } else if(strlen(command)==2) {
        switch(command[1]) {
        case 'U': case 'D': case 'L': case 'R': move(b,command[1]); break;
        // The unmodified PC sends J+ for D until its own B key was pressed.
        // This alias makes physical BTN2 entry usable with that same PC UI.
        case '+': move(b,'R'); break;
        case '-': move(b,'L'); break;
        case 'P': b->drawing^=1; if(b->drawing) stamp(b); ++b->revision; break;
        case 'K': b->colour=(uint8_t)((b->colour+1)%6); ++b->revision; break;
        default: return text(out,capacity,"ERR:UNSUPPORTED\n");
        }
    } else return text(out,capacity,"ERR:COMMAND\n");
    return text(out,capacity,"OK\n");
}
void vx_protocol_feed(VxProtocol *p, VxBrush *b, const uint8_t *data, size_t size,
                      VxReply reply, void *context) {
    size_t i;
    for(i=0;i<size;++i) {
        unsigned char c=data[i];
        if(c=='\r') continue;
        if(c=='\n') {
            char response[512];
            size_t n;
            if(p->discard) n=text(response,sizeof(response),"ERR:LINE\n");
            else {
                char *start=p->line;
                while(p->length && (p->line[p->length-1]==' ' || p->line[p->length-1]=='\t')) --p->length;
                p->line[p->length]=0;
                while(*start==' ' || *start=='\t') ++start;
                n=*start ? vx_brush_command(b,start,response,sizeof(response)) : 0;
            }
            if(n && reply) reply(context,response,n);
            p->length=0; p->discard=0;
        } else if(!p->discard) {
            if((c<32 && c!='\t') || c>126 || p->length>=VX_LINE_MAX-1) p->discard=1;
            else p->line[p->length++]=(char)c;
        }
    }
}
