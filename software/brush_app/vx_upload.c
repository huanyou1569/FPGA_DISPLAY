#include "vx_upload.h"
#include <string.h>
void vx_upload_init(VxUploader *u) {
    memset(u,0,sizeof(*u)); u->displayed_revision=UINT32_MAX;
}
int vx_upload_step(VxUploader *u, const VxBrush *b, const VxRegisters *io, uint32_t now_ms) {
    uint32_t status=io->read(io->context,VX_STATUS);
    uint32_t rgb[3];
    if(u->state==3) return -1;
    if(u->state==0) {
        if((status&2u) || u->displayed_revision==b->revision) return 0;
        vx_brush_snapshot(b,&u->snapshot);
        u->upload_revision=b->revision; u->row=0;
        io->write(io->context,VX_COMMAND,VX_BEGIN); u->state=1;
    } else if(u->state==1) {
        if((status&2u) || io->read(io->context,VX_ROW)!=u->row) { u->state=3; return -1; }
        vx_brush_pack_row(&u->snapshot,u->row,rgb);
        io->write(io->context,VX_RED,rgb[0]);
        io->write(io->context,VX_GREEN,rgb[1]);
        io->write(io->context,VX_BLUE,rgb[2]);
        io->write(io->context,VX_COMMAND,VX_WRITE_ROW);
        if(++u->row==VX_ROWS) {
            io->write(io->context,VX_COMMAND,VX_COMMIT);
            u->wait_start_ms=now_ms; u->state=2;
        }
    } else if(u->state==2) {
        if(!(status&2u) && (status&4u)) {
            u->displayed_revision=u->upload_revision;
            ++u->frames; u->state=0;
        } else if((uint32_t)(now_ms-u->wait_start_ms)>2000u) { u->state=3; return -1; }
    }
    return 0;
}
