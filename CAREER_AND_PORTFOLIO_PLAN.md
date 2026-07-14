# 커리어 피벗 & 포트폴리오 플랜

> 작성: 2026-07-14 · Claude와의 논의 정리

---

## 0. TL;DR

- **목적지:** AI Networking (AI 데이터센터 인터커넥트 패브릭) — FPGA-native end.
- **엣지:** DSP RTL + hardware-aware ML (남들 없는 조합).
- **경로:** 저연봉 시장 탈출 → 싱가포르/글로벌 진입 → 거기서 래터럴 점프.
- **포트폴리오:** sim-first(rate-independent) + 보유 하드웨어(Zedboard 느린클럭 + DGX Spark ML). 라인레이트 물리보드는 채용에 불필요.
- **진행:** CD 보상 FDE 알고리즘 물증 완료 (block-FDE BER 1e-4).
- **결정(2026-07-14):** **(B) 옵티컬/네트워킹 DSP** — 강한돈+fit+지속가능. HFT 잭팟은 후에 이 발판에서 점프.

---

## 1. 방향 분석

### 1.1 커리어 사다리

```
OFDM          현 위치 (comms DSP: 등화, 타이밍복원, FEC, 모뎀 L1)
  ↓  등화+CDR = SerDes DSP
SerDes        PAM4, FFE/DFE/CTLE, CDR        ⚠️ 물리층 ASIC-lean
  ↓  SerDes 레인 위 PCS/PMA
Ethernet PHY  64b/66b, RS-FEC(KP4), deskew   ✅ FPGA-native
  ↓  전기→광
Optical PHY   coherent/PAM4 DSP              ⚠️ coherent DSP ASIC-lean
  ↓  링크→패브릭
AI Networking UEC/InfiniBand/RDMA, CPO,      ✅ FPGA-native
              in-network compute, SmartNIC
```

**FPGA-gravity 인사이트 (딜레마 해소):**
- 중간 칸(SerDes 등화, coherent DSP) = **ASIC 중력**.
- 양 끝(Ethernet PHY/MAC, AI networking 데이터플레인/SmartNIC) = **FPGA 중력**.
- → **FPGA에 남을 거면 사다리 중력을 오른쪽 끝으로.** 목적지(AI networking)와 제약(FPGA)이 여기서 일치.
- **연결 실 = FEC** (KP4 RS-FEC ~ 광 oFEC/LDPC) → through-line.

### 1.2 시장 / ROI 비교 (시니어 TC 대략치, 2026-01 기준)

| 경로 | 미국 TC | 싱가포르 | 한국 | fit |
|---|---|---|---|---|
| HFT FPGA | $400K~1M+ | SGD 300~600K+ | 거의 없음 | 진입 최난(C++ 갭) |
| NPU/AI 가속기 | $300~600K | $150~300K | 낮음 | fit 약(comp-arch 경쟁) |
| **옵티컬/네트워킹 DSP** | **$180~350K** | ~$110~190K | 얇음 | ⭐ **fit 최고, 착지 현실적** |
| 무선/모뎀 (현재) | $180~300K | ~$130K | ~$75~135K | 탈출 대상 |

- 냉정한 진실: 하드웨어 DSP는 어느 경로든 **엘리트 ML/AI 소프트웨어**($500K~1M+)보다 중앙값 낮음.
- 잭팟 = HFT(하드웨어 유일 top-money) / NVIDIA류 지분. 둘 다 fit·착지 나쁨.
- **저연봉 시장 탈출만으로 2~3배.** 최적화 = "낮은 시장 탈출 → 좋은 시장 → 점프".
- **EV 관점:** 남는 것 = 액수 × 착지확률. `$600K×10% < $250K×70%`. 천장 말고 기댓값으로.
- 세금/물가: 싱가포르 저세율(~15%) vs 미국 고세율(~45%)+고물가 → 실수령 격차 좁음.

### 1.3 스킬 전이 비교

| 목적 | 전이도 | 비고 |
|---|---|---|
| coherent optical DSP | **~80%** | comms DSP ≈ coherent DSP (CD보상=FDE, carrier recovery=CFO, EQ=EQ) |
| AI networking (FPGA) | 높음 | line-rate 스트리밍/FEC/timing 근육 직결 |
| NPU/RISC-V | ~40–50% | RTL은 O, 아키텍처/dataflow/컴파일러 미보유 |
| HFT | 중 | 네트워킹+C++ 신규 |

---

## 2. 선택한 경로 & 포지셔닝

- **목적지:** AI Networking (FPGA-native), 진입 = **Ethernet PHY/FEC** 또는 데이터플레인.
- **엣지:** DSP RTL + **hardware-aware ML** (neural equalizer 등). 남들 없는 조합 → "AI 흐름" 탑승.
- **지역:** 저비용 sprint 베이스 → **싱가포르/글로벌** 타깃.
- **내러티브:** *"모뎀/FPGA → PHY 시스템 → [옵티컬/네트워킹 DSP + ML], 물증은 이 포트폴리오."*

### 타깃 회사
- 글로벌: Marvell(Inphi), Broadcom, Nvidia(networking), Ciena, Cisco, Arista.
- 계측: Keysight, VIAVI, Anritsu(일), R&S.
- APAC 현실 타깃: 위 회사들 싱가포르/일본 설계센터.

---

## 3. 포트폴리오 플랜

### 3.1 하드웨어 현실 (보유 킷)

