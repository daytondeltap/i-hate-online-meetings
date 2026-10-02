from pathlib import Path
root = Path(__file__).resolve().parents[1]
source = (root / "dist/AdvancedMain.swift").read_text()
assert "width:520,height:500" in source, "main UI must keep its size"
assert "width:840,height:480" in source
assert "add(rf,144,300,400)" in source
assert 'lab("Remote port",596,305,100)' in source
assert "window.beginSheet" in source
assert "maximumNumberOfLines=2" in source
print("Mac layout structure passed; native geometry/font checks run separately")
