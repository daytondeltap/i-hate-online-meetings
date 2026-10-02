from pathlib import Path
root = Path(__file__).resolve().parents[1]
rc = (root / "source/app.rc").read_text()
source = (root / "source/advanced_main_layout.cpp").read_text()
assert "IDD_MAIN DIALOGEX 0,0,360,300" in rc, "main UI must keep its size"
assert "wr.bottom-wr.top+uiPixels(h,48)" in source
assert "if(GetParent(c)!=h)continue" in source, "do not reposition nested controls"
assert "SS_ENDELLIPSIS" in source
assert "uiPixels(win,820),uiPixels(win,570)" in source
assert "GetMessageW" in source and "IsDialogMessageW" in source
print("Windows layout structure passed; native geometry/font checks run separately")
