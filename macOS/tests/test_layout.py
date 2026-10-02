from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "dist" / "AdvancedMain.swift").read_text(encoding="utf-8")

required = [
    "width:520,height:500",
    "place(advancedCheck,16,462,180)",
    "place(configureButton,404,456,100)",
    "place(adapterBox,16,420,380)",
    "place(refreshButton,404,420,100)",
    "place(modeBox,16,380,488)",
    "place(behaviorBox,16,340,488)",
    "place(offField,200,258,140)",
    "place(offMax,360,258,144)",
    "place(onField,200,218,140)",
    "place(onMax,360,218,144)",
    "place(hotKeyBox,70,138,320)",
    "place(testButton,404,138,100)",
    "place(startButton,16,92,238,30)",
    "place(stopButton,266,92,238,30)",
    "place(detailLabel,16,12,488,42)",
    "width:760,height:530",
    "add(af,96,442,520)",
    "add(browse,626,442,118)",
    "add(proto,90,394,132)",
    "add(dir,316,394,150)",
    "add(lp,636,394,108)",
    "add(rf,128,346,430)",
    "add(rp,636,346,108)",
    "add(flows,16,250,728)",
    "add(note,16,156,728,74)",
    "add(save,534,96,100,30)",
    "add(close,644,96,100,30)",
]
for needle in required:
    assert needle in source, f"expanded layout fragment missing: {needle}"


def gap(left, right):
    lx, lw = left
    rx, _ = right
    return rx - (lx + lw)

# Main-window horizontal spacing.
assert gap((16, 380), (404, 100)) >= 8
assert gap((200, 140), (360, 144)) >= 20
assert gap((70, 320), (404, 100)) >= 14
assert gap((16, 238), (266, 238)) >= 12

# Advanced-editor horizontal spacing.
assert gap((96, 520), (626, 118)) >= 10
assert gap((90, 132), (316, 150)) >= 90
assert gap((316, 150), (636, 108)) >= 170
assert gap((128, 430), (636, 108)) >= 78
assert gap((534, 100), (644, 100)) >= 10

# Vertical row bands. All values are lower-edge/height pairs in AppKit coordinates.
main_rows = [(12, 42), (60, 21), (92, 30), (138, 24), (178, 24), (218, 24), (258, 24), (300, 24), (340, 24), (380, 24), (420, 24), (456, 30)]
for (y, h), (ny, nh) in zip(main_rows, main_rows[1:]):
    assert ny - (y + h) >= 4, f"main UI vertical spacing regression: {y}+{h} -> {ny}"

editor_rows = [(96, 30), (156, 74), (250, 24), (298, 24), (346, 24), (394, 24), (442, 24), (486, 24)]
for (y, h), (ny, nh) in zip(editor_rows, editor_rows[1:]):
    assert ny - (y + h) >= 12, f"editor vertical spacing regression: {y}+{h} -> {ny}"

assert "ihatemeetings 1.5.1" in source
print("macOS UI layout checks passed")
