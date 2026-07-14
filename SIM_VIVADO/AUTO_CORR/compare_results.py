import numpy as np
import os

def load_hex_data(filename, cols=1):
    """Hex 파일을 로드하여 정수 배열로 변환 (x는 0으로 처리)"""
    if not os.path.exists(filename):
        print(f"Warning: {filename} not found.")
        return None
    
    data = []
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts: continue
            try:
                # 각 컬럼별로 Hex -> Int 변환
                row = [int(p, 16) if 'x' not in p.lower() else 0 for p in parts]
                # 32비트 Signed 처리
                row = [v - (1 << 32) if v & (1 << 31) else v for v in row]
                data.append(row if cols > 1 else row[0])
            except ValueError:
                continue
    return np.array(data)

def find_best_offset(gold, rtl):
    """Cross-correlation을 이용해 RTL 데이터의 지연(Offset)을 찾음"""
    # 1차원 데이터 기준 (Metric 등)
    g = gold.flatten() if gold.ndim > 1 else gold
    r = rtl.flatten() if rtl.ndim > 1 else rtl
    
    # 신호가 유효한 구간(값이 있는 구간) 추출
    correlation = np.correlate(r, g, mode='full')
    return np.argmax(correlation) - (len(g) - 1)

def analyze_stage(stage_name, gold_file, rtl_file, cols=1):
    print(f"\n--- Analyzing Stage: {stage_name} ---")
    gold = load_hex_data(gold_file, cols)
    rtl = load_hex_data(rtl_file, cols)
    
    if gold is None or rtl is None: return

    # Metric이나 Mag 단계는 음수가 나올 수 없으므로(RTL 클리핑) Gold도 0으로 클리핑
    if "final" in stage_name.lower() or "mag" in stage_name.lower():
        gold = np.maximum(gold, 0)

    # 오프셋 탐색 (최종 Metric 기준으로 탐색한 오프셋을 공유하거나 개별 탐색)
    # 여기서는 각 파일별로 최적의 매칭 포인트를 찾습니다.
    ref_gold = gold[:, 0] if cols > 1 else gold
    ref_rtl = rtl[:, 0] if cols > 1 else rtl
    offset = find_best_offset(ref_gold, ref_rtl)
    print(f"Detected Latency: {offset} samples")

    if offset < 0:
        print("Error: RTL data length is shorter than Gold or sync failed.")
        return

    # 동기화된 데이터 슬라이싱
    rtl_sync = rtl[offset : offset + len(gold)]
    compare_len = min(len(gold), len(rtl_sync))
    
    # 오차 계산
    diff = gold[:compare_len] - rtl_sync[:compare_len]
    max_err = np.max(np.abs(diff))
    
    if max_err == 0:
        print(f"[SUCCESS] {stage_name}: Perfect Match!")
    else:
        print(f"[MISMATCH] {stage_name}: Max Difference = {max_err}")
        # 처음 3개의 오차 지점 출력
        count = 0
        for i in range(compare_len):
            if np.any(diff[i] != 0):
                print(f"  Line {i}: Gold={gold[i]}, RTL={rtl_sync[i]}")
                count += 1
                if count >= 3: break

def main():
    # 1. 상관 및 에너지 평균 단계 비교 (I, Q, Energy 3컬럼)
    analyze_stage("Auto Correlation & Energy", "gold_auto_corr.txt", "rtl_res_auto_corr.txt", cols=3)
    
    # 2. 크기 근사 단계 비교 (|R|)
    analyze_stage("Magnitude Approximation", "gold_mag_approx.txt", "rtl_res_mag_approx.txt", cols=1)
    
    # 3. 최종 Van de Beek Metric 비교
    analyze_stage("Final VDB Metric", "gold_van_de_beek.txt", "rtl_res_final_vdb.txt", cols=1)

if __name__ == "__main__":
    main()
