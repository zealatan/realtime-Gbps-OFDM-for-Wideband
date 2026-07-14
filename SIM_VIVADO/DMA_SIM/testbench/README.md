# Understanding `dma_ip_tb.sv`

This note explains the first part of the `dma_ip_tb.sv` testbench file step by step.

The goal is to understand how the DMA simulation environment works before modifying or extending it.

---

## 1. Overall Role of `dma_ip_tb.sv`

`dma_ip_tb.sv` is not just a simple testbench.  
It behaves like a complete simulation environment that includes:

- A fake CPU
- A fake DDR memory
- The DMA DUT
- A result checker

The high-level structure is:

```text
dma_ip_tb.sv
 ├─ Clock/reset generation
 ├─ DUT instance: dma_ip_top
 ├─ AXI-Lite Master VIP instance
 │    └─ Used for register control
 ├─ AXI Memory Slave VIP instance
 │    └─ Used as DDR memory model
 ├─ AXI-Lite write/read tasks
 ├─ Backdoor memory write/read tasks
 └─ Main stimulus
      ├─ Initialize source memory
      ├─ Configure DMA registers
      ├─ Start DMA
      ├─ Poll for DMA completion
      └─ Check destination memory
```

The most important idea is:

```text
The testbench controls the DMA IP through AXI-Lite,
while the DMA IP accesses a simulated memory through AXI4.
```

---

## 2. File Header and Package Imports

At the beginning of the file, we see:

```systemverilog
`timescale 1 ns / 1 ps
import axi_vip_pkg::*;
import slv_m00_axi_vip_pkg::*;
import control_dma_ip_vip_pkg::*;

module dma_ip_tb ();
```

There are three important package imports.

---

### 2.1 `axi_vip_pkg::*`

This package contains the basic Xilinx AXI VIP transaction classes.

For example, later in the testbench we may see objects such as:

```systemverilog
axi_transaction wr_xfer;
axi_transaction rd_xfer;
```

These transaction types come from the AXI VIP package.

Instead of manually toggling low-level AXI signals such as:

```text
AWVALID
WVALID
BREADY
ARVALID
RREADY
```

the testbench uses Xilinx AXI VIP class APIs to generate AXI transactions.

This makes the testbench much cleaner and closer to a real verification environment.

---

### 2.2 `slv_m00_axi_vip_pkg::*`

This package is for the AXI slave memory VIP.

Later, the testbench creates an object similar to:

```systemverilog
slv_m00_axi_vip_slv_mem_t m00_axi;
```

This object behaves as the external memory model.

From the DUT point of view, it looks like a DDR memory connected to the AXI master port.

In other words:

```text
DUT AXI Master
    ↓
AXI Slave Memory VIP
    ↓
Simulated DDR memory
```

The DMA reads data from and writes data to this memory model.

---

### 2.3 `control_dma_ip_vip_pkg::*`

This package is for the AXI-Lite master VIP.

Later, the testbench creates an object similar to:

```systemverilog
control_dma_ip_vip_mst_t ctrl;
```

This object acts like a CPU or software driver.

It writes and reads the DMA IP control registers through AXI-Lite.

So the control path is:

```text
AXI-Lite Master VIP
    ↓
DMA control registers
    ↓
DMA internal control signals
```

---

## 3. Main Components in the Testbench

The testbench contains the following main components:

```text
control_dma_ip_vip  → CPU-like register controller
slv_m00_axi_vip     → DDR-like memory model
dma_ip_top          → DUT
dma_ip_tb.sv        → Scenario generator and checker
```

Conceptually:

```text
             AXI-Lite
 control VIP ---------> dma_ip_top
    CPU role             DUT
                          |
                          | AXI Master
                          v
                  slave memory VIP
                    DDR role
