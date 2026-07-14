#!/usr/bin/env bash
# run_rx_multiframe.sh
# MULTI-FRAME continuous-streaming full-chain BER gate (rx_full_chain_top).
# Loops the identical golden frame N times in BOTH source modes:
#   mode (a) backpressure-honoring  : default
#   mode (b) free-running (drop-mode): +FREERUN=1
# Reuses the already-generated xfft IP sim files (no IP regen). Vivado 2021.1 xsim.
#
# Args:  NFRAMES (default 5)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NFRAMES="${1:-5}"

VIVADO_DIR="${VIVADO_DIR:-/opt/Xilinx/Vivado/2021.1}"
source "$VIVADO_DIR/settings64.sh"

BUILD="$ROOT/vivado_xsim/logs/rx_multiframe_build"
rm -rf "$BUILD"; mkdir -p "$BUILD"

# Stage hex/rom files the TB / downstream modules $readmemh from the cwd.
cp "$ROOT/vectors/bk_conj_fft512_rom.txt"                 "$BUILD/" 2>/dev/null || true
cp "$ROOT/golden/rx_downstream/tx_slot_iq.hex"            "$BUILD/" 2>/dev/null || true
cp "$ROOT/golden/rx_downstream/pilot_rom.hex"             "$BUILD/" 2>/dev/null || true
cp "$ROOT/golden/rx_downstream/tx_bits.txt"               "$BUILD/" 2>/dev/null || true
cp "$ROOT/golden/rx_downstream/ce_pilot_recip.hex"        "$BUILD/" 2>/dev/null || true
cp "$ROOT/rtl/rx_equalizer_recip_lut.hex"                 "$BUILD/" 2>/dev/null || true
# downstream rx_ch_est default CE_W_ROM = "rtl/rx_ch_est_rom/ce_interp_W.hex"
ln -sfn "$ROOT/rtl" "$BUILD/rtl"
cd "$BUILD"

IPGEN="$ROOT/vivado_xsim/DSP_Rx.gen/sources_1/ip"
VHDL_FILES=$(find "$IPGEN/xfft_N/hdl" "$IPGEN/xfft_2N/hdl" "$IPGEN/xfft_IFFT/hdl" \
                  "$IPGEN/xfft_N/synth" "$IPGEN/xfft_2N/synth" "$IPGEN/xfft_IFFT/synth" \
                  -name "*.vhd" 2>/dev/null | sort -u)

echo "=== compiling IP VHDL ($(echo "$VHDL_FILES" | wc -l) files) ==="
xvhdl --nolog -work xil_defaultlib $VHDL_FILES > "$BUILD/ip_vhdl.log" 2>&1
if [ $? -ne 0 ]; then echo "BLOCKED: IP vhdl compile failed"; tail -40 "$BUILD/ip_vhdl.log"; exit 1; fi

echo "=== compiling RTL ==="
xvlog --nolog $ROOT/rtl/*.v > "$BUILD/rtl.log" 2>&1
if [ $? -ne 0 ]; then echo "BLOCKED: rtl compile failed"; tail -60 "$BUILD/rtl.log"; exit 1; fi

echo "=== compiling TB ==="
xvlog --nolog -sv "$ROOT/tb/rx_full_chain_multiframe_tb.sv" > "$BUILD/tb.log" 2>&1
if [ $? -ne 0 ]; then echo "BLOCKED: tb compile failed"; tail -60 "$BUILD/tb.log"; exit 1; fi

echo "=== elaborating ==="
xelab --nolog -L work -L xil_defaultlib -L xfft_v9_1_8 \
      --snapshot rx_mf_snap work.rx_full_chain_multiframe_tb > "$BUILD/elab.log" 2>&1
if ! grep -q "Built simulation snapshot" "$BUILD/elab.log"; then
    echo "BLOCKED: elab failed"; tail -60 "$BUILD/elab.log"; exit 1
fi

echo "=== simulating mode (a) BACKPRESSURE-HONORING, NFRAMES=$NFRAMES ==="
xsim --nolog rx_mf_snap --runall --onerror quit \
     -testplusarg NFRAMES=$NFRAMES -testplusarg FREERUN=0 2>&1 | tee "$BUILD/sim_bp.log"

echo "=== simulating mode (b) FREE-RUNNING (drop), NFRAMES=$NFRAMES ==="
xsim --nolog rx_mf_snap --runall --onerror quit \
     -testplusarg NFRAMES=$NFRAMES -testplusarg FREERUN=1 2>&1 | tee "$BUILD/sim_fr.log"

echo "======================================================================"
echo "MULTI-FRAME STREAMING SUMMARY (NFRAMES=$NFRAMES)"
echo "======================================================================"
echo "--- mode (a) backpressure ---"
grep -E "MFRAME|GATE:|dropped_beats" "$BUILD/sim_bp.log"
echo "--- mode (b) free-running ---"
grep -E "MFRAME|GATE:|dropped_beats|free-run" "$BUILD/sim_fr.log"
