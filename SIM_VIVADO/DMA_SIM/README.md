# AXI Transaction-Level Study Notes for the DMA Simulation

This document explains the DMA simulation from an **AXI transaction-level perspective**.

It is intentionally written as a companion document to the DMA IP test scenario.  
Instead of repeating the test objective, memory map, or expected data pattern, this note focuses on:

```text
- Which block is the AXI master or slave
- Which AXI channels are active
- How AXI-Lite register transactions control the DMA
- How AXI4 read/write bursts move data
- How internal valid/ready handshakes connect RDMA, processing logic, FIFO, and WDMA
- What to inspect in the waveform
- What AXI corner cases can be added later
```

---

## 1. AXI Interfaces in the Simulation

The simulation contains three interface domains.

```text
1. AXI-Lite control interface
2. AXI4 full memory-mapped interface
3. Internal stream-style valid/ready interface
```

These three domains should be studied separately.

---

## 2. AXI-Lite Control Plane

The AXI-Lite interface is used only for configuration and status access.

```text
AXI-Lite Master:
  control_dma_ip_vip

AXI-Lite Slave:
  dma_ip_control_s_axi
```

Conceptually:

```text
control_dma_ip_vip
    |
    | AXI-Lite register write/read
    v
dma_ip_control_s_axi
    |
    | internal control/status signals
    v
dma_wrapper / dut
```

The AXI-Lite bus does not carry the main payload data.  
It only programs control registers and reads status registers.

---

## 3. AXI-Lite Write Transaction

An AXI-Lite write transaction uses three independent channels.

```text
AW channel : write address
W  channel : write data
B  channel : write response
```

A typical write transaction has the following handshake sequence:

```text
AWVALID && AWREADY
    ↓
WVALID && WREADY
    ↓
BVALID && BREADY
```

The transfer is complete only after the B channel response handshake.

A register write such as:

```systemverilog
blocking_write_register(register_address, register_value);
```

is converted by the AXI VIP into a bus-level transaction:

```text
AWADDR  = register_address
WDATA   = register_value
WSTRB   = byte write mask
BRESP   = write response
```

The important point is that the testbench does not manually toggle AXI signals.  
The Xilinx AXI VIP generates valid AXI-Lite transactions through transaction-level API calls.

---

## 4. AXI-Lite Read Transaction

An AXI-Lite read transaction uses two channels.

```text
AR channel : read address
R  channel : read data
```

The handshake sequence is:

```text
ARVALID && ARREADY
    ↓
RVALID && RREADY
```

A read transaction such as:

```systemverilog
read_register(register_address, read_data);
```

causes the AXI VIP to issue:

```text
ARADDR = register_address
```

The slave responds with:

```text
RDATA  = register contents
RRESP  = read response
```

Status polling is implemented as repeated AXI-Lite read transactions.

---

## 5. AXI-Lite Slave Behavior

The AXI-Lite slave register block is implemented with simple read/write FSMs.

A typical write-side structure is:

```text
WRIDLE
  wait for address phase

WRDATA
  wait for data phase

WRRESP
  return write response
```

This style is common in generated HLS-style AXI-Lite control blocks.

Important observation:

```text
AXI-Lite allows AW and W channels to be independent.
```

However, simple slave implementations often internally assume a specific ordering, such as:

```text
AW phase first
W phase second
B response last
```

For basic simulation, the AXI VIP sequence works correctly.  
For stronger verification, delayed or reordered AW/W timing should be tested separately.

---

## 6. AXI4 Full Memory-Mapped Data Plane

The main payload data is transferred through the AXI4 full memory interface.

```text
AXI4 Master:
  dma_wrapper
  - RDMA side uses read channels
  - WDMA side uses write channels

AXI4 Slave:
  slv_m00_axi_vip memory model
```

AXI4 full has five channels:

```text
AW : write address
W  : write data
B  : write response

AR : read address
R  : read data
```

In this design:

```text
RDMA uses:
  AR channel
  R channel

WDMA uses:
  AW channel
  W channel
  B channel
```

Thus, the memory-mapped data movement is split into two logical flows:

```text
Read flow:
  memory → RDMA

Write flow:
  WDMA → memory
```

---

## 7. RDMA as an AXI4 Read Master

RDMA initiates AXI4 read transactions.

The read address channel carries:

```text
ARADDR  : start address
ARLEN   : burst length minus one
ARSIZE  : number of bytes per beat encoded as log2(bytes)
ARBURST : burst type
ARVALID : address valid
ARREADY : slave ready
```

After the AR handshake, the memory slave returns data through the R channel.

```text
RDATA   : read data
RVALID  : read data valid
RREADY  : master ready to accept data
RLAST   : final beat of the burst
RRESP   : read response
```

The read transfer progresses only when:

```text
RVALID && RREADY
```

For debugging, the most useful RDMA read signals are:

