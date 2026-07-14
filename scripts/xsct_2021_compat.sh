#!/usr/bin/env bash
# Invoke xsct across machines with different Xilinx install roots/versions.
# This PC (dsp-mikro7) has Vitis 2022.2 under ~/xilinx; other PCs use
# /tools or /tool with 2021.1. The libidn.so.11 shim keeps older xsct happy.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compat_dir="$repo_root/software/generated/vitis_compat"
system_lib="/usr/lib/x86_64-linux-gnu/libidn.so.12"

mkdir -p "$compat_dir"
if [[ -r "$system_lib" && ! -e "$compat_dir/libidn.so.11" ]]; then
    ln -sfn "$system_lib" "$compat_dir/libidn.so.11"
fi
export LD_LIBRARY_PATH="$compat_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

xsct_bin=""
for cand in \
    "$HOME"/xilinx/Vitis/Vitis/*/bin/xsct \
    /tools/Xilinx/Vitis/*/bin/xsct \
    /tool/Xilinx/Vitis/*/bin/xsct \
    /opt/Xilinx/Vitis/*/bin/xsct; do
    if [[ -x "$cand" ]]; then
        xsct_bin="$cand"
        break
    fi
done
if [[ -z "$xsct_bin" ]]; then
    echo "XSCT_COMPAT: xsct not found under ~/xilinx, /tools, /tool, or /opt" >&2
    exit 1
fi
echo "XSCT_COMPAT: using $xsct_bin" >&2
exec "$xsct_bin" "$@"
