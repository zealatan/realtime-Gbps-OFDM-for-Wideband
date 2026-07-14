# `moving_avg_optimized` and `tb_moving_avg` Short Documentation

## 1. Purpose

The `moving_avg_optimized` module implements an FPGA-friendly sliding-window moving sum / moving-average style filter.

It is designed to compute a running accumulation over a fixed window length:

```text
WINDOW_SIZE = 2^WINDOW_SHIFT
```

For the default configuration:

```text
WINDOW_SHIFT = 5
WINDOW_SIZE  = 32
```

The module updates the running sum using the standard sliding-window equation:

```text
running_sum[n] = running_sum[n-1] + data_in[n] - data_in[n-WINDOW_SIZE]
```

Instead of re-summing all 32 samples every cycle, the module only adds the newest sample and subtracts the oldest sample. This makes the design suitable for FPGA implementation.

---

## 2. DUT Parameters

```verilog
parameter DATA_WIDTH   = 32;
parameter WINDOW_SHIFT = 5;
parameter RAM_LATENCY  = 2;
```

| Parameter | Description |
|---|---|
| `DATA_WIDTH` | Input data width. Default is 32 bits. |
| `WINDOW_SHIFT` | Log2 of the moving window size. Default `5` gives a 32-sample window. |
| `RAM_LATENCY` | Expected RAM read latency used for timing alignment. |

---

## 3. DUT Interface

```verilog
input  wire                   clock;
input  wire                   reset;
input  wire                   enable;
input  wire signed [31:0]     data_in;
input  wire                   input_strobe;
output reg  signed [63:0]     data_out;
output reg                    output_strobe;
```

| Signal | Direction | Description |
|---|---|---|
| `clock` | Input | Main clock. |
| `reset` | Input | Synchronous active-high reset. |
| `enable` | Input | Enables pipeline and accumulator update. |
| `data_in` | Input | Signed input sample. |
| `input_strobe` | Input | Indicates valid input sample. |
| `data_out` | Output | Scaled running sum output. |
| `output_strobe` | Output | Indicates valid output sample. |

---

## 4. Internal Architecture

The module consists of four main parts:

1. **Input pipeline**  
   Delays `data_in` and `input_strobe` to align the current sample with the delayed RAM output.

2. **RAM-based delay line**  
   Uses `ram_2port` as a circular buffer. The RAM stores the latest samples and returns the oldest sample from the same address.

3. **Accumulator**  
   Updates the running sum using:

   ```text
   running_sum <= running_sum + new_data - old_data
   ```

4. **Output scaling**  
   Applies a 12-bit arithmetic right shift:

   ```verilog
   data_out <= running_sum >>> 12;
   ```

This scaling reduces output magnitude and matches the expected fixed-point behavior used in the testbench.

---

## 5. Important Timing Point

The module assumes that `old_data` from RAM is valid after `RAM_LATENCY` cycles. Therefore, the current input sample is delayed using `data_in_pipe` and `strobe_pipe`.

The accumulator update is currently triggered by:

```verilog
if (strobe_pipe[RAM_LATENCY-1]) begin
    running_sum <= running_sum
                 + $signed(data_in_pipe[RAM_LATENCY-1])
                 - $signed(old_data);
end
```

This means the design uses `RAM_LATENCY-1` as the effective alignment point. This should be checked against the actual latency of `ram_2port`.

If the RAM really has two cycles of read latency, the alignment may need to use:

```verilog
strobe_pipe[RAM_LATENCY]
data_in_pipe[RAM_LATENCY]
```

instead of `RAM_LATENCY-1`.

---

## 6. Testbench Overview

The testbench `tb_moving_avg` verifies the DUT against a behavioral golden model.

The testbench uses the same window size as the DUT:

```verilog
parameter WINDOW_SHIFT = 5;
parameter WINDOW_SIZE  = 1 << WINDOW_SHIFT; // 32
```

A golden circular buffer is used:

```verilog
golden_buffer[0:WINDOW_SIZE-1]
```

The expected sum is updated as:

```verilog
expected_sum <= expected_sum
              + $signed(data_in)
              - $signed(golden_buffer[buf_ptr]);
```

The expected output is scaled in the same way as the DUT:

```verilog
expected_avg = expected_sum >>> 12;
```

---

## 7. Test Scenarios

The testbench includes four main test cases.

### TC1: Constant Input

```verilog
repeat(64) send_data(32'd100);
```

Purpose:

- Checks basic moving-sum behavior.
- Verifies that the output increases until the 32-sample window is full.
- After the window is full, the sum should become stable because the new value and removed old value are both `100`.

