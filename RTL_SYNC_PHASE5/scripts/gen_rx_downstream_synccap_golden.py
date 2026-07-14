#!/usr/bin/env python3
"""
gen_rx_downstream_synccap_golden.py
===================================
Build ONE complete, SYNC-CAPABLE golden frame of 4160 samples that BOTH the
synchronizer can lock onto AND the rx-downstream chain can demodulate.

WHY THIS EXISTS (correction to the earlier rx_downstream foundation):
    The previous golden frame put PLACEHOLDER/ZERO samples in the 576-sample
    sync region. A zero sync region produces NO frame-detection peak, so the
    end-to-end chain (sync -> FFT -> CE -> EQ -> demod) cannot run at all.

FIX:
    - Keep golden/p5_wrapper_fullchain/fc_kp0.mem[0:640] BYTE-IDENTICAL:
        [0:64]   PRE_ZEROS
        [64:640] REAL sync region (PSS_CP|PSS|SSS_CP|SSS, 576 samples)
      so the existing synchronizer makes the IDENTICAL peak.
    - Replace fc_kp0.mem[640:4096] with the 12 proper rx_downstream data
      symbols (QPSK pilots on pltIndx + 16-QAM data on dataIndx, IDFT+CP),
      from the already-validated rx_downstream_ref model.
    - Match the Q15 scale so the data-region COMPLEX RMS (in integer Q15
      units) equals fc_kp0's data-region RMS (so the sync threshold + the x4
      gearbox energy assumptions stay consistent). Measured fc_kp0 data RMS
      ~= 5045.88 int units; my data float RMS ~= 0.9912 -> scale ~= 5090.70.
    - Keep fc_kp0.mem[4096:4160] = POST_ZEROS.

OUTPUTS (golden/rx_downstream/):
    tx_slot_iq.hex           4160-sample COMPLETE sync-capable frame
                             (M_AXIS {Q[31:16], I[15:0]} Q15)
    tx_slot_iq_float.npy     4160x2 float [I,Q] (data region float; sync region
                             = fc_kp0 ints / scale)
    tx_slot_iq_4032.hex      4032-sample synchronizer corrected M_AXIS output
                             (frame minus 64 pre/post zeros; beat0 = PSS CP start)
    fft_out / hest / eq_out / pilot_rom (.hex + _float.npy)   per-stage golden
                             for the 12 data symbols, derived from the data
                             AS PLACED IN THIS FRAME (same Q15 scale)
    tx_bits.txt / rx_bits.txt   BER check (identical)
    pilot_indx.txt / data_indx.txt

numpy only (no scipy). Does NOT modify any RTL or fc_kp0.mem.
"""

import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import rx_downstream_ref as R   # noqa: E402

FC_KP0 = os.path.join(ROOT, "golden", "p5_wrapper_fullchain", "fc_kp0.mem")
OUT    = os.path.join(ROOT, "golden", "rx_downstream")

# Frame geometry (must match fc_kp0 layout)
PRE_ZEROS  = 64
SYNC_LEN   = 576                       # PSS_CP|PSS|SSS_CP|SSS
NUM_DATA   = R.NUM_DATA                # 12
SYM_LEN    = R.SYM_LEN                 # 288
DATA_LEN   = NUM_DATA * SYM_LEN        # 3456
POST_ZEROS = 64
TOTAL_LEN  = 4160
FRAME_LEN  = 4032                      # slot (sync+data), synchronizer M_AXIS

SYNC_START = PRE_ZEROS                 # 64
DATA_START = PRE_ZEROS + SYNC_LEN      # 640
DATA_END   = DATA_START + DATA_LEN     # 4096

NSC    = R.NSC
CP_LEN = R.CP_LEN

# ----------------------------------------------------------------------
# fc_kp0 readback / packing helpers ({im[15:0], re[15:0]} == {Q,I})
# ----------------------------------------------------------------------
def unpack_word(h):
    w = int(h, 16)
    re = w & 0xFFFF
    im = (w >> 16) & 0xFFFF
    if re >= 0x8000:
        re -= 0x10000
    if im >= 0x8000:
        im -= 0x10000
    return re + 1j * im

def pack_word(iv, qv):
    iv = int(max(-32768, min(32767, iv))) & 0xFFFF
    qv = int(max(-32768, min(32767, qv))) & 0xFFFF
    return ((qv << 16) | iv) & 0xFFFFFFFF

def read_fc_kp0():
    raw = open(FC_KP0).read().split()
    assert len(raw) == TOTAL_LEN, f"fc_kp0 len {len(raw)} != {TOTAL_LEN}"
    return raw  # keep hex strings so [0:640] stays byte-identical

