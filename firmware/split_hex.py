#!/usr/bin/env python3
# Split a 32-bit-per-word hex (exe.hex) into two 16-bit hex files:
#   out_lo = bits [15:0]  (last 4 hex digits)  -> ram_lo
#   out_hi = bits [31:16] (first 4 hex digits) -> ram_hi
import sys

src, out_lo, out_hi = sys.argv[1], sys.argv[2], sys.argv[3]
lo, hi = [], []
for raw in open(src):
    s = raw.strip()
    if not s:
        continue
    if s.startswith("@"):        # readmemh address directive -> keep in both
        lo.append(s); hi.append(s); continue
    s = s.zfill(8)
    hi.append(s[0:4])
    lo.append(s[4:8])
open(out_lo, "w").write("\n".join(lo) + "\n")
open(out_hi, "w").write("\n".join(hi) + "\n")
