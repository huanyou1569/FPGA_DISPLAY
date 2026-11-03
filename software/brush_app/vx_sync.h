#ifndef VX_SYNC_H
#define VX_SYNC_H
#include "vx_upload.h"
typedef struct {
    uint32_t flags, period, scan_clocks, edges, accepted, rejected;
    uint32_t rpm, slice_us, scan_hz;
} VxSync;
void vx_sync_read(VxSync *s, const VxRegisters *io);
const char *vx_sync_state(const VxSync *s);
size_t vx_sync_status(const VxSync *s, char *out, size_t capacity);
#endif
