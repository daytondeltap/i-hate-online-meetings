#define wWinMain applicationEntryPoint
#include "advanced_main_layout.cpp"
#undef wWinMain
#include <cstdio>
#include <stdexcept>

static int failures=0;
static void check(bool ok,const char* message){if(!ok){fprintf(stderr,"FAIL: %s\n",message);++failures;}}
static void snapshot(HWND h,const wchar_t* file){
 RECT r{};GetClientRect(h,&r);HDC dc=GetDC(h),mem=CreateCompatibleDC(dc);HBITMAP bmp=CreateCompatibleBitmap(dc,r.right,r.bottom);auto old=SelectObject(mem,bmp);PrintWindow(h,mem,PW_CLIENTONLY);SelectObject(mem,old);
 BITMAPINFO bi{};bi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);bi.bmiHeader.biWidth=r.right;bi.bmiHeader.biHeight=-r.bottom;bi.bmiHeader.biPlanes=1;bi.bmiHeader.biBitCount=32;bi.bmiHeader.biCompression=BI_RGB;std::vector<BYTE>pixels((size_t)r.right*r.bottom*4);GetDIBits(dc,bmp,0,r.bottom,pixels.data(),&bi,DIB_RGB_COLORS);
 BITMAPFILEHEADER fh{};fh.bfType=0x4d42;fh.bfOffBits=sizeof(fh)+sizeof(bi.bmiHeader);fh.bfSize=fh.bfOffBits+(DWORD)pixels.size();FILE*f=_wfopen(file,L"wb");if(f){fwrite(&fh,sizeof(fh),1,f);fwrite(&bi.bmiHeader,sizeof(bi.bmiHeader),1,f);fwrite(pixels.data(),pixels.size(),1,f);fclose(f);}else check(false,"write screenshot");DeleteObject(bmp);DeleteDC(mem);ReleaseDC(h,dc);
}
static void audit(HWND h){
 RECT bounds{};GetClientRect(h,&bounds);std::vector<HWND>children;
 for(HWND c=GetWindow(h,GW_CHILD);c;c=GetWindow(c,GW_HWNDNEXT))if(IsWindowVisible(c))children.push_back(c);
 for(size_t i=0;i<children.size();++i){HWND c=children[i];RECT r{};GetWindowRect(c,&r);MapWindowPoints(HWND_DESKTOP,h,(POINT*)&r,2);wchar_t cls[64]{},label[4096]{};GetClassNameW(c,cls,64);GetWindowTextW(c,label,4096);
  if(r.left<0||r.top<0||r.right>bounds.right||r.bottom>bounds.bottom){fwprintf(stderr,L"outside: %ls id=%d\n",label,GetDlgCtrlID(c));check(false,"control outside client area");}
  for(size_t j=0;j<i;++j){RECT b{},overlap{};GetWindowRect(children[j],&b);MapWindowPoints(HWND_DESKTOP,h,(POINT*)&b,2);if(IntersectRect(&overlap,&r,&b)){fwprintf(stderr,L"overlap: %ls id=%d with id=%d\n",label,GetDlgCtrlID(c),GetDlgCtrlID(children[j]));check(false,"native sibling rectangles overlap");}}
  if(!*label||(_wcsicmp(cls,L"STATIC")&&_wcsicmp(cls,L"BUTTON")))continue;
  LONG_PTR st=GetWindowLongPtrW(c,GWL_STYLE);if(!_wcsicmp(cls,L"STATIC")&&(st&SS_ELLIPSISMASK))continue;
  HDC dc=GetDC(c);auto font=(HFONT)SendMessageW(c,WM_GETFONT,0,0);auto old=SelectObject(dc,font);RECT needed{0,0,r.right-r.left,r.bottom-r.top};
  if(!_wcsicmp(cls,L"BUTTON")){SIZE extent{};GetTextExtentPoint32W(dc,label,(int)wcslen(label),&extent);int padding=(st&BS_TYPEMASK)==BS_AUTOCHECKBOX?advanced::uiPixels(h,22):advanced::uiPixels(h,16);check(extent.cx+padding<=r.right-r.left,"button caption clipped");}
  else {DrawTextW(dc,label,-1,&needed,DT_CALCRECT|DT_WORDBREAK|DT_NOPREFIX);if(needed.bottom>r.bottom-r.top){fwprintf(stderr,L"clipped: %ls need=%ld height=%ld\n",label,needed.bottom,r.bottom-r.top);check(false,"static text clipped");}}
  SelectObject(dc,old);ReleaseDC(c,dc);
 }
}
static VOID CALLBACK editorTimer(HWND h,UINT,UINT_PTR id,DWORD){if(!advanced::editor)return;KillTimer(h,id);audit(advanced::editor);snapshot(advanced::editor,L"windows-config.bmp");DestroyWindow(advanced::editor);}
static void filterTests(){
 using namespace advanced;wchar_t exe[32768]{};GetModuleFileNameW(nullptr,exe,32768);
 for(int protocol:{1,2})for(int direction:{0,1,2})for(const wchar_t*remote:{L"192.0.2.99/32",L"2001:db8::99/128"}){
  Preset p;p.app=exe;p.protocol=protocol;p.direction=direction;p.localPort=50001;p.remote=remote;p.remotePort=443;advanced::Backend b(p);DWORD e=b.init();check(e==0,"WFP session/app identity initialization");if(e){fprintf(stderr,"WFP init=%lu\n",e);continue;}e=b.change(true);check(e==0,"WFP filter installation");if(e){fprintf(stderr,"WFP install=%lu\n",e);continue;}
  check(b.ids.size()==(direction==0?2u:1u),"WFP selected family/direction count");auto ids=b.ids;
  for(auto id:ids){FWPM_FILTER0*f=nullptr;e=FwpmFilterGetById0(b.engine,id,&f);check(e==0&&f,"WFP read-back");if(f){bool app=false;for(UINT32 j=0;j<f->numFilterConditions;++j){auto&c=f->filterCondition[j];if(IsEqualGUID(c.fieldKey,NT_FWPM_CONDITION_ALE_APP_ID)){app=c.conditionValue.type==FWP_BYTE_BLOB_TYPE&&c.conditionValue.byteBlob->size==b.appId->size&&memcmp(c.conditionValue.byteBlob->data,b.appId->data,b.appId->size)==0;}}check(app&&f->numFilterConditions==5,"WFP app identity AND all endpoint conditions");FwpmFreeMemory0((void**)&f);}}
  check(b.change(false)==0,"WFP unblock");for(auto id:ids){FWPM_FILTER0*f=nullptr;check(FwpmFilterGetById0(b.engine,id,&f)!=0,"WFP removal verified");if(f)FwpmFreeMemory0((void**)&f);}check(b.restore()==0,"WFP session cleanup");
 }
 ParsedRemote parsed;check(!parseRemote(L"192.0.2.1/-1",parsed),"negative CIDR rejected");check(!parseRemote(L"192.0.2.1/33",parsed),"IPv4 prefix rejected");check(!parseRemote(L"::1/129",parsed),"IPv6 prefix rejected");
}
int wmain(){
 SetProcessDPIAware();WSADATA ws{};WSAStartup(MAKEWORD(2,2),&ws);INITCOMMONCONTROLSEX cc{sizeof(cc),ICC_WIN95_CLASSES};InitCommonControlsEx(&cc);stopEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);doneEvent=CreateEventW(nullptr,TRUE,TRUE,nullptr);
 HWND h=CreateDialogParamW(GetModuleHandleW(nullptr),MAKEINTRESOURCEW(IDD_MAIN),nullptr,advancedDialog,0);check(h!=nullptr,"main window creation");if(h){ShowWindow(h,SW_SHOW);UpdateWindow(h);audit(h);snapshot(h,L"windows-main.bmp");for(int mode=0;mode<6;++mode){SendDlgItemMessageW(h,MODE,CB_SETCURSEL,mode,0);advancedDialog(h,WM_COMMAND,MAKEWPARAM(MODE,CBN_SELCHANGE),0);audit(h);}SetTimer(h,777,100,editorTimer);advanced::showEditor();check(IsWindowEnabled(h),"main window restored after configuration");DestroyWindow(h);}
 filterTests();CloseHandle(stopEvent);CloseHandle(doneEvent);WSACleanup();printf("Native UI and WFP checks: %d failures\n",failures);return failures?1:0;
}
