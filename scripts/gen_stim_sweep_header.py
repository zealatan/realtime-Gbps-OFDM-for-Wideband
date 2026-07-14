#!/usr/bin/env python3
import sys
mem=sys.argv[1]; out=sys.argv[2]
words=[l.strip() for l in open(mem) if l.strip()]
with open(out,"w") as f:
    f.write(f"/* auto-generated from {mem} — GPIO-load sweep vector ({len(words)} words) */\n")
    f.write("static const u32 stim_frame[STIM_LEN] = {\n")
    for i in range(0,len(words),8):
        f.write("  "+",".join("0x"+w for w in words[i:i+8])+",\n")
    f.write("};\n")
print(f"wrote {out} ({len(words)} words)")