```

The simulation flow is:

```text
1. The testbench initializes the source buffer inside the memory VIP.
2. The testbench configures the DMA registers through AXI-Lite.
3. The testbench writes ap_start.
4. The DUT reads data from memory through AXI master.
5. The DUT processes the stream data.
6. The DUT writes the processed data back to memory.
7. The testbench reads the destination buffer and checks the result.
```

---

## 4. AXI Interface Parameters

The testbench defines several AXI-related parameters:

```systemverilog
parameter C_S_AXI_CONTROL_ADDR_WIDTH      = 12;
parameter C_S_AXI_CONTROL_DATA_WIDTH      = 32;
parameter C_M00_AXI_ADDR_WIDTH            = 32;
parameter C_M00_AXI_DATA_WIDTH            = 64;
parameter C_M00_AXI_DATA_WIDTH_BYTE       = C_M00_AXI_DATA_WIDTH/8;
parameter C_M00_AXI_DATA_WIDTH_BYTE_LOG   = $clog2(C_M00_AXI_DATA_WIDTH_BYTE);
```

There are two AXI interfaces in this design.

---

### 4.1 AXI-Lite Control Interface

```systemverilog
C_S_AXI_CONTROL_ADDR_WIDTH = 12;
C_S_AXI_CONTROL_DATA_WIDTH = 32;
```

This interface is used for control registers.

Examples of registers controlled through AXI-Lite:

```text
ap_start
rdma_transfer_byte
rdma_mem_ptr
wdma_transfer_byte
wdma_mem_ptr
value_to_add
```

The AXI-Lite data width is 32 bits.

This is typical for memory-mapped control registers.

---

### 4.2 AXI Master Memory Interface

```systemverilog
C_M00_AXI_ADDR_WIDTH = 32;
C_M00_AXI_DATA_WIDTH = 64;
```

This interface is used by the DMA engine to access memory.

The DMA uses this AXI master interface for:

```text
RDMA: AXI read
WDMA: AXI write
```

The data width is 64 bits.

That means one AXI beat transfers 8 bytes.

```systemverilog
parameter C_M00_AXI_DATA_WIDTH_BYTE = C_M00_AXI_DATA_WIDTH/8;
```

Therefore:

```text
C_M00_AXI_DATA_WIDTH_BYTE = 64 / 8 = 8 bytes
```

The next parameter is:

```systemverilog
parameter C_M00_AXI_DATA_WIDTH_BYTE_LOG = $clog2(C_M00_AXI_DATA_WIDTH_BYTE);
```

Since:

```text
$clog2(8) = 3
```

this parameter is used for byte-offset and alignment calculations.

For example, if the byte address is:

```text
0x13
```

then with an 8-byte AXI data width:

```text
aligned base address = 0x10
byte offset          = 3
```

This becomes important when accessing memory at byte granularity.

---

## 5. User Transfer Parameters

The testbench defines:

```systemverilog
parameter USER_TRANSFER_LEN = 32'd1024;
parameter USER_RDMA_ADDR    = 32'd0;
```

This means:

```text
Transfer size = 1024 bytes
Source address = 0x0000
```

The destination address is later calculated as:

```systemverilog
USER_RDMA_ADDR + USER_TRANSFER_LEN
```

Since:

```text
USER_RDMA_ADDR    = 0x0000
USER_TRANSFER_LEN = 1024 bytes = 0x0400
```

the destination address becomes:

```text
Destination address = 0x0400
```

So the memory layout is:

```text
0x0000 ~ 0x03FF : Source buffer, 1024 bytes
0x0400 ~ 0x07FF : Destination buffer, 1024 bytes
```

This memory layout is one of the most important parts of the testbench.

---

## 6. AXI-Lite Register Address Map

The testbench defines the DMA control register addresses:

```systemverilog
parameter ADDR_AP_CTRL                   = 6'h00;
parameter ADDR_GIE                       = 6'h04;
parameter ADDR_IER                       = 6'h08;
parameter ADDR_ISR                       = 6'h0c;
parameter ADDR_RDMA_TRANSFER_BYTE_DATA_0 = 6'h10;
parameter ADDR_RDMA_MEM_PTR_DATA_0       = 6'h14;
parameter ADDR_WDMA_TRANSFER_BYTE_DATA_0 = 6'h18;
parameter ADDR_WDMA_MEM_PTR_DATA_0       = 6'h1c;
parameter ADDR_AXI00_PTR0_DATA_0         = 6'h20;
parameter ADDR_VALUE_TO_ADD              = 6'h24;
```

This register map is similar to what a software driver would use.

Important registers:

| Address | Register Name | Meaning |
|---:|---|---|
| `0x00` | `ADDR_AP_CTRL` | Start/done/idle/ready control |
| `0x10` | `ADDR_RDMA_TRANSFER_BYTE_DATA_0` | Number of bytes to read |
| `0x14` | `ADDR_RDMA_MEM_PTR_DATA_0` | RDMA source address |
| `0x18` | `ADDR_WDMA_TRANSFER_BYTE_DATA_0` | Number of bytes to write |
| `0x1c` | `ADDR_WDMA_MEM_PTR_DATA_0` | WDMA destination address |
| `0x20` | `ADDR_AXI00_PTR0_DATA_0` | Memory base pointer |
| `0x24` | `ADDR_VALUE_TO_ADD` | Value added by the stream processing DUT |

Later in the testbench, these registers are written like this:

```systemverilog
blocking_write_register(ADDR_RDMA_TRANSFER_BYTE_DATA_0, USER_TRANSFER_LEN);
blocking_write_register(ADDR_RDMA_MEM_PTR_DATA_0, USER_RDMA_ADDR);