```text
m00_axi_arvalid
m00_axi_arready
m00_axi_araddr
m00_axi_arlen
m00_axi_arsize
m00_axi_arburst

m00_axi_rvalid
m00_axi_rready
m00_axi_rdata
m00_axi_rlast
m00_axi_rresp
```

---

## 8. WDMA as an AXI4 Write Master

WDMA initiates AXI4 write transactions.

The write address channel carries:

```text
AWADDR  : start address
AWLEN   : burst length minus one
AWSIZE  : number of bytes per beat encoded as log2(bytes)
AWBURST : burst type
AWVALID : address valid
AWREADY : slave ready
```

The write data channel carries:

```text
WDATA   : write data
WSTRB   : byte-enable mask
WVALID  : write data valid
WREADY  : slave ready to accept data
WLAST   : final beat of the burst
```

The write response channel carries:

```text
BRESP   : write response
BVALID  : response valid
BREADY  : master ready to accept response
```

The write data transfer progresses only when:

```text
WVALID && WREADY
```

The write transaction is not fully complete until the B channel response is accepted:

```text
BVALID && BREADY
```

For debugging, the most useful WDMA write signals are:

```text
m00_axi_awvalid
m00_axi_awready
m00_axi_awaddr
m00_axi_awlen
m00_axi_awsize
m00_axi_awburst

m00_axi_wvalid
m00_axi_wready
m00_axi_wdata
m00_axi_wstrb
m00_axi_wlast

m00_axi_bvalid
m00_axi_bready
m00_axi_bresp
```

---

## 9. Relationship Between AXI4 Bursts and Internal Stream Data

The AXI4 read channel delivers memory data to RDMA.  
RDMA then converts that data into an internal stream-style interface.

```text
AXI4 R channel
    ↓
RDMA
    ↓
internal valid/ready/data
```

The internal stream signals can be interpreted as:

```text
out_r_write  = valid
out_r_full_n = ready
out_r_din    = data
```

The processing block receives data only when:

```text
out_r_write && out_r_full_n
```

After processing and FIFO buffering, WDMA consumes data through another stream-style interface.

```text
in_r_empty_n = valid
in_r_read    = ready
in_r_dout    = data
```

WDMA consumes one internal data word only when:

```text
in_r_empty_n && in_r_read
```

Therefore, the complete payload path is:

```text
AXI4 RDATA
  → RDMA internal stream output
  → processing logic
  → FIFO
  → WDMA internal stream input
  → AXI4 WDATA
```

---

## 10. Backpressure Propagation

Backpressure is one of the most important concepts in this simulation.

At every valid/ready interface, transfer occurs only when both sides agree:

```text
VALID && READY
```

Backpressure can originate from several places.

---

### 10.1 Memory Read Backpressure

If the memory slave delays `ARREADY`, RDMA cannot issue the read address immediately.

```text
ARVALID = 1
ARREADY = 0
→ read address is stalled
```

If the memory slave delays `RVALID`, RDMA does not receive read data.

```text
RVALID = 0
RREADY = 1
→ no read data transfer
```

---

### 10.2 Processing/FIFO Backpressure

If the processing block or FIFO cannot accept data, the ready signal toward RDMA is deasserted.

```text
out_r_write  = 1
out_r_full_n = 0
→ RDMA output stream is stalled
```

This can eventually stop RDMA from accepting more AXI4 read data, depending on internal buffering.

---

### 10.3 Memory Write Backpressure

If the memory slave delays `AWREADY`, WDMA cannot issue the write address immediately.

If the memory slave delays `WREADY`, WDMA cannot send write data.

```text
WVALID = 1
WREADY = 0
→ write data channel is stalled
```

This can cause the FIFO to fill, which may propagate backpressure upstream.

---

## 11. Read/Write Overlap

AXI4 read and write channels are independent.

Therefore, RDMA read activity and WDMA write activity can overlap.

A possible pipeline is:

```text
RDMA reads data from memory
    ↓
processing block modifies data
    ↓
FIFO buffers processed data
    ↓
WDMA writes processed data back to memory
```

At the bus level, this means the waveform may show AR/R activity and AW/W/B activity overlapping in time.

However, WDMA cannot write meaningful data until processed data is available from the internal stream path.

So the design has:

```text
AXI-level channel independence
but
datapath-level dependency
```

---

## 12. Backdoor Memory Access Is Not AXI Traffic

The testbench uses backdoor memory access for initialization and checking.

This is important:

```text
Backdoor memory write/read does not generate AXI transactions.
```

Backdoor access directly modifies or reads the memory array inside the AXI memory VIP.

Therefore:

```text
Source initialization:
  backdoor memory write
  → no AW/W/B transaction

Destination checking:
  backdoor memory read
  → no AR/R transaction
```

Only the DMA engine and AXI-Lite control operations generate AXI bus traffic.

---

