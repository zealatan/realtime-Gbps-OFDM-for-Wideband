import re
import matplotlib.pyplot as plt

FILE_PATH = "fpga_result.txt"

USE_HEX_SIGNED = True   # True: hex를 signed 32-bit로 해석 / False: decimal 컬럼 사용
SHOW_FRAME_BOUNDARY = True


def hex_to_signed32(hex_str: str) -> int:
    v = int(hex_str, 16) & 0xFFFFFFFF
    if v & 0x80000000:
        v -= 0x100000000
    return v


pattern = re.compile(
    r"\[\s*(\d+)\]\s+(-?\d+)\s+(0x[0-9a-fA-F]+)"
)

x = []
y = []
frame_starts = []

prev_idx = None
frame_no = 0

with open(FILE_PATH, "r") as f:
    for line in f:
        m = pattern.search(line)
        if not m:
            continue

        idx = int(m.group(1))
        dec_val = int(m.group(2))
        hex_val = m.group(3)

        # [0]~[255]만 사용
        if not (0 <= idx <= 255):
            continue

        # frame 경계 감지: index가 다시 작아지면 새 frame
        if prev_idx is not None and idx < prev_idx:
            frame_no += 1
            frame_starts.append(frame_no * 256)

        val = hex_to_signed32(hex_val) if USE_HEX_SIGNED else dec_val
        global_idx = frame_no * 256 + idx

        x.append(global_idx)
        y.append(val)

        prev_idx = idx

# 시작 프레임 표시용
if x:
    frame_starts = [0] + frame_starts

plt.figure(figsize=(16, 5))
plt.plot(x, y, linewidth=1)

if SHOW_FRAME_BOUNDARY:
    for s in frame_starts:
        plt.axvline(s, linestyle="--", alpha=0.25)

plt.xlabel("Global Index")
plt.ylabel("Value")
plt.title("Continuous Plot ([0]~[255] repeated)")
plt.grid(True)
plt.tight_layout()
plt.show()
