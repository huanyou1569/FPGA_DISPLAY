#include "vx_sync.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(c) do { if(!(c)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); exit(1); } } while(0)
static unsigned step;
static uint32_t values[7];
static uint32_t rd(void *p, unsigned offset) {
    static const unsigned offsets[]={VX_PERIOD,VX_SYNC_FLAGS,VX_SYNC_EDGES,VX_SYNC_ACCEPTED,VX_SYNC_REJECTED,VX_SCAN_PERIOD};
    (void)p; CHECK(step<6 && offset==offsets[step]); return values[step++];
}
static void read_sample(VxSync *s,uint32_t period,uint32_t flags,uint32_t scan) {
    VxRegisters io={rd,0,0};
    values[0]=period; values[1]=flags; values[2]=20; values[3]=18; values[4]=2; values[5]=scan;
    step=0; vx_sync_read(s,&io); CHECK(step==6);
}
int main(void) {
    VxSync s; char out[256], small[8];
    read_sample(&s,13888889,28,115712); CHECK(s.rpm==540 && s.slice_us==925 && s.scan_hz==1080);
    CHECK(!strcmp(vx_sync_state(&s),"TRACK"));
    CHECK(vx_sync_status(&s,out,sizeof(out))==strlen(out));
    CHECK(strstr(out,"EDGES:20 ACCEPT:18 REJECT:2") && strstr(out,"FRAME_CLK:115712"));
    read_sample(&s,8333333,28,69440); CHECK(s.rpm==900 && s.slice_us==555 && s.scan_hz==1800);
    CHECK(!strcmp(vx_sync_state(&s),"TRACK"));
    read_sample(&s,5681818,28,47328); CHECK(s.rpm==1320); CHECK(!strcmp(vx_sync_state(&s),"TRACK"));
    read_sample(&s,8333333,28,115712); CHECK(!strcmp(vx_sync_state(&s),"ADJUST"));
    read_sample(&s,50000000,44,218880); CHECK(s.rpm==150); CHECK(!strcmp(vx_sync_state(&s),"LIMIT"));
    read_sample(&s,0,4,69440); CHECK(s.rpm==0); CHECK(!strcmp(vx_sync_state(&s),"ACQUIRE"));
    read_sample(&s,8333333,0,69440); CHECK(s.rpm==0 && s.slice_us==555); CHECK(!strcmp(vx_sync_state(&s),"LOST"));
    read_sample(&s,0,12,0); CHECK(s.rpm==0 && s.scan_hz==0); CHECK(!strcmp(vx_sync_state(&s),"ACQUIRE"));
    CHECK(vx_sync_status(&s,small,sizeof(small))==7 && small[7]==0); CHECK(vx_sync_status(&s,0,0)==0);
    puts("TEST_PASS sync: snapshot read order, 540/900/1320RPM, actual scan timing, acquire/loss/limit/transient, bounded formatting");
    return 0;
}
