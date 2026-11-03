#ifndef VX_UPLOAD_H
#define VX_UPLOAD_H
#include "vx_brush.h"
#define VX_BRIDGE_ID UINT32_C(0x56584234) /* VXB4: coherent rotation/scan diagnostics */
enum { VX_ID=0x00, VX_STATUS=0x04, VX_ROW=0x08,
       VX_RED=0x10, VX_GREEN=0x14, VX_BLUE=0x18, VX_COMMAND=0x1c,
       VX_MODE=0x20, VX_REVOLUTION=0x24, VX_PERIOD=0x28,
       VX_SYNC_FLAGS=0x2c, VX_SYNC_EDGES=0x30, VX_SYNC_ACCEPTED=0x34,
       VX_SYNC_REJECTED=0x38, VX_SCAN_PERIOD=0x3c };
enum { VX_BEGIN=1, VX_WRITE_ROW=2, VX_COMMIT=4 };
typedef struct {
    uint32_t (*read)(void *context, unsigned offset);
    void (*write)(void *context, unsigned offset, uint32_t value);
    void *context;
} VxRegisters;
typedef struct {
    VxBrushSnapshot snapshot;
    uint32_t displayed_revision, upload_revision, wait_start_ms, frames;
    unsigned row, state; /* 0 idle, 1 upload, 2 wait commit, 3 fault */
} VxUploader;
void vx_upload_init(VxUploader *u);
int vx_upload_step(VxUploader *u, const VxBrush *b, const VxRegisters *io, uint32_t now_ms);
#endif
