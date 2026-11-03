#include "vx_brush.h"
#include "vx_upload.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static VxBrush b;
static VxBrushSnapshot snapshot;
static VxUploader upload;
static char replies[8192];
static size_t reply_size;
static void reply(void *context,const char *data,size_t size) {
    (void)context;
    assert(reply_size+size<sizeof(replies));
    memcpy(replies+reply_size,data,size); reply_size+=size; replies[reply_size]=0;
}
static void command(const char *s) {
    char out[256];
    size_t n=vx_brush_command(&b,s,out,sizeof(out));
    assert(n>0 && !strcmp(out,"OK\n"));
}
static int sign_threshold(double v) { return v>0.5 ? 1 : (v < -0.5 ? -1 : 0); }
static void movement(void) {
    unsigned angle,held,i;
    const char *commands[]={"JL","JR","JU","JD"};
    for(angle=0;angle<100;++angle) for(held=0;held<2;++held) for(i=0;i<4;++i) {
        double theta=angle*6.2831853071795864769/100;
        int dx,dy,dz=0;
        vx_brush_init(&b); vx_brush_set_active(&b,1);
        b.angle=(uint8_t)angle; b.held=(uint8_t)held;
        if(held && i>=2) { dx=dy=0; dz=i==2 ? 1 : -1; }
        else if(i<2) { dx=sign_threshold(sin(theta)); dy=sign_threshold(cos(theta)); if(i==1){dx=-dx;dy=-dy;} }
        else { dx=sign_threshold(cos(theta)); dy=sign_threshold(-sin(theta)); if(i==3){dx=-dx;dy=-dy;} }
        command(commands[i]);
        assert(b.x==16+dx && b.y==16+dy && b.z==12+dz);
    }
    for(i=0;i<10000;++i) {
        b.angle=(uint8_t)(i%100); b.held=(uint8_t)(i%2);
        command(commands[i%4]);
        assert(b.x<=30 && b.y<=30 && b.z<=22);
    }
}
static void protocol_test(void) {
    VxProtocol p={0};
    const char *wire="BRUSH\r\nJP\nJL\nJB1\nJU\nJH0\nJK\n";
    size_t i;
    char long_line[140];
    vx_brush_init(&b); reply_size=0;
    for(i=0;i<strlen(wire);++i) vx_protocol_feed(&p,&b,(const uint8_t*)wire+i,1,reply,0);
    assert(b.active && b.drawing && b.held && b.y==15 && b.z==13 && b.angle==0 && b.colour==1);
    assert(b.voxels==3 && b.canvas[12][16][16]==1); // three single-voxel stamps; original red ink persists
    assert(!strstr(replies,"ERR"));
    command("J+"); assert(b.y==14); // physical button entry / PC D alias
    command("JH9999999999999999999999"); assert(b.angle==99);
    memset(long_line,'X',sizeof(long_line)); long_line[sizeof(long_line)-1]='\n';
    vx_protocol_feed(&p,&b,(const uint8_t*)long_line,sizeof(long_line),reply,0);
    wire=":CLEAR\n:STATUS\nJE\nJP\nBRUSH\nCLEAR\n";
    vx_protocol_feed(&p,&b,(const uint8_t*)wire,strlen(wire),reply,0);
    assert(strstr(replies,"ERR:LINE") && strstr(replies,"BX:") && strstr(replies,"ERR:MODE"));
    assert(strstr(replies,"TARGET_RPS:15 SLICES:120"));
    assert(VX_SLICE_PERIOD_US(8333333u)==555u);
    assert(b.active && !b.drawing && b.voxels==0);
    {
        char out[256];
        vx_brush_command(&b,"JH-1",out,sizeof(out)); assert(!strcmp(out,"ERR:ANGLE\n"));
        vx_brush_command(&b,":DATA 123",out,sizeof(out)); assert(!strcmp(out,"ERR:UNSUPPORTED\n"));
    }
}
static void packing(void) {
    uint32_t rgb[3];
    vx_brush_init(&b); vx_brush_set_active(&b,1);
    vx_brush_snapshot(&b,&snapshot);
    vx_brush_pack_row(&snapshot,400,rgb);
    assert(rgb[0]==0x10000 && rgb[1]==0x10000 && rgb[2]==0x10000); // single-voxel white cursor
    vx_brush_pack_row(&snapshot,401,rgb);
    assert(rgb[0]==0 && rgb[1]==0 && rgb[2]==0); // cursor does not spill into next row
    vx_brush_pack_row(&snapshot,432,rgb);
    assert(rgb[0]==0 && rgb[1]==0 && rgb[2]==0); // or next z layer
    b.canvas[12][16][0]=3; // blue at x=0, independent of cursor
    ++b.revision;
    vx_brush_pack_row(&snapshot,400,rgb); assert(!(rgb[2]&1)); // snapshot immutable
    vx_brush_tick(&b,2); vx_brush_snapshot(&b,&snapshot);
    vx_brush_pack_row(&snapshot,400,rgb);
    assert(rgb[0]==0 && rgb[1]==0 && rgb[2]==1); // blink off, persistent blue
    b.canvas[23][31][31]=6;
    vx_brush_snapshot(&b,&snapshot); vx_brush_pack_row(&snapshot,767,rgb);
    assert(rgb[0]==0x80000000u && rgb[1]==0 && rgb[2]==0x80000000u);
}
typedef struct {
    uint32_t banks[2][VX_ROWS][3], staging[3];
    unsigned row,active,pending,ready,writes;
} Fake;
static Fake fake;
static uint32_t read_reg(void *context,unsigned offset) {
    Fake *f=context;
    if(offset==VX_STATUS) return f->pending*2u+f->ready*4u;
    if(offset==VX_ROW) return f->row;
    assert(0); return 0;
}
static void write_reg(void *context,unsigned offset,uint32_t value) {
    Fake *f=context;
    ++f->writes;
    if(offset>=VX_RED && offset<=VX_BLUE) f->staging[(offset-VX_RED)/4]=value;
    else {
        assert(offset==VX_COMMAND && !f->pending);
        if(value==VX_BEGIN) f->row=0;
        else if(value==VX_WRITE_ROW) {
            assert(f->row<VX_ROWS);
            memcpy(f->banks[!f->active][f->row++],f->staging,sizeof(f->staging));
        } else { assert(value==VX_COMMIT && f->row==VX_ROWS); f->pending=1; }
    }
}
static void transfer(void) {
    VxRegisters io={read_reg,write_reg,&fake};
    unsigned i,writes;
    memset(&fake,0,sizeof(fake)); vx_brush_init(&b); vx_upload_init(&upload);
    b.canvas[12][16][0]=1;
    assert(vx_upload_step(&upload,&b,&io,0)==0);
    b.canvas[12][16][0]=3; ++b.revision; // arrives during the previous snapshot
    for(i=0;i<VX_ROWS;++i) {
        unsigned old=fake.row;
        assert(vx_upload_step(&upload,&b,&io,i)==0);
        assert(fake.row==old+1);
    }
    assert(fake.pending && fake.banks[1][400][0]==1 && fake.banks[1][400][2]==0);
    writes=fake.writes;
    vx_upload_step(&upload,&b,&io,900); assert(fake.writes==writes && upload.frames==0);
    fake.pending=0; fake.ready=1; fake.active^=1;
    vx_upload_step(&upload,&b,&io,901); assert(upload.frames==1);
    vx_upload_step(&upload,&b,&io,902);
    for(i=0;i<VX_ROWS;++i) vx_upload_step(&upload,&b,&io,903+i);
    assert(fake.banks[0][400][0]==0 && fake.banks[0][400][2]==1);
    assert(vx_upload_step(&upload,&b,&io,4000)<0); // commit timeout, no silent overwrite
    writes=fake.writes; vx_upload_step(&upload,&b,&io,4001); assert(fake.writes==writes);
}
int main(void) {
    movement(); protocol_test(); packing(); transfer();
    puts("TEST_PASS brush_host: 800 view/axis cases, bounds, PC protocol framing, canvas, snapshot packing, incremental transfer, timeout");
    return 0;
}
