/* Rotation telemetry only. Game state and commands remain unchanged. */
#include "vx_sync.h"
#include <stdio.h>
#include <string.h>
void vx_sync_read(VxSync *s, const VxRegisters *io) {
    // PERIOD latches all following words in the AXI bridge (one clock domain).
    s->period=io->read(io->context,VX_PERIOD);
    s->flags=io->read(io->context,VX_SYNC_FLAGS);
    s->edges=io->read(io->context,VX_SYNC_EDGES);
    s->accepted=io->read(io->context,VX_SYNC_ACCEPTED);
    s->rejected=io->read(io->context,VX_SYNC_REJECTED);
    s->scan_clocks=io->read(io->context,VX_SCAN_PERIOD);
    s->rpm=(s->flags&12u)==12u && s->period ?
        (uint32_t)((UINT64_C(60)*VX_CLOCK_HZ+s->period/2u)/s->period) : 0;
    s->slice_us=(uint32_t)((uint64_t)s->scan_clocks*1000000u/VX_CLOCK_HZ);
    s->scan_hz=s->scan_clocks ? VX_CLOCK_HZ/s->scan_clocks : 0;
}
const char *vx_sync_state(const VxSync *s) {
    uint64_t sweep=(uint64_t)s->scan_clocks*VX_ANGLE_SLICES;
    if(!(s->flags&4u)) return "LOST";
    if(!(s->flags&8u) || !s->period) return "ACQUIRE";
    if(s->flags&32u) return "LIMIT";
    // A rounded-down line divider leaves less than 32*120 clocks/turn.
    if(!s->scan_clocks || sweep>s->period || s->period-sweep>=32u*VX_ANGLE_SLICES)
        return "ADJUST";
    return "TRACK";
}
size_t vx_sync_status(const VxSync *s, char *out, size_t capacity) {
    int n;
    if(!capacity) return 0;
    out[0]=0;
    out[capacity-1]=0;
    n=snprintf(out,capacity,
        "SYNC:%s DO:%u LEVEL:%u EDGES:%lu ACCEPT:%lu REJECT:%lu PERIOD_CLK:%lu FRAME_CLK:%lu SCAN_HZ:%lu SLICE_US:%lu\n",
        vx_sync_state(s),(unsigned)(s->flags&1u),(unsigned)((s->flags>>1)&1u),
        (unsigned long)s->edges,(unsigned long)s->accepted,(unsigned long)s->rejected,
        (unsigned long)s->period,(unsigned long)s->scan_clocks,
        (unsigned long)s->scan_hz,(unsigned long)s->slice_us);
    out[capacity-1]=0; // legacy host CRT may return -1 on truncation
    return n<0 ? strlen(out) : ((size_t)n<capacity ? (size_t)n : capacity-1);
}
