from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
rc = (ROOT / "source" / "app.rc").read_text(encoding="utf-8")
layout = (ROOT / "source" / "advanced_main_layout.cpp").read_text(encoding="utf-8")

m = re.search(r"IDD_MAIN DIALOGEX 0,0,(\d+),(\d+)", rc)
assert m, "main dialog dimensions not found"
w, h = map(int, m.groups())
assert w >= 360 and h >= 300, f"main dialog too small: {w}x{h}"
assert 'CAPTION "ihatemeetings 1.5.1"' in rc
assert 'FILEVERSION 1,5,1,0' in rc

required = [
    "wr.bottom-wr.top+48",
    "pt.y+38",
    "10,8,138,20",
    "156,6,92,24",
    "780,570,win,nullptr",
    "94,48,530,26",
    "636,48,108,26",
    "84,88,132,140",
    "308,88,152,140",
    "560,88,184,26",
    "132,128,426,26",
    "662,128,82,26",
    "16,210,728,190",
    "16,410,728,48",
    "536,478,98,30",
    "646,478,98,30",
]
for needle in required:
    assert needle in layout, f"expanded layout fragment missing: {needle}"

# Horizontal spacing checks for the expanded rows. Tuples are (x, width).
def assert_gaps(name, items, minimum=8):
    items = sorted(items)
    for (x, width), (nx, nwidth) in zip(items, items[1:]):
        gap = nx - (x + width)
        assert gap >= minimum, f"{name} overlap/insufficient gap: {gap}px"

assert_gaps("top advanced controls", [(10, 138), (156, 92)])
assert_gaps("application row", [(94, 530), (636, 108)])
assert_gaps("protocol row", [(84, 132), (308, 152), (560, 184)], 20)
assert_gaps("remote row", [(132, 426), (662, 82)], 20)
assert_gaps("advanced action buttons", [(16, 160), (184, 184)])
assert_gaps("editor footer buttons", [(536, 98), (646, 98)])

# Vertical bands are intentionally separated so controls do not touch at normal DPI.
bands = [
    (14, 36),    # preset row
    (48, 74),    # application row
    (88, 114),   # protocol row
    (128, 154),  # remote row
    (170, 200),  # inspector buttons
    (210, 400),  # connection list
    (410, 458),  # note
    (478, 508),  # footer buttons
]
for (top, bottom), (ntop, nbottom) in zip(bands, bands[1:]):
    assert ntop - bottom >= 10, f"vertical bands too close: {bottom} -> {ntop}"

print("Windows UI layout checks passed")