# ----------------------------------------------------------------------
# CP autocorrelation metric (matches streaming_cp_autocorr.v):
#   P[n] = sum_{m=0..CP_LEN-1} r[n-m] * conj(r[n-m-NSC])
# Peaks where a CP aligns with the tail of its body (CP-start +  fill).
# ----------------------------------------------------------------------
def cp_autocorr(x):
    n = len(x)
    prod = np.zeros(n, dtype=complex)
    for i in range(NSC, n):
        prod[i] = x[i] * np.conj(x[i - NSC])
    P = np.zeros(n, dtype=complex)
    acc = 0.0 + 0.0j
    for i in range(n):
        acc += prod[i]
        if i - CP_LEN >= 0:
            acc -= prod[i - CP_LEN]
        P[i] = acc
    return np.abs(P)

# ----------------------------------------------------------------------
# main
# ----------------------------------------------------------------------
def main():
    os.makedirs(OUT, exist_ok=True)

    # ---- 1. read fc_kp0 (hex strings) + complex view ----
    fc_hex = read_fc_kp0()
    fc_cplx = np.array([unpack_word(h) for h in fc_hex])

    fc_data = fc_cplx[DATA_START:DATA_END]
    fc_data_rms = float(np.sqrt(np.mean(np.abs(fc_data) ** 2)))   # int Q15 units
    print(f"[scale] fc_kp0 data-region complex RMS = {fc_data_rms:.6f} (int Q15 units)")

    # ---- 2. build 12 rx_downstream data symbols (float) ----
    data_bits = R.load_bits(os.path.join(R.REF, "Data_Bits.txt"),
                            R.DATA_BITS_PER_BLOCK * NUM_DATA)
    pilot_bits = R.load_bits(os.path.join(R.REF, "Pilot_Bits.txt"),
                             R.PILOT_BITS_PER_BLOCK * NUM_DATA)
    plt = np.zeros((NUM_DATA, R.NUM_PILOTS), dtype=complex)
    for z in range(NUM_DATA):
        for p in range(R.NUM_PILOTS):
            base = (z * R.NUM_PILOTS + p) * R.QPSK_BPS
            plt[z, p] = R.mod_qpsk(pilot_bits[base:base + R.QPSK_BPS])

    syms = np.zeros((NUM_DATA, SYM_LEN), dtype=complex)
    tx_bits = np.zeros((NUM_DATA, R.DATA_BITS_PER_BLOCK), dtype=int)
    for z in range(NUM_DATA):
        dblk = data_bits[z * R.DATA_BITS_PER_BLOCK:(z + 1) * R.DATA_BITS_PER_BLOCK]
        tx_bits[z] = dblk
        sym, _ = R.tx_modulate_block(dblk, plt[z])
        syms[z] = sym

    data_float = syms.reshape(-1)                      # 3456 complex
    my_rms = float(np.sqrt(np.mean(np.abs(data_float) ** 2)))
    Q15_SCALE = fc_data_rms / my_rms                   # RMS-matched to fc_kp0
    print(f"[scale] my data float RMS = {my_rms:.6f}")
    print(f"[scale] Q15_SCALE (matched) = {Q15_SCALE:.6f}")

    # quantize my data symbols at the matched scale
    di = np.clip(np.round(data_float.real * Q15_SCALE), -32768, 32767).astype(int)
    dq = np.clip(np.round(data_float.imag * Q15_SCALE), -32768, 32767).astype(int)
    data_peak = int(np.max(np.abs(np.concatenate([di, dq]))))
    print(f"[scale] data peak (int) = {data_peak} "
          f"({'OK no clip' if data_peak <= 32767 else 'CLIPS!'})")
    # confirm achieved data RMS matches fc_kp0
    ach_rms = float(np.sqrt(np.mean(di.astype(float) ** 2 + dq.astype(float) ** 2)))
    print(f"[scale] achieved data int RMS = {ach_rms:.6f}  "
          f"(fc_kp0 = {fc_data_rms:.6f}, ratio = {ach_rms / fc_data_rms:.6f})")

    # ---- 3. assemble the 4160-sample frame (hex) ----
    frame_hex = list(fc_hex)                            # start byte-identical
    for k in range(DATA_LEN):
        frame_hex[DATA_START + k] = f"{pack_word(di[k], dq[k]):08x}"
    # PRE/POST/SYNC untouched (== fc_kp0)

    # sanity: [0:640] and [4096:4160] byte-identical to fc_kp0
    assert frame_hex[:DATA_START] == fc_hex[:DATA_START], "sync/pre region changed!"
    assert frame_hex[DATA_END:] == fc_hex[DATA_END:], "post region changed!"

    frame_cplx = np.array([unpack_word(h) for h in frame_hex])

    # ---- 3a. VERIFY (a) SYNC-CAPABLE: CP autocorr peak ----
    # The CP-autocorr window P[n] = sum_{m} r[n-m]*conj(r[n-m-NSC]) is fully
    # filled only at the END of each OFDM symbol body. For the PSS symbol the
    # CP is at abs [64..96) and its source body tail is at [320..352); the
    # correlation peaks at the PSS symbol end, abs idx 351 (= PRE_ZEROS + CP +
    # NSC - 1 = 64 + 287). We search a window around the PSS symbol end.
    m_new = cp_autocorr(frame_cplx)
    m_fc  = cp_autocorr(fc_cplx)
    lo, hi = 320, 360                      # PSS symbol-end correlation window
    pk_new_idx = lo + int(np.argmax(m_new[lo:hi]))
    pk_fc_idx  = lo + int(np.argmax(m_fc[lo:hi]))
    # data-region reference (every data symbol also carries a CP -> ~equal peak)
    data_ref_pk = float(np.max(m_new[DATA_START + 32:DATA_END - 32]))
    print(f"\n[sync] NEW frame  PSS CP-autocorr peak = {m_new[pk_new_idx]:.1f} "
          f"at abs idx {pk_new_idx}")
    print(f"[sync] fc_kp0     PSS CP-autocorr peak = {m_fc[pk_fc_idx]:.1f} "
          f"at abs idx {pk_fc_idx}")
    print(f"[sync] data-region CP-autocorr peak (NEW) = {data_ref_pk:.1f} "
          f"(comparable magnitude => CP framing preserved)")
    sync_identical = np.array_equal(frame_cplx[:DATA_START], fc_cplx[:DATA_START])
    sync_metric_identical = np.allclose(m_new[SYNC_START:DATA_START],
                                        m_fc[SYNC_START:DATA_START])
    print(f"[sync] sync region samples identical to fc_kp0 : {sync_identical}")
    print(f"[sync] sync CP-autocorr metric identical       : {sync_metric_identical}")

    # ---- 4. VERIFY (b) DEMODULABLE: run downstream on the PLACED data ----
    # extract the 12 data symbols AS PLACED (dequantized to float at the
    # matched scale) and run FFT->CE->EQ->demod.
    placed = frame_cplx[DATA_START:DATA_END] / Q15_SCALE   # float amplitude
    fft_out = np.zeros((NUM_DATA, NSC), dtype=complex)
    hest_out = np.zeros((NUM_DATA, NSC), dtype=complex)
    eq_out = np.zeros((NUM_DATA, R.NUM_DATA_SC), dtype=complex)
    rx_bits = np.zeros((NUM_DATA, R.DATA_BITS_PER_BLOCK), dtype=int)
    evm_acc = 0.0
    ideal_pow = 0.0
    n_ideal = 0
    for z in range(NUM_DATA):
        sym288 = placed[z * SYM_LEN:(z + 1) * SYM_LEN]
        rxSym = R.rx_fft(sym288)
        fft_out[z] = rxSym
        Hp = R.ch_estimation_fdm(rxSym, plt[z])
        H = R.interp_fft(Hp)
        Hest = np.zeros(NSC, dtype=complex)
        Hest[1:1 + (NSC - 2)] = H[0:NSC - 2]
        hest_out[z] = Hest
        eq = R.fde_zf(rxSym, Hest)
        eqdata = np.array([eq[idx] for idx in R.DATA_INDX])
        eq_out[z] = eqdata
        ideal = np.array([R.mod_16qam(tx_bits[z][k * 4:(k + 1) * 4])
                          for k in range(R.NUM_DATA_SC)])
        evm_acc += np.sum(np.abs(eqdata - ideal) ** 2)
        ideal_pow += np.sum(np.abs(ideal) ** 2)
        n_ideal += len(ideal)
        for k in range(R.NUM_DATA_SC):
            rx_bits[z][k * 4:(k + 1) * 4] = R.demod_16qam(eqdata[k])

    nbits = tx_bits.size
    nerr = int(np.sum(tx_bits != rx_bits))
    ber = nerr / nbits
    evm_rms = np.sqrt(evm_acc / n_ideal) / np.sqrt(ideal_pow / n_ideal)
    print(f"\n[ber] errored bits = {nerr} / {nbits}  -> BER = {ber:.3e}")
    print(f"[evm] RMS EVM = {evm_rms:.3e}  ({100 * evm_rms:.6f} %)")

    # ---- 5. emit golden files ----
    Q15 = Q15_SCALE

    # 5a. tx_slot_iq.hex : 4160 COMPLETE sync-capable frame {Q,I}
    with open(os.path.join(OUT, "tx_slot_iq.hex"), "w") as f:
        f.write("\n".join(h.upper() for h in frame_hex) + "\n")
    iq_float = np.stack([frame_cplx.real / Q15, frame_cplx.imag / Q15], axis=1)
    np.save(os.path.join(OUT, "tx_slot_iq_float.npy"), iq_float)

    # 5b. tx_slot_iq_4032.hex : synchronizer corrected M_AXIS output
    #     (frame minus 64 pre + 64 post zeros). beat0 = PSS CP start (abs 64).
    frame_4032 = frame_hex[SYNC_START:SYNC_START + FRAME_LEN]
    assert len(frame_4032) == FRAME_LEN
    with open(os.path.join(OUT, "tx_slot_iq_4032.hex"), "w") as f:
        f.write("\n".join(h.upper() for h in frame_4032) + "\n")

    # 5c. per-stage downstream golden (derived from data AS PLACED)
    def dump_complex_hex(path, arr, scale):
        with open(path, "w") as f:
            for c in arr.ravel():
                iv = int(np.round(c.real * scale))
                qv = int(np.round(c.imag * scale))
                f.write(f"{pack_word(iv, qv):08X}\n")

    np.save(os.path.join(OUT, "fft_out_float.npy"), fft_out)
    dump_complex_hex(os.path.join(OUT, "fft_out.hex"), fft_out, Q15)
    np.save(os.path.join(OUT, "hest_float.npy"), hest_out)
    dump_complex_hex(os.path.join(OUT, "hest.hex"), hest_out, Q15)
    np.save(os.path.join(OUT, "eq_out_float.npy"), eq_out)
    dump_complex_hex(os.path.join(OUT, "eq_out.hex"), eq_out, Q15)

    # 5d. pilot ROM (QPSK pilots, same Q15 scale)
    with open(os.path.join(OUT, "pilot_rom.hex"), "w") as f:
        for z in range(NUM_DATA):
            for p in range(R.NUM_PILOTS):
                iv = int(np.round(plt[z, p].real * Q15))
                qv = int(np.round(plt[z, p].imag * Q15))
                f.write(f"{pack_word(iv, qv):08X}\n")
    np.save(os.path.join(OUT, "pilot_rom_float.npy"),
            np.stack([plt.real, plt.imag], axis=2))

    # 5e. bits + index tables
    with open(os.path.join(OUT, "tx_bits.txt"), "w") as f:
        for z in range(NUM_DATA):
            f.write("".join(str(int(b)) for b in tx_bits[z]) + "\n")
    with open(os.path.join(OUT, "rx_bits.txt"), "w") as f:
        for z in range(NUM_DATA):
            f.write("".join(str(int(b)) for b in rx_bits[z]) + "\n")
    with open(os.path.join(OUT, "pilot_indx.txt"), "w") as f:
        f.write(",".join(str(i) for i in R.PLT_INDX) + "\n")
    with open(os.path.join(OUT, "data_indx.txt"), "w") as f:
        f.write(",".join(str(i) for i in R.DATA_INDX) + "\n")

    print(f"\n[done] wrote sync-capable golden to {OUT}")
    return dict(ber=ber, evm=evm_rms, scale=Q15,
                peak_new=m_new[pk_new_idx], peak_new_idx=pk_new_idx,
                peak_fc=m_fc[pk_fc_idx], peak_fc_idx=pk_fc_idx,
                fc_data_rms=fc_data_rms, data_peak=data_peak)


if __name__ == "__main__":
    res = main()
    if res["ber"] != 0.0:
        raise SystemExit(f"FAIL: BER={res['ber']} (must be 0)")
    print("\n=== SUMMARY ===")
    print(f"  Q15 scale          : {res['scale']:.6f}")
    print(f"  data peak (int)    : {res['data_peak']}")
    print(f"  fc_kp0 data RMS    : {res['fc_data_rms']:.4f}")
    print(f"  SYNC peak (NEW)    : {res['peak_new']:.1f} @ abs idx {res['peak_new_idx']}")
    print(f"  SYNC peak (fc_kp0) : {res['peak_fc']:.1f} @ abs idx {res['peak_fc_idx']}")
    print(f"  BER                : {res['ber']:.3e}")
    print(f"  EVM                : {100*res['evm']:.6f} %")