blocking_write_register(ADDR_WDMA_TRANSFER_BYTE_DATA_0, USER_TRANSFER_LEN);
blocking_write_register(ADDR_WDMA_MEM_PTR_DATA_0, USER_RDMA_ADDR + USER_TRANSFER_LEN);

blocking_write_register(ADDR_VALUE_TO_ADD, adding_value);
```

The meaning is:

```text
RDMA:
  Read 1024 bytes from address 0x0000.

WDMA:
  Write 1024 bytes to address 0x0400.

Stream processing DUT:
  Add value_to_add to each byte.
```

If `adding_value = 1`, then the expected behavior is:

```text
dst[i] = src[i] + 1
```

---

## 7. AP Control Register Bit Masks

The testbench defines several control bit masks:

```systemverilog
parameter CTRL_START_MASK        = 32'h00000001;
parameter CTRL_DONE_MASK         = 32'h00000002;
parameter CTRL_IDLE_MASK         = 32'h00000004;
parameter CTRL_READY_MASK        = 32'h00000008;
parameter CTRL_CONTINUE_MASK     = 32'h00000010; 
parameter CTRL_AUTO_RESTART_MASK = 32'h00000080; 
```

These bits correspond to an HLS-style `ap_ctrl` register.

The register at `ADDR_AP_CTRL = 0x00` usually has this layout:

```text
bit[0] = ap_start
bit[1] = ap_done
bit[2] = ap_idle
bit[3] = ap_ready
bit[7] = auto_restart
```

---

### 7.1 Checking Idle State

The testbench checks the idle state with:

```systemverilog
if ((lite_rddata & CTRL_IDLE_MASK) == 32'b100)
    break;
```

This means:

```text
If ap_idle == 1, the DMA is ready to start.
```

---

### 7.2 Checking Done State

The testbench checks the done state with:

```systemverilog
if ((lite_rddata & CTRL_DONE_MASK) == 32'b10)
    break;
```

This means:

```text
If ap_done == 1, the DMA operation has finished.
```

Therefore, the control sequence is:

```text
1. Read AP_CTRL until ap_idle is set.
2. Write AP_CTRL with ap_start = 1.
3. Read AP_CTRL until ap_done is set.
```

---

## 8. Clock Generation

The clock generation code is:

```systemverilog
parameter LP_CLK_PERIOD_PS = 10000; // 100 MHz

logic ap_clk = 0;

initial begin: AP_CLK
  forever begin
    ap_clk = #(LP_CLK_PERIOD_PS/2) ~ap_clk;
  end
end
```

The intention seems to be:

```text
10000 ps = 10 ns
10 ns period = 100 MHz
```

However, there is an important detail.

At the top of the file, the timescale is:

```systemverilog
`timescale 1 ns / 1 ps
```

If a delay does not include a time unit suffix, it is interpreted using the time unit of the file.

Therefore:

```systemverilog
#(LP_CLK_PERIOD_PS/2)
```

may be interpreted as:

```text
#5000 ns
```

instead of:

```text
#5000 ps
```

This would result in:

```text
Half period = 5000 ns
Full period = 10000 ns
Clock frequency = 100 kHz
```

not 100 MHz.

For clarity, the clock generation code can be rewritten as:

```systemverilog
parameter real LP_CLK_PERIOD_NS = 10.0; // 100 MHz

initial begin : AP_CLK
  forever begin
    #(LP_CLK_PERIOD_NS/2.0) ap_clk = ~ap_clk;
  end
end
```

Or more directly:

```systemverilog
initial begin : AP_CLK
  forever begin
    #5ns ap_clk = ~ap_clk; // 100 MHz
  end
end
```

The current simulation may still work functionally, but the time unit should be cleaned up for readability and correctness.

---

## 9. Reset Generation

The reset signals are:

```systemverilog
logic ap_rst_n = 0;
logic initial_reset  = 0;
```

`ap_rst_n` is an active-low reset signal.

```text
ap_rst_n = 0 → reset active
ap_rst_n = 1 → reset released
```

The reset task is:

```systemverilog
task automatic ap_rst_n_sequence(input integer unsigned width = 20);
  @(posedge ap_clk);
  #1ps;
  ap_rst_n = 0;
  repeat (width) @(posedge ap_clk);
  #1ps;
  ap_rst_n = 1;
endtask
```

The reset sequence is started here:

```systemverilog
initial begin: AP_RST
  ap_rst_n_sequence(50);
  initial_reset = 1;
end
```

The behavior is:

```text
1. Wait for one positive clock edge.
2. Assert reset by setting ap_rst_n = 0.
3. Keep reset active for 50 clock cycles.
4. Release reset by setting ap_rst_n = 1.
5. Set initial_reset = 1.
```

Waveform-style view:

```text
ap_clk    : _/‾\_/‾\_/‾\_/‾\_/‾\_ ...
ap_rst_n : 0---------------------1----
```

The `#1ps` delay is used to avoid changing reset exactly at the same simulation delta cycle as the clock edge.

This is a common testbench technique.

---

## 10. Summary of This Section

So far, the first part of `dma_ip_tb.sv` defines the simulation environment.

Key points:

```text
1. The testbench uses Xilinx AXI VIP.
2. control_dma_ip_vip acts like a CPU.
3. slv_m00_axi_vip acts like DDR memory.
4. The DMA transfers 1024 bytes.
5. The source buffer starts at 0x0000.
6. The destination buffer starts at 0x0400.
7. AXI-Lite registers configure RDMA, WDMA, and the stream processing DUT.
8. AP_CTRL is used for start, idle, and done control.
9. Clock and reset are generated inside the testbench.
```

The most important concept is:

```text
`dma_ip_tb.sv` simulates not only the hardware DUT,
but also the software driver, the memory system, and the result checker.
```

The next part to study should be:

```text
1. Wire declarations
2. dma_ip_top instance
3. control_dma_ip_vip instance
4. slv_m00_axi_vip instance
```

That section shows how the DUT, AXI-Lite master, and AXI memory slave are physically connected in the simulation.
