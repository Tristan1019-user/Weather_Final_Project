
import re, os, datetime

CT_OFFSET = -5

now_ct = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=CT_OFFSET, minutes=3)
hh = now_ct.hour
mm = now_ct.minute
ss = now_ct.second
dd = now_ct.day
mo = now_ct.month
yy = now_ct.year

m0,m1 = mo//10, mo%10
d0,d1 = dd//10, dd%10
y0=(yy//1000)%10; y1=(yy//100)%10; y2=(yy//10)%10; y3=yy%10

vhd_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vga_dashboard.vhd")

with open(vhd_path, "r") as f:
    content = f.read()

# --- Patch clock signal initialisers (anchored to PATCHED_ comments) ---
content = re.sub(r'(signal hour_count\s*:.*?:=\s*)\d+(?=\s*;.*?PATCHED_HOUR)',
                 rf'\g<1>{hh}', content)
content = re.sub(r'(signal min_count\s*:.*?:=\s*)\d+(?=\s*;.*?PATCHED_MIN)',
                 rf'\g<1>{mm}', content)
content = re.sub(r'(signal sec_count\s*:.*?:=\s*)\d+(?=\s*;.*?PATCHED_SEC)',
                 rf'\g<1>{ss}', content)

# --- Patch date ---
date_pattern = (
    r'(when\s+0\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
    r'(;\s*when\s+1\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
    r'(;\s*when\s+2\s*=>\s*hdr_ascii\s*<=\s*46;\s*when\s+3\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
    r'(;\s*when\s+4\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
    r'(;\s*when\s+5\s*=>\s*hdr_ascii\s*<=\s*46;\s*when\s+6\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
    r'(;\s*when\s+7\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
    r'(;\s*when\s+8\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
    r'(;\s*when\s+9\s*=>\s*hdr_ascii\s*<=\s*48\+)\d+'
)
date_replacement = (
    rf'\g<1>{m0}\g<2>{m1}\g<3>{d0}\g<4>{d1}'
    rf'\g<5>{y0}\g<6>{y1}\g<7>{y2}\g<8>{y3}'
)
new_content = re.sub(date_pattern, date_replacement, content, flags=re.IGNORECASE)
date_ok = new_content != content
if not date_ok:
    print("WARNING: date pattern did not match - check vga_dashboard.vhd date case statement")
content = new_content

with open(vhd_path, "w") as f:
    f.write(content)

print(f"SUCCESS: Central Time  {hh:02d}:{mm:02d}:{ss:02d}")
print(f"         Date          {mo:02d}.{dd:02d}.{yy}")
print(f"         Date patched: {date_ok}")
print("Compile in Quartus NOW.")