## 13. Recommended Waveform Study Order

A good way to study the waveform is to follow bus activity in this order:

```text
1. AXI-Lite register writes
2. AXI-Lite status polling
3. AP start write
4. AXI4 read address transaction
5. AXI4 read data burst
6. Internal stream transfer from RDMA to processing logic
7. Internal stream transfer through FIFO to WDMA
8. AXI4 write address transaction
9. AXI4 write data burst
10. AXI4 write response
11. AXI-Lite done polling
```

This order separates control traffic, memory traffic, and internal stream traffic.

---

## 14. Waveform Checklist

### AXI-Lite Control

Check:

```text
s_axi_control_awvalid
s_axi_control_awready
s_axi_control_awaddr

s_axi_control_wvalid
s_axi_control_wready
s_axi_control_wdata
s_axi_control_wstrb

s_axi_control_bvalid
s_axi_control_bready
s_axi_control_bresp

s_axi_control_arvalid
s_axi_control_arready
s_axi_control_araddr

s_axi_control_rvalid
s_axi_control_rready
s_axi_control_rdata
s_axi_control_rresp
```

Questions to ask:

```text
Are register writes reaching the expected addresses?
Are write responses returned correctly?
Are status reads returning changing AP_CTRL values?
Does ap_start appear after the AP_CTRL write?
Does ap_done appear after DMA completion?
```

---

### AXI4 Read Side

Check:

```text
m00_axi_arvalid
m00_axi_arready
m00_axi_araddr
m00_axi_arlen
m00_axi_arsize
m00_axi_arburst

m00_axi_rvalid
m00_axi_rready
m00_axi_rdata
m00_axi_rlast
m00_axi_rresp
```

Questions to ask:

```text
Does RDMA issue a read address?
Is the read address correct?
Is the burst size correct for the AXI data width?
Does RDATA match the initialized source memory?
Is RLAST asserted at the end of each burst?
Is RRESP OKAY?
```

---

### Internal Stream Path

Check:

```text
out_r_write
out_r_full_n
out_r_din

w_in_r_empty_n
w_in_r_read
w_in_r_dout

in_r_empty_n
in_r_read
in_r_dout
```

Questions to ask:

```text
Does RDMA produce stream data after AXI4 read data arrives?
Does the processing block modify the data?
Does the FIFO accept processed data?
Does WDMA consume data from the FIFO?
Is backpressure propagated correctly when ready is low?
```

---

### AXI4 Write Side

Check:

```text
m00_axi_awvalid
m00_axi_awready
m00_axi_awaddr
m00_axi_awlen
m00_axi_awsize
m00_axi_awburst

m00_axi_wvalid
m00_axi_wready
m00_axi_wdata
m00_axi_wstrb
m00_axi_wlast

m00_axi_bvalid
m00_axi_bready
m00_axi_bresp
```

Questions to ask:

```text
Does WDMA issue a write address?
Is the destination address correct?
Does WDATA match the processed stream data?
Is WSTRB valid for the active bytes?
Is WLAST asserted correctly?
Is BRESP OKAY?
```

---

## 15. Useful AXI Corner Cases for Future Tests

The current test is a clean functional scenario.  
For stronger bus-level verification, the following cases are useful.

---

### 15.1 AXI-Lite Corner Cases

```text
AWVALID arrives before WVALID
WVALID arrives before AWVALID
AWVALID and WVALID arrive in the same cycle
BREADY is delayed
ARVALID is accepted but RREADY is delayed
Invalid register address access
Partial register write using WSTRB
Back-to-back register writes
Back-to-back register reads
```

---

### 15.2 AXI4 Read Corner Cases

```text
ARREADY delayed
RVALID delayed
Inter-beat gaps on R channel
Short bursts
Long bursts
Multiple bursts for one transfer
Read response error injection
Read burst near a 4KB boundary
```

---

### 15.3 AXI4 Write Corner Cases

```text
AWREADY delayed
WREADY delayed
BVALID delayed
Inter-beat gaps on W channel
Write response error injection
Write burst near a 4KB boundary
WSTRB variations
Back-to-back write bursts
```

---

### 15.4 Stream Backpressure Cases

```text
FIFO temporarily full
WDMA temporarily not ready
Processing block output stalled
RDMA output stalled
Random valid/ready stalls
```

---

## 16. Key Takeaway

The DMA simulation can be understood as three connected layers:

```text
Control layer:
  AXI-Lite register access

Memory transaction layer:
  AXI4 read/write bursts

Processing layer:
  internal valid/ready stream path
```

The most important transaction-level view is:

```text
AXI-Lite configures the DMA.
AXI4 read fetches source data.
The internal stream path processes and buffers the data.
AXI4 write stores the processed data.
AXI-Lite status polling confirms completion.
```

This perspective is useful for waveform debugging, AXI protocol study, and future verification expansion.