| 장비 | 정체 | 판정 |
|---|---|---|
| Zedboard (Zynq-7020) | 소형 FPGA, **MGT 없음**, 1GbE | ❌ 라인레이트 SerDes/PHY 물리 데모 불가 / ✅ 느린클럭 기능 데모 O |
| AD9361 | 무선 RFIC(≤56MHz) | ❌ 무선 전용 |
| DGX Spark (GB10) | AI 컴퓨트 128GB | ⚠️ FPGA 아님 / ✅ **ML 학습에 최적** |

**핵심:** 세 장비 중 **프로그래머블 고속 SerDes 없음** → 라인레이트 물리 데모 불가.
**그러나 불필요:** 기능 RTL 검증은 **rate-independent** (sim + 느린 Zedboard로 증명). 라인레이트 물리는 *회사 랩*이 제공.

### 3.2 빌드 대상

1. **CD 보상 FDE** (완료, 아래 §4) — PHY DSP 근육 증명.
2. **RS-FEC (KP4) 디코더 RTL** — Ethernet PHY 핵심, FPGA-native, FEC through-line. ← **목적지 직결, 추천 다음 스텝.**
3. **Neural equalizer** (DGX Spark 학습) — hardware-aware ML 엣지 증명.

### 3.3 검증 원칙
- **sim-first, rate-independent.** 4-SPC 설계 시 느린 클럭(예: 5 MHz)으로 기능 검증 = 병렬 아키텍처 실증.
- 채용 포트폴리오엔 STA(실제 파트) / 라인레이트 HIL 불필요.
- 필요시 후에 **AWS F2** 또는 중고 SFP+ 보드(KCU105/ZCU106/Alveo U50).

---

## 4. 진행 상황

### CD 보상 FDE (2026-07-14 완료)
`coherent_optical_dsp/ref/cd_comp_ref.py` — 80 km SMF CD를 256-pt overlap-save FDE로 보상.

```
no compensation        BER = 4.47e-01   (CD가 신호 파괴)
ideal full-signal FDE  BER = 0.00e+00
overlap-save block FDE BER = 1.00e-04   ← RTL 방식, PASS
```
산출물: `golden/cd_coeff_q15.hex`, `fde_in_q15.hex`, `fde_out_q15.hex` (RTL 검증용 ROM/golden).
재활용 근거: rx_fft_frontend(FFT) + per-bin complex multiply = OFDM RX FDE와 동일 기계.

### CD 보상 RTL 코어 (2026-07-14 완료, 검증됨)
`rtl/cd_fde_mult.v` — per-bin complex multiply(× CD 계수 ROM), 2-stage 파이프라인, Q15 round/saturate.
`tb/tb_cd_fde_mult.v` (iverilog): **1024 bins checked, 0 errors, maxerr 2 LSB → PASS.**
(2 LSB = float golden vs fixed-point RTL 반올림 차. RTL이 레퍼런스 재현.)

---

## 5. 열린 결정 & 다음 스텝

- [x] **목표 1순위 확정 → (B) 옵티컬/네트워킹 DSP.** (강한돈+fit+지속가능; HFT 잭팟은 후에 이 발판에서 점프)
- [ ] 포트폴리오 다음 산출물: **RS-FEC 디코더**(목적지 직결) vs **CD comp에 neural EQ 얹기**(엣지 증명). → 추천: RS-FEC.
- [ ] 이력서/LinkedIn을 "DSP + hardware-aware ML" 내러티브로 리라이트.
- [ ] 타깃 3사 압축 + 인터뷰 특화 준비.
- [ ] (선택) 포트폴리오를 독립 public repo로 분리.

---

## 부록 A. 재사용 기술 인사이트 (OFDM repo 논의)

- **Multi-SPC 저속검증:** 진짜 4-SPC RTL을 5 MHz(=20 Msps)로 돌리면 병렬 아키텍처가 기능 검증됨(rate-independent). 넘어가지 않는 것: 250 MHz STA, wideband 채널 robustness, 프론트엔드 IP rate 규칙, 4-wide 입력 패킹.
- **Feedback-bound 블록** (파이프라인으로 못 품 → 알고리즘 재구조화 필요): `moving_avg_optimized`(running_sum), `streaming_cp_autocorr`/`auto_corr`, `sliding_window_sum`, `nco_phase_gen`(phase acc), `peak_detector`(argmax). 대응: parallel-prefix / block-accumulate / C-slow.
- **메모리-latency 블로커:** `meyr_sync_capture` LUTRAM combinational read → BRAM registered-read (파이프라인 아님, 아키텍처 변경).
- **이미 feed-forward(재사용 용이):** CORDIC(언롤됨), complex_mult, FFT(IP), demap, EQ, CE.
- **timing closure ≠ 파이프라인 만능:** feedback 루프·routing congestion·하드블록 latency는 파이프라인으로 안 풀림.
- **mod_sel 주의:** RX 경로에서 순수 passthrough(프레임 태깅 없음) → on-the-fly 컨스텔레이션 전환 시 경계 프레임 에러. zero-error 전환은 per-frame mod 태깅 필요.
- **ML-PHY(DeepRx) 하이브리드:** DeepRx는 CE/EQ/demap만 대체(sync/CFO/FFT는 클래식 유지). 실무 = front-end 클래식 + downstream NN. FPGA는 Versal AIE가 현실 타깃.
```
