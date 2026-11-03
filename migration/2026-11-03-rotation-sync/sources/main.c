/* PYNQ-Z2, Cortex-A9 core 0, Vitis 2026.1 Standalone/SDT.
 * UART0 console; UART1 115200 8N1 -> original BLE serial module.
 * Polling is bounded, and at most one canvas row is uploaded per loop.
 */
#include "vx_brush.h"
#include "vx_upload.h"
#include "vx_sync.h"
#include "vx_hardware.h" /* generated from this design's XSA, never guessed */
#include "xparameters.h"
#include "xuartps.h"
#include "xuartps_hw.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xpseudo_asm.h"
#include "xiltimer.h" /* SDT BSP exposes XTime through xilTimer. */
#include "sleep.h"
#include "xstatus.h"

static VxBrush brush;
static VxProtocol protocol;
static VxUploader uploader;
static XUartPs bluetooth;
static XUartPs console;
static VxSync rotation;
static volatile uint32_t ddr_probe[1024] __attribute__((aligned(32)));
#define TX_SIZE 4096u
static char tx[TX_SIZE];
static unsigned tx_head,tx_tail;
static uint32_t tx_dropped,rx_overruns;

static uint32_t reg_read(void *unused, unsigned offset) {
    (void)unused;
    return Xil_In32((UINTPTR)VX_BRUSH_BASEADDR+offset);
}
static void reg_write(void *unused, unsigned offset, uint32_t value) {
    (void)unused;
    Xil_Out32((UINTPTR)VX_BRUSH_BASEADDR+offset,value);
    dmb();
}
static void enqueue(void *unused, const char *data, size_t size) {
    size_t i;
    unsigned free_space=(tx_tail-tx_head-1u)&(TX_SIZE-1u);
    (void)unused;
    if(size>free_space) { ++tx_dropped; return; }
    for(i=0;i<size;++i) { tx[tx_head]=data[i]; tx_head=(tx_head+1u)&(TX_SIZE-1u); }
}
static void service_tx(void) {
    unsigned budget=32;
    while(budget-- && tx_tail!=tx_head && !XUartPs_IsTransmitFull(XPAR_UART1_BASEADDR)) {
        XUartPs_WriteReg(XPAR_UART1_BASEADDR,XUARTPS_FIFO_OFFSET,(uint8_t)tx[tx_tail]);
        tx_tail=(tx_tail+1u)&(TX_SIZE-1u);
    }
}
static int init_uart(XUartPs *uart, UINTPTR base) {
    XUartPs_Config *config;
    XUartPsFormat format;
    int status;
    // This BSP uses SDT: LookupConfig takes a base address, not a device ID.
    config=XUartPs_LookupConfig(base);
    if(!config) return XST_FAILURE;
    status=XUartPs_CfgInitialize(uart,config,config->BaseAddress);
    if(status!=XST_SUCCESS) return status;
    XUartPs_SetInterruptMask(uart,0);
    XUartPs_SetOperMode(uart,XUARTPS_OPER_MODE_NORMAL);
    format.BaudRate=115200;
    format.DataBits=XUARTPS_FORMAT_8_BITS;
    format.Parity=XUARTPS_FORMAT_NO_PARITY;
    format.StopBits=XUARTPS_FORMAT_1_STOP_BIT;
    return XUartPs_SetDataFormat(uart,&format);
}
static uint32_t now_ms(void) {
    XTime time;
    XTime_GetTime(&time);
    return (uint32_t)(time/(COUNTS_PER_SECOND/1000u));
}
static int check_ddr(void) {
    static const uint32_t patterns[]={0,UINT32_MAX,UINT32_C(0x55aa55aa),UINT32_C(0xa5a55a5a)};
    unsigned pass,i;
    for(pass=0;pass<4;++pass) {
        for(i=0;i<1024;++i) ddr_probe[i]=patterns[pass]^(i*UINT32_C(0x01010101));
        Xil_DCacheFlushRange((INTPTR)ddr_probe,sizeof(ddr_probe));
        Xil_DCacheInvalidateRange((INTPTR)ddr_probe,sizeof(ddr_probe));
        for(i=0;i<1024;++i) {
            uint32_t expected=patterns[pass]^(i*UINT32_C(0x01010101));
            uint32_t actual=ddr_probe[i];
            if(actual!=expected) {
                xil_printf("DDR probe FAIL pass=%u word=%u expected=%08x actual=%08x\r\n",
                    pass,i,expected,actual);
                return XST_FAILURE;
            }
        }
    }
    return XST_SUCCESS;
}
int main(void) {
    const VxRegisters io={reg_read,reg_write,0};
    uint32_t last_report=0;
    uint32_t bridge_id;
    int upload_fault_reported=0;
    if(init_uart(&console,XPAR_UART0_BASEADDR)!=XST_SUCCESS) return XST_FAILURE;
    xil_printf("\r\nVX brush: UART0 ready; enabling caches\r\n");
    Xil_ICacheEnable();
    Xil_DCacheEnable();
    xil_printf("\r\nVX display: UART1 115200 8N1; BTN2 demo/brush/snake/tetris\r\n");
    if(check_ddr()!=XST_SUCCESS) return XST_FAILURE;
    xil_printf("DDR 4 KiB probe PASS\r\n");
    xil_printf("Reading brush AXI ID...\r\n");
    bridge_id=reg_read(0,VX_ID);
    xil_printf("Brush AXI ID=0x%08x\r\n",bridge_id);
    if(bridge_id!=VX_BRIDGE_ID) {
        xil_printf("Brush bridge ID mismatch. Load matching brush XSA/bitstream.\r\n");
        return XST_FAILURE;
    }
    if(init_uart(&bluetooth,XPAR_UART1_BASEADDR)!=XST_SUCCESS) {
        xil_printf("Bluetooth UART initialization failed\r\n");
        return XST_FAILURE;
    }
    vx_brush_init(&brush);
    vx_upload_init(&uploader);
    usleep(1); /* Start xilTimer's A9 global counter before XTime_GetTime. */
    xil_printf("UART1 ready; canvas uploader running\r\n");
    xil_printf("Display target: %u rps, %u slices/rev\r\n",
               (unsigned)VX_TARGET_RPS,(unsigned)VX_ANGLE_SLICES);
    // Keep the board's selected mode. The PL boots in its original demo mode.
    for(;;) {
        uint32_t status=reg_read(0,VX_STATUS);
        uint32_t ms=now_ms();
        unsigned budget=256;
        // Read the full PL-selected mode, not just STATUS's canvas-active flag.
        uint32_t revolution=reg_read(0,VX_REVOLUTION);
        unsigned mode=(unsigned)reg_read(0,VX_MODE);
        if(mode!=brush.mode) {
            brush.revolution=revolution; // do not catch up turns spent in other modes
            vx_brush_set_mode(&brush,mode);
        }
        vx_brush_tick(&brush,revolution);
        if(brush.mode==VX_TETRIS && vx_tetris_tick(&brush.tetris,ms)) ++brush.revision;
        vx_sync_read(&rotation,&io);
        brush.rpm=rotation.rpm;
        brush.phase_us=rotation.slice_us; // actual frame_done interval, even during free-run
        brush.uploaded_frames=uploader.frames;
        if(XUartPs_ReadReg(XPAR_UART1_BASEADDR,XUARTPS_ISR_OFFSET)&XUARTPS_IXR_OVER) {
            ++rx_overruns;
            XUartPs_WriteReg(XPAR_UART1_BASEADDR,XUARTPS_ISR_OFFSET,XUARTPS_IXR_OVER);
            protocol.discard=1; protocol.length=0;
        }
        while(budget-- && XUartPs_IsReceiveData(XPAR_UART1_BASEADDR)) {
            uint8_t byte=(uint8_t)XUartPs_ReadReg(XPAR_UART1_BASEADDR,XUARTPS_FIFO_OFFSET);
            vx_protocol_feed(&protocol,&brush,&byte,1,enqueue,0);
        }
        if(brush.mode_request>=0) {
            reg_write(0,VX_MODE,(uint32_t)brush.mode_request);
            brush.mode_request=-1;
        }
        service_tx();
        if(vx_upload_step(&uploader,&brush,&io,ms)<0 && !upload_fault_reported) {
            static const char error[]="ERR:CANVAS_TRANSFER\n";
            enqueue(0,error,sizeof(error)-1);
            xil_printf("Canvas transfer fault; original demo still selectable with BTN2.\r\n");
            upload_fault_reported=1;
        }
        if((uint32_t)(ms-last_report)>=1000u) {
            char response[512];
            size_t length=vx_brush_status(&brush,response,sizeof(response));
            enqueue(0,response,length);
            length=vx_sync_status(&rotation,response,sizeof(response));
            enqueue(0,response,length);
            xil_printf("%s",response);
            xil_printf("VX mode=%s uploaded=%u state=%u row=%u status=0x%02x\r\n",
                vx_mode_name(brush.mode),uploader.frames,
                (unsigned)uploader.state,(unsigned)uploader.row,
                (unsigned)status);
            if(rx_overruns || tx_dropped) xil_printf("BLE RX overruns=%u TX drops=%u\r\n",rx_overruns,tx_dropped);
            last_report=ms;
        }
    }
}
