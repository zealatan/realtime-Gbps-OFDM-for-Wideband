#!/usr/bin/env bash
# Board DETECTION regression: GPIO-load each diverse vector (golden/p5_board_regression/),
# run normal mode, compare frame_start/peak/slot vs golden (tolerance). No bitstream rebuild.
set -uo pipefail
cd /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
tc=$(ls -d ~/xilinx/Vitis/Vitis/*/gnu/aarch64/lin/aarch64-none/bin 2>/dev/null | head -1); export PATH="$tc:$PATH"
HDR=software/generated/rfdc_capture_ws/rfdc_capture/src/stim_sweep.h
DBG=software/generated/rfdc_capture_ws/rfdc_capture/Debug
MAN=RTL_SYNC_PHASE5/golden/p5_board_regression/manifest.json
TOL_F=2; TOL_P=1; TOL_S=2
echo "=== BOARD DETECTION REGRESSION $(date +%H:%M) (tol: frame+-$TOL_F peak+-$TOL_P slot+-$TOL_S) ==="
printf "%-10s | %-18s | %-18s | %s\n" "vector" "golden fs/pk/sl" "board fs/pk/sl" "verdict"
names=$(python3 -c "import json;print(' '.join(c['name'] for c in json.load(open('$MAN'))['cases']))")
for nm in $names; do
  read gf gp gs <<<"$(python3 -c "import json;c=[x for x in json.load(open('$MAN'))['cases'] if x['name']=='$nm'][0];print(c['golden_frame_start'],c['golden_peak'],c['golden_slot'])")"
  python3 scripts/gen_stim_sweep_header.py RTL_SYNC_PHASE5/golden/p5_board_regression/reg_${nm}.mem $HDR >/dev/null
  ( cd $DBG && rm -f rfdc_capture.elf src/main.o && make all >/tmp/reg_make_$nm.log 2>&1 )
  [ -f $DBG/rfdc_capture.elf ] || { printf "%-10s | ELF BUILD FAIL\n" "$nm"; continue; }
  screen -S uart -X logfile /tmp/uart_reg_$nm.log 2>/dev/null; screen -S uart -X log on 2>/dev/null
  timeout 200 scripts/xsct_2021_compat.sh scripts/run_10_digital_loopback.xsct reg_$nm >/tmp/reg_run_$nm.console 2>&1
  screen -S uart -X log off 2>/dev/null
  line=$(grep -hE "SYNC fsv" /tmp/uart_reg_$nm.log 2>/dev/null | tail -1)
  bf=$(echo "$line" | grep -oE "fsi=[0-9]+" | grep -oE "[0-9]+")
  bp=$(echo "$line" | grep -oE "peak=[0-9]+" | grep -oE "[0-9]+")
  bs=$(echo "$line" | grep -oE "slot=[0-9]+" | grep -oE "[0-9]+")
  bfsv=$(echo "$line" | grep -oE "fsv=[0-9]+" | grep -oE "[0-9]+")
  v="FAIL"
  if [ -n "$bf" ] && [ "$bfsv" = "1" ]; then
    df=$(( bf>gf ? bf-gf : gf-bf )); dp=$(( bp>gp ? bp-gp : gp-bp )); ds=$(( bs>gs ? bs-gs : gs-bs ))
    [ $df -le $TOL_F ] && [ $dp -le $TOL_P ] && [ $ds -le $TOL_S ] && v="PASS"
  fi
  printf "%-10s | %-18s | %-18s | %s\n" "$nm" "$gf/$gp/$gs" "${bf:-?}/${bp:-?}/${bs:-?} (fsv=${bfsv:-?})" "$v"
done
echo "=== REGRESSION DONE $(date +%H:%M) ==="