Expected behavior:

```text
Before 32 valid samples: running_sum gradually increases.
After 32 valid samples: running_sum remains approximately constant.
```

---

### TC2: Ramp Input

```verilog
for (i=1; i<=40; i=i+1) send_data(i * 10);
```

Purpose:

- Checks whether the circular buffer pointer and subtraction of old samples work correctly.
- Verifies dynamic update behavior when input values continuously change.

Expected behavior:

```text
The output should follow the golden model as the window slides over increasing values.
```

---

### TC3: Random Signed Input

```verilog
repeat(100) send_data($random);
```

Purpose:

- Stresses signed arithmetic.
- Checks positive and negative value handling.
- Helps reveal sign-extension, truncation, and accumulator bugs.

Expected behavior:

```text
RTL output should match the signed golden model within the allowed tolerance.
```

---

### TC4: Large Negative Input

```verilog
repeat(32) send_data(-32'd10000);
```

Purpose:

- Verifies negative accumulation behavior.
- Checks arithmetic right shift behavior for negative values.
- Ensures the 64-bit accumulator handles large signed sums correctly.

Expected behavior:

```text
The output should become negative and match expected_sum >>> 12.
```

---

## 8. Comparison Rule

Whenever `output_strobe` is asserted, the testbench compares the RTL output with the golden model:

```verilog
if (abs_diff(data_out, expected_avg) > 64'd1) begin
    error_cnt = error_cnt + 1;
end
```

A tolerance of `1` is allowed:

```text
PASS condition: |RTL - expected| <= 1
FAIL condition: |RTL - expected| > 1
```

This small tolerance is useful when validating fixed-point or pipeline-aligned arithmetic.

---

## 9. Data Injection Method

The testbench sends one valid sample using `send_data()`:

```verilog
task send_data(input signed [DATA_WIDTH-1:0] val);
    begin
        @(posedge clock);
        input_strobe = 1;
        data_in = val;
        @(posedge clock);
        input_strobe = 0;
        data_in = 0;
        repeat(1) @(posedge clock);
    end
endtask
```

This means valid samples are not continuous every cycle. There is a gap after each sample.

Therefore, the DUT is verified under a **strobe-driven input condition**, not a full-rate streaming condition.

---

## 10. Current Verification Coverage

The testbench checks:

- Reset behavior
- Enable behavior during normal operation
- Constant input response
- Ramp input response
- Signed random input response
- Large negative input response
- Circular-buffer based old-sample subtraction
- 12-bit output scaling
- Output comparison using `output_strobe`

---

## 11. Limitations of the Current Testbench

The current testbench is useful, but it does not fully cover all corner cases.

Additional tests are recommended for:

1. **Continuous input strobe**  
   Verify operation when `input_strobe = 1` every clock cycle.

2. **Enable toggling**  
   Check whether the pipeline and RAM address stop correctly when `enable = 0`.

3. **Reset during active stream**  
   Confirm that the accumulator, RAM pointer, and output strobe recover correctly.

4. **Impulse input**  
   Send one large value followed by zeros to verify exact window delay behavior.

5. **RAM latency mismatch test**  
   Confirm whether the correct alignment point is `RAM_LATENCY-1` or `RAM_LATENCY`.

---

## 12. Key RTL Review Notes

### 12.1 Alignment Must Be Verified

The most important design point is the timing alignment between:

```text
old_data from RAM
```

and

```text
data_in_pipe delayed current sample
```

If this alignment is off by one cycle, the moving sum will subtract the wrong old sample.

---

### 12.2 Output Is a Scaled Sum, Not a True Average

Although the module name is `moving_avg_optimized`, the output is:

```text
running_sum >>> 12
```

It is not divided by `WINDOW_SIZE`.

Therefore, the output is a **scaled moving sum**, not a mathematically exact moving average.

---

### 12.3 RAM Initialization Is Not Explicitly Verified

The golden buffer is initialized to zero during reset. The RAM contents inside `ram_2port` should also be reset or initialized to zero. If the RAM does not clear on reset, early output samples may differ from the golden model.

---

## 13. Summary

The `moving_avg_optimized` module implements an efficient sliding-window accumulation structure for FPGA use.

The testbench verifies the main behavior using four scenarios:

1. Constant input
2. Ramp input
3. Random signed input
4. Large negative input

The golden model compares the scaled running sum against the DUT output whenever `output_strobe` is asserted.

The most important point to verify further is the RAM latency alignment. Once the RAM timing is confirmed, this module can be reliably used as the moving correlation / moving power accumulation block inside an OFDM synchronization pipeline.
