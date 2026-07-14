#include <stdio.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xtime_l.h"  // To measure of processing time

#define AXI_DATA_BYTE 8 // 64 / 8

// REG MAP
#define ADDR_AP_CTRL                    0x00
#define ADDR_GIE                        0x04
#define ADDR_IER                        0x08
#define ADDR_ISR                        0x0c
#define ADDR_RDMA_TRANSFER_BYTE_DATA_0  0x10
#define ADDR_RDMA_MEM_PTR_DATA_0        0x14
#define ADDR_WDMA_TRANSFER_BYTE_DATA_0  0x18
#define ADDR_WDMA_MEM_PTR_DATA_0        0x1c
#define ADDR_AXI00_PTR0_DATA_0          0x20
#define ADDR_ADD_TO_VALUE               0x24

#define CTRL_DONE_MASK                  0x00000002
#define CTRL_IDLE_MASK                  0x00000004

#define BASE_ADDR 0x10000000

void hw_memcpy(void* dest, const void* source, size_t num){
    u32 read_data;
	Xil_Out32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_RDMA_TRANSFER_BYTE_DATA_0, (u32)num);
	Xil_Out32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_RDMA_MEM_PTR_DATA_0, (u32) source );
	Xil_Out32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_WDMA_TRANSFER_BYTE_DATA_0, (u32)num);
	Xil_Out32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_WDMA_MEM_PTR_DATA_0, (u32) dest);

	while(1) {
		read_data = Xil_In32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_AP_CTRL);
	    if( (read_data & CTRL_IDLE_MASK) == CTRL_IDLE_MASK ) // IDLE
	    	break;
	}
	Xil_Out32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_AP_CTRL, (u32)(0x00000001)); // Start !!

 	while(1) {
		read_data = Xil_In32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_AP_CTRL);
	    if( (read_data & CTRL_DONE_MASK) == CTRL_DONE_MASK ) // IDLE
	    	break;
	}

}

int main() {
    u32 transfer_cnt;
    u32 add_val;
    XTime tStart, tEnd;
    while (1) {
///////////////////////////////////////////////////////////////////////
//////////// HW DMA Latency (two way- memory read/write) //////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////
    	printf("======= mem_copy_test ======\n");
    	do{
        	printf("plz input transfer_cnt\n");
        	scanf("%u",&transfer_cnt);
    	}while( !( (0 < transfer_cnt) && (transfer_cnt%AXI_DATA_BYTE == 0) && (transfer_cnt <= 67108864) ) );
    	do{
    		printf("plz input add_val (0~255)\n");
    		scanf("%u",&add_val);
    	}while( !( (0 <= add_val) && (add_val<256) ) );

    	u8* rdma_baseaddr = (u8*) BASE_ADDR;
    	u8* wdma_baseaddr = (u8*) (BASE_ADDR + transfer_cnt);

    	for(int addr = 0; addr < transfer_cnt; addr++){
    		u8 data = addr %256;
    		rdma_baseaddr[addr] = data;
    	}
    	Xil_DCacheDisable();
    	float transfer_bytes_display = transfer_cnt/1024/1024;
    	printf("rdma_baseaddr : 0x%x\n", rdma_baseaddr);
    	printf("wdma_baseaddr : 0x%x\n", wdma_baseaddr);
    	printf("transfer_cnt size : %f Mbytes\n", transfer_bytes_display);

    	Xil_Out32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_AXI00_PTR0_DATA_0, (u32)(0x00000000));
        Xil_Out32((XPAR_DMA_IP_TOP_0_BASEADDR) + ADDR_ADD_TO_VALUE, (u32) add_val);

    	XTime_GetTime(&tStart);
    	hw_memcpy(wdma_baseaddr, rdma_baseaddr, transfer_cnt);
    	XTime_GetTime(&tEnd);
		printf("HW Mem Copy function Time %.2f us.\n",
		       1.0 * (tEnd - tStart) / (COUNTS_PER_SECOND/1000000));

    	for(int addr = 0; addr < transfer_cnt; addr++){
    		u8 golden_val = rdma_baseaddr[addr] + add_val;
    		if(golden_val != wdma_baseaddr[addr]){
    			printf("Mismatch!!!! addr = %d, golden_val =%x, wdma_value = %x \n", addr, golden_val, wdma_baseaddr[addr]);
    		}
    	}
///////////////////////////////////////////////////////////////////////
//////////// SW Memory Latency (two way- memory read/write)//////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////
    	XTime_GetTime(&tStart);
		memcpy (wdma_baseaddr, rdma_baseaddr, transfer_cnt);
    	XTime_GetTime(&tEnd);
		printf("SW Mem Copy function Time %.2f us.\n",
		       1.0 * (tEnd - tStart) / (COUNTS_PER_SECOND/1000000));

    	XTime_GetTime(&tStart);
    	for(int addr = 0; addr < transfer_cnt; addr++){
    		wdma_baseaddr[addr] = rdma_baseaddr[addr];
    	}
    	XTime_GetTime(&tEnd);
 		printf("SW no use dma Time %.2f us.\n",
		       1.0 * (tEnd - tStart) / (COUNTS_PER_SECOND/1000000));
    }
    return 0;
}
