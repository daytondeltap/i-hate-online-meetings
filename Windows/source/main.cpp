#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define _WIN32_WINNT 0x0601
#include <winsock2.h>
#include <ws2ipdef.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <commctrl.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <devguid.h>
#include <fwpmu.h>
#include "wfp_guids.hpp"
#include <mmsystem.h>
#include <shellapi.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <algorithm>
#include <utility>
#include <set>
#include <cwctype>
#include <cstdio>
#include "resource.h"
#include "cycle.hpp"
#include "meet_ranges.hpp"

static HWND win; static HANDLE stopEvent,doneEvent; static std::thread worker;
static bool running=false,closing=false,recoveryFailed=false,suppressHotkeys=false; static std::wstring configPath,lastError;
static std::atomic<unsigned long long> cycles{0},switches{0};
static std::atomic<int> phase{0}; // 0 ready, 1 off, 2 on, 3 restoring
static ULONGLONG began; static WORD hotkey=VK_F6;
static int hotkeyId=0; static bool manualRun=false,diagnosticRun=false,stopRequested=false,emergencyBound=false;
static HICON smallIcon=nullptr,bigIcon=nullptr;
static bool diagnosticCompleted=false;
struct Adapter { NET_LUID luid; std::wstring name; ULONG type; bool up; };
static std::vector<Adapter> adapters;
static std::wstring txt(int id) { wchar_t s[512]{}; GetDlgItemTextW(win,id,s,512); return s; }
static void text(int id,const std::wstring& s) { SetDlgItemTextW(win,id,s.c_str()); }
static void error(const std::wstring& s) {
 if(!configPath.empty()) {
  auto path=configPath.substr(0,configPath.find_last_of(L"\\"))+L"\\errors.log";
  HANDLE f=CreateFileW(path.c_str(),FILE_APPEND_DATA,FILE_SHARE_READ,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(f!=INVALID_HANDLE_VALUE) {
   LARGE_INTEGER size{};
   if(GetFileSizeEx(f,&size) && size.QuadPart>1024*1024) {CloseHandle(f);f=CreateFileW(path.c_str(),GENERIC_WRITE,FILE_SHARE_READ,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);}
   if(f!=INVALID_HANDLE_VALUE) {SYSTEMTIME t;GetLocalTime(&t);wchar_t stamp[64];swprintf(stamp,64,L"[%04u-%02u-%02u %02u:%02u:%02u] ",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond);
    auto message=std::wstring(stamp)+s+L"\r\n";
    int n=WideCharToMultiByte(CP_UTF8,0,message.c_str(),-1,nullptr,0,nullptr,nullptr);std::vector<char> data(n);
    WideCharToMultiByte(CP_UTF8,0,message.c_str(),-1,data.data(),n,nullptr,nullptr);DWORD written;WriteFile(f,data.data(),(DWORD)n-1,&written,nullptr);CloseHandle(f);}
  }
 }
 bool previous=suppressHotkeys;suppressHotkeys=true;
 MessageBoxW(win,s.c_str(),L"ihatemeetings",MB_OK|MB_ICONERROR);
 suppressHotkeys=previous;
}
static std::wstring sysError(DWORD e) {
 wchar_t* p=nullptr; FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER|FORMAT_MESSAGE_FROM_SYSTEM|FORMAT_MESSAGE_IGNORE_INSERTS,nullptr,e,0,(LPWSTR)&p,0,nullptr);
 std::wstring s=p?p:L"Windows API error"; if(p) LocalFree(p);
 while(!s.empty() && (s.back()==L'\r'||s.back()==L'\n')) s.pop_back();
 wchar_t hex[32]; swprintf(hex,32,L" (0x%08lX)",e); return s+hex;
}
static bool number(int id,uint64_t lo,uint64_t hi,uint64_t& v) {
 auto s=txt(id); if(s.empty()||s.size()>12) return false; v=0;
 for(auto c:s) { if(c<L'0'||c>L'9') return false; v=v*10+c-L'0'; if(v>hi) return false; }
 return v>=lo;
}
static int sel(int id) { return (int)SendDlgItemMessageW(win,id,CB_GETCURSEL,0,0); }
static void add(int id,const std::wstring& s) { SendDlgItemMessageW(win,id,CB_ADDSTRING,0,(LPARAM)s.c_str()); }
static void rate() {
 int mode=sel(MODE);
 if(mode==3||mode==5)text(RATE,L"Hold OFF until the next hotkey press.");
 else if(mode<2&&sel(BEHAVIOR)==1)text(RATE,L"Hotkey toggles OFF / ON; timers are ignored.");
 else {
  uint64_t a,b,x,y;bool random=IsDlgButtonChecked(win,RANDOMTIME)==BST_CHECKED;
  if(!number(OFFMS,10,86400000,a)||!number(ONMS,10,86400000,b)||
    (random&&(!number(OFFMAX,a,86400000,x)||!number(ONMAX,b,86400000,y))))text(RATE,L"Check timing ranges: 10 to 86400000 ms.");
  else {wchar_t label[160];if(random)swprintf(label,160,L"Random: %.2f - %.2f cycles/s target",1000.0/(x+y),1000.0/(a+b));
   else {swprintf(label,160,L"Target: %.2f cycles/s (OFF + ON)",1000.0/(a+b));}
   text(RATE,label);}
 }
 if(mode==0)text(NOTE,L"Selected adapter; includes local network traffic.");
 else if(mode==1)text(NOTE,L"Adapter reconnects may take several seconds.");
 else if(mode<4)text(NOTE,L"Local Zoom client. A meeting kick is not guaranteed.");
 else text(NOTE,L"Browser Meet media only; may remain joined.");
}
static void refresh() {
 NET_LUID old{}; int i=sel(ADAPTER); if(i>=0&&i<(int)adapters.size()) old=adapters[i].luid;
 adapters.clear(); SendDlgItemMessageW(win,ADAPTER,CB_RESETCONTENT,0,0);
 PMIB_IF_TABLE2 table=nullptr; DWORD e=GetIfTable2(&table);
 if(e) { text(STATUS,L"Adapter scan failed"); error(sysError(e)); return; }
 int type=sel(TYPE);
 for(ULONG j=0;j<table->NumEntries;++j) {
  auto& r=table->Table[j];
  if(!r.InterfaceAndOperStatusFlags.HardwareInterface) continue;
  if(r.Type!=IF_TYPE_ETHERNET_CSMACD && r.Type!=IF_TYPE_IEEE80211) continue;
  if(type==1 && r.Type!=IF_TYPE_ETHERNET_CSMACD) continue;
  if(type==2 && r.Type!=IF_TYPE_IEEE80211) continue;
  adapters.push_back({r.InterfaceLuid,r.Alias,r.Type,r.OperStatus==IfOperStatusUp});
 }
 FreeMibTable(table);
 std::stable_sort(adapters.begin(),adapters.end(),[](const Adapter&a,const Adapter&b){return a.up>b.up;});
 wchar_t stored[64]{};
 GetPrivateProfileStringW(L"Settings",L"AdapterGuid",L"",stored,64,configPath.c_str());
 int chosen=0;
 for(size_t j=0;j<adapters.size();++j) {
  auto& a=adapters[j]; add(ADAPTER,a.name+(a.type==IF_TYPE_IEEE80211?L" [Wi-Fi]":L" [Ethernet]")+(a.up?L" - connected":L" - disconnected"));
  if(old.Value && a.luid.Value==old.Value) chosen=(int)j;
  if(!old.Value) {GUID guid{};wchar_t value[64]{};if(!ConvertInterfaceLuidToGuid(&a.luid,&guid)) {StringFromGUID2(guid,value,64);if(wcscmp(stored,value)==0)chosen=(int)j;}}
 }
 SendDlgItemMessageW(win,ADAPTER,CB_SETCURSEL,adapters.empty()?-1:chosen,0);
 text(STATUS,adapters.empty()?L"No matching physical adapters found.":L"Ready");
 EnableWindow(GetDlgItem(win,START),(sel(MODE)>=2 || !adapters.empty())&&!recoveryFailed);
}
static bool sameGuidText(const wchar_t* a,const wchar_t* b) {
 if(!a||!b) return false;
 GUID ga{},gb{}; return SUCCEEDED(CLSIDFromString(a,&ga))&&SUCCEEDED(CLSIDFromString(b,&gb))&&IsEqualGUID(ga,gb);
}
struct DeviceRef { HDEVINFO set=INVALID_HANDLE_VALUE; SP_DEVINFO_DATA data{}; DeviceRef(){data.cbSize=sizeof(data);} };
static void closeDevice(DeviceRef& d) {if(d.set!=INVALID_HANDLE_VALUE){SetupDiDestroyDeviceInfoList(d.set);d.set=INVALID_HANDLE_VALUE;}}
static DWORD findAdapterDevice(const GUID& guid,DeviceRef& out) {
 DWORD e=0; wchar_t wanted[64]{}; if(!StringFromGUID2(guid,wanted,64)) return ERROR_INVALID_DATA;
 HDEVINFO set=SetupDiGetClassDevsW(&GUID_DEVCLASS_NET,nullptr,nullptr,DIGCF_PRESENT);
 if(set==INVALID_HANDLE_VALUE) return GetLastError();
 for(DWORD i=0;;++i) {
  SP_DEVINFO_DATA data{};data.cbSize=sizeof(data);
  if(!SetupDiEnumDeviceInfo(set,i,&data)) {e=GetLastError();break;}
  HKEY key=SetupDiOpenDevRegKey(set,&data,DICS_FLAG_GLOBAL,0,DIREG_DRV,KEY_READ);
  if(key==INVALID_HANDLE_VALUE) continue;
  wchar_t value[128]{}; DWORD type=0,bytes=sizeof(value)-sizeof(wchar_t);
  LONG r=RegQueryValueExW(key,L"NetCfgInstanceId",nullptr,&type,(LPBYTE)value,&bytes);RegCloseKey(key);
  if(r==ERROR_SUCCESS && (type==REG_SZ||type==REG_EXPAND_SZ) && sameGuidText(value,wanted)) {out.set=set;out.data=data;return 0;}
 }
 SetupDiDestroyDeviceInfoList(set);
 return e==ERROR_NO_MORE_ITEMS?ERROR_NOT_FOUND:e;
}
static DWORD deviceState(const SP_DEVINFO_DATA& data,bool enabled) {
 ULONG status=0,problem=0; CONFIGRET cr=CM_Get_DevNode_Status(&status,&problem,data.DevInst,0);
 if(cr!=CR_SUCCESS) return ERROR_GEN_FAILURE;
 if(enabled) return (status&DN_STARTED)?0:ERROR_NOT_READY;
 return (!(status&DN_STARTED) || problem==CM_PROB_DISABLED)?0:ERROR_BUSY;
}
static DWORD waitDeviceState(const SP_DEVINFO_DATA& data,bool enabled,DWORD timeoutMs=8000) {
 ULONGLONG end=GetTickCount64()+timeoutMs; DWORD last=ERROR_TIMEOUT;
 do {last=deviceState(data,enabled);if(!last)return 0;Sleep(100);} while(GetTickCount64()<end);
 return last==ERROR_NOT_READY||last==ERROR_BUSY?ERROR_TIMEOUT:last;
}
static DWORD setAdapterGuid(const GUID& guid,bool enabled) {
 DeviceRef dev; DWORD e=findAdapterDevice(guid,dev); if(e) return e;
 SP_PROPCHANGE_PARAMS p{};p.ClassInstallHeader.cbSize=sizeof(SP_CLASSINSTALL_HEADER);p.ClassInstallHeader.InstallFunction=DIF_PROPERTYCHANGE;
 p.StateChange=enabled?DICS_ENABLE:DICS_DISABLE;p.Scope=DICS_FLAG_GLOBAL;p.HwProfile=0;
 if(!SetupDiSetClassInstallParamsW(dev.set,&dev.data,&p.ClassInstallHeader,sizeof(p))) e=GetLastError();
 else if(!SetupDiCallClassInstaller(DIF_PROPERTYCHANGE,dev.set,&dev.data)) e=GetLastError();
 else e=waitDeviceState(dev.data,enabled);
 closeDevice(dev);return e;
}
// A separate process restores an originally-enabled adapter if the UI crashes.
struct Guard {
 HANDLE process=nullptr,event=nullptr;
 DWORD launch(const GUID& guid) {
  SECURITY_ATTRIBUTES sa{sizeof(sa),nullptr,TRUE};
  event=CreateEventW(&sa,TRUE,FALSE,nullptr);if(!event) return GetLastError();
  HANDLE ready=CreateEventW(&sa,TRUE,FALSE,nullptr);if(!ready) return GetLastError();
  HANDLE parent=nullptr;
  if(!DuplicateHandle(GetCurrentProcess(),GetCurrentProcess(),GetCurrentProcess(),&parent,SYNCHRONIZE,TRUE,0)) {DWORD e=GetLastError();CloseHandle(ready);return e;}
  wchar_t path[32768]{};
  if(!GetModuleFileNameW(nullptr,path,32768)) {DWORD e=GetLastError();CloseHandle(parent);CloseHandle(ready);return e;}
  wchar_t guidText[64]{};if(!StringFromGUID2(guid,guidText,64)){CloseHandle(parent);CloseHandle(ready);return ERROR_INVALID_DATA;}
  std::wstring cmd=L"\""+std::wstring(path)+L"\" --guard "+std::to_wstring((uintptr_t)parent)+L" "+std::to_wstring((uintptr_t)event)+L" "+guidText+L" "+std::to_wstring((uintptr_t)ready);
  STARTUPINFOEXW si{};si.StartupInfo.cb=sizeof(si);SIZE_T bytes=0;
  InitializeProcThreadAttributeList(nullptr,1,0,&bytes);
  std::vector<BYTE> attributes(bytes);si.lpAttributeList=(LPPROC_THREAD_ATTRIBUTE_LIST)attributes.data();
  DWORD e=0;
  if(!InitializeProcThreadAttributeList(si.lpAttributeList,1,0,&bytes)) e=GetLastError();
  else {
   HANDLE inherited[]{parent,event,ready};
   if(!UpdateProcThreadAttribute(si.lpAttributeList,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,inherited,sizeof(inherited),nullptr,nullptr)) e=GetLastError();
   else {
    PROCESS_INFORMATION pi{};
    if(!CreateProcessW(path,&cmd[0],nullptr,nullptr,TRUE,CREATE_NO_WINDOW|EXTENDED_STARTUPINFO_PRESENT,nullptr,nullptr,&si.StartupInfo,&pi)) e=GetLastError();
    else {process=pi.hProcess;CloseHandle(pi.hThread);HANDLE waits[]{ready,process,stopEvent};
     DWORD result=WaitForMultipleObjects(3,waits,FALSE,5000);
     if(result!=WAIT_OBJECT_0) {e=result==WAIT_OBJECT_0+2?ERROR_CANCELLED:result==WAIT_TIMEOUT?ERROR_TIMEOUT:ERROR_PROCESS_ABORTED;SetEvent(event);}
    }
   }
   DeleteProcThreadAttributeList(si.lpAttributeList);
  }
  CloseHandle(parent);CloseHandle(ready);return e;
 }
 bool healthy() const {return process && WaitForSingleObject(process,0)==WAIT_TIMEOUT;}
 void disarm() { if(event) SetEvent(event); }
 ~Guard() { if(process) CloseHandle(process); if(event) CloseHandle(event); }
};
struct Backend {
 NET_LUID luid; GUID adapterGuid{}; int mode; HANDLE engine=nullptr; GUID sub{};
 UINT64 filters[4]{}; bool blocked=false,mayHaveDisabled=false,guardFailed=false;
 Guard guard;
 Backend(NET_LUID l,int m):luid(l),mode(m){}
 DWORD init() {
  MIB_IF_ROW2 row{}; row.InterfaceLuid=luid; DWORD e=GetIfEntry2(&row); if(e) return e;
  if(row.AdminStatus!=NET_IF_ADMIN_STATUS_UP) return ERROR_NOT_READY;
  e=ConvertInterfaceLuidToGuid(&luid,&adapterGuid); if(e) return e;
  if(mode) return guard.launch(adapterGuid);
  FWPM_SESSION0 session{}; session.flags=NT_DYNAMIC_SESSION; session.txnWaitTimeoutInMSec=2000;
  session.displayData.name=(wchar_t*)L"ihatemeetings temporary session";
  e=FwpmEngineOpen0(nullptr,RPC_C_AUTHN_WINNT,nullptr,&session,&engine); if(e) return e;
  RPC_STATUS uuid=UuidCreate(&sub); if(uuid!=RPC_S_OK && uuid!=RPC_S_UUID_LOCAL_ONLY) return uuid;
  FWPM_SUBLAYER0 layer{}; layer.subLayerKey=sub; layer.weight=0xFFFF;
  layer.displayData.name=(wchar_t*)L"ihatemeetings temporary traffic block";
  return FwpmSubLayerAdd0(engine,&layer,nullptr);
 }
 DWORD verifyWfp(bool shouldBlock) {
  if(!engine) return ERROR_INVALID_HANDLE;
  const GUID* layers[]={&NT_FWPM_LAYER_INBOUND_IPPACKET_V4,&NT_FWPM_LAYER_OUTBOUND_IPPACKET_V4,&NT_FWPM_LAYER_INBOUND_IPPACKET_V6,&NT_FWPM_LAYER_OUTBOUND_IPPACKET_V6};
  for(int i=0;i<4;++i) {
   FWPM_FILTER0* f=nullptr; DWORD e=FwpmFilterGetById0(engine,filters[i],&f);
   if(shouldBlock) {
    if(e) return e;
    bool ok=f && f->action.type==FWP_ACTION_BLOCK && IsEqualGUID(f->layerKey,*layers[i]) && IsEqualGUID(f->subLayerKey,sub);
    if(f) FwpmFreeMemory0((void**)&f);
    if(!ok) return ERROR_INVALID_DATA;
   } else {
    if(!e) {if(f)FwpmFreeMemory0((void**)&f);return ERROR_BUSY;}
    if(e!=(DWORD)FWP_E_FILTER_NOT_FOUND) return e;
   }
  }
  return 0;
 }
 DWORD change(bool off) {
  if(mode) { if(off && !guard.healthy()) {guardFailed=true;return ERROR_PROCESS_ABORTED;} if(off) mayHaveDisabled=true; DWORD e=setAdapterGuid(adapterGuid,!off); if(!e&&!off) mayHaveDisabled=false; return e; }
  if(off==blocked) return 0;
  DWORD e=FwpmTransactionBegin0(engine,0); if(e) return e;
  UINT64 ids[4]{};
  const GUID* layers[]={&NT_FWPM_LAYER_INBOUND_IPPACKET_V4,&NT_FWPM_LAYER_OUTBOUND_IPPACKET_V4,&NT_FWPM_LAYER_INBOUND_IPPACKET_V6,&NT_FWPM_LAYER_OUTBOUND_IPPACKET_V6};
  for(int i=0;i<4 && !e;++i) {
   if(!off) { e=FwpmFilterDeleteById0(engine,filters[i]); continue; }
   UINT64 value=luid.Value;
   FWPM_FILTER_CONDITION0 condition{}; condition.fieldKey=NT_FWPM_CONDITION_IP_LOCAL_INTERFACE;
   condition.matchType=FWP_MATCH_EQUAL; condition.conditionValue.type=FWP_UINT64; condition.conditionValue.uint64=&value;
   FWPM_FILTER0 f{}; f.displayData.name=(wchar_t*)L"ihatemeetings offline phase";
   f.layerKey=*layers[i]; f.subLayerKey=sub; f.weight.type=FWP_UINT8; f.weight.uint8=15;
   f.action.type=FWP_ACTION_BLOCK; f.numFilterConditions=1; f.filterCondition=&condition;
   e=FwpmFilterAdd0(engine,&f,nullptr,&ids[i]);
  }
  if(e) { FwpmTransactionAbort0(engine); return e; }
  e=FwpmTransactionCommit0(engine); if(e) return e;
  if(off) std::copy(ids,ids+4,filters);
  e=verifyWfp(off); if(e) return e;
  blocked=off; if(!off) std::fill(filters,filters+4,0); return 0;
 }
 DWORD restore() {
  DWORD e=0;
  if(mode) {
   if(mayHaveDisabled) for(int i=0;i<3;++i) { e=setAdapterGuid(adapterGuid,true); if(!e) {mayHaveDisabled=false; break;} Sleep(200); }
   if(!e) guard.disarm();
  } else if(engine) { e=FwpmEngineClose0(engine); if(!e) {engine=nullptr;blocked=false;} }
  return e;
 }
 ~Backend() { restore(); }
 uint64_t now() {return GetTickCount64();}
 bool cancelled() {
  if(mode && !guard.healthy()) {guardFailed=true;return true;}
  return WaitForSingleObject(stopEvent,0)==WAIT_OBJECT_0;
 }
 void wait(uint32_t ms) {
  const auto end=GetTickCount64()+ms;
  while(!cancelled()) {auto now=GetTickCount64();if(now>=end) break;WaitForSingleObject(stopEvent,(DWORD)std::min<ULONGLONG>(250,end-now));}
 }
 void progress(const cycle::Result&r,bool off) {cycles=r.completed; switches=r.switches; phase=off?1:2;}
};
static std::wstring lowerCopy(std::wstring s) {for(auto& c:s)c=(wchar_t)towlower(c);return s;}
static bool fileExists(const std::wstring& p) {DWORD a=GetFileAttributesW(p.c_str());return a!=INVALID_FILE_ATTRIBUTES && !(a&FILE_ATTRIBUTE_DIRECTORY);}
static std::vector<std::wstring> zoomTargets() {
 std::vector<std::wstring> out;
 auto addPath=[&](const std::wstring& p){if(p.empty()||!fileExists(p))return;for(const auto& e:out)if(_wcsicmp(e.c_str(),p.c_str())==0)return;out.push_back(p);};
 HANDLE snap=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
 if(snap!=INVALID_HANDLE_VALUE) {
  PROCESSENTRY32W pe{};pe.dwSize=sizeof(pe);
  if(Process32FirstW(snap,&pe)) do {
   std::wstring exe=lowerCopy(pe.szExeFile);
   if(exe!=L"zoom.exe" && exe!=L"cpthost.exe") continue;
   HANDLE ph=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pe.th32ProcessID);
   if(!ph) continue;
   wchar_t path[32768]{};DWORD n=32768;
   if(QueryFullProcessImageNameW(ph,0,path,&n)) addPath(path);
   CloseHandle(ph);
  } while(Process32NextW(snap,&pe));
  CloseHandle(snap);
 }
 auto envPath=[&](const wchar_t* name,const wchar_t* suffix){
  wchar_t base[32768]{};DWORD n=GetEnvironmentVariableW(name,base,32768);if(n&&n<32768)addPath(std::wstring(base)+suffix);
 };
 envPath(L"APPDATA",L"\\Zoom\\bin\\Zoom.exe");
 envPath(L"APPDATA",L"\\Zoom\\bin_00\\Zoom.exe");
 envPath(L"LOCALAPPDATA",L"\\Zoom\\bin\\Zoom.exe");
 envPath(L"ProgramFiles",L"\\Zoom\\bin\\Zoom.exe");
 envPath(L"ProgramFiles",L"\\Zoom\\bin_00\\Zoom.exe");
 envPath(L"ProgramFiles(x86)",L"\\Zoom\\bin\\Zoom.exe");
 return out;
}
static std::vector<std::wstring> browserTargets() {
 std::vector<std::wstring> out;HANDLE snap=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
 if(snap==INVALID_HANDLE_VALUE)return out;
 PROCESSENTRY32W pe{};pe.dwSize=sizeof(pe);
 if(Process32FirstW(snap,&pe))do{
  auto exe=lowerCopy(pe.szExeFile);
  if(exe!=L"chrome.exe"&&exe!=L"msedge.exe"&&exe!=L"firefox.exe"&&exe!=L"brave.exe"&&exe!=L"opera.exe"&&exe!=L"vivaldi.exe")continue;
  HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pe.th32ProcessID);if(!process)continue;
  wchar_t path[32768]{};DWORD length=32768;
  if(QueryFullProcessImageNameW(process,0,path,&length)){
   bool duplicate=false;for(auto& existing:out)if(!_wcsicmp(existing.c_str(),path))duplicate=true;
   if(!duplicate)out.emplace_back(path);
  }
  CloseHandle(process);
 }while(Process32NextW(snap,&pe));
 CloseHandle(snap);return out;
}
struct AppBackend {
 bool meet;HANDLE engine=nullptr;GUID sub{};std::vector<FWP_BYTE_BLOB*> appIds;
 struct Filter {UINT64 id;const GUID* layer;FWP_BYTE_BLOB* app;int range;};
 std::vector<Filter> filters;bool blocked=false;
 explicit AppBackend(bool forMeet):meet(forMeet){}
 DWORD init(){
  auto paths=meet?browserTargets():zoomTargets();if(paths.empty())return ERROR_FILE_NOT_FOUND;
  FWPM_SESSION0 session{};session.flags=NT_DYNAMIC_SESSION;session.txnWaitTimeoutInMSec=2000;session.displayData.name=(wchar_t*)L"ihatemeetings temporary application filters";
  DWORD e=FwpmEngineOpen0(nullptr,RPC_C_AUTHN_WINNT,nullptr,&session,&engine);if(e)return e;
  RPC_STATUS uuid=UuidCreate(&sub);if(uuid!=RPC_S_OK&&uuid!=RPC_S_UUID_LOCAL_ONLY)return uuid;
  FWPM_SUBLAYER0 layer{};layer.subLayerKey=sub;layer.weight=0xFFFF;layer.displayData.name=(wchar_t*)L"ihatemeetings local application block";
  e=FwpmSubLayerAdd0(engine,&layer,nullptr);if(e)return e;
  for(auto& path:paths){FWP_BYTE_BLOB* id=nullptr;e=FwpmGetAppIdFromFileName0(path.c_str(),&id);if(e)return e;if(!id)return ERROR_INVALID_DATA;appIds.push_back(id);}
  return 0;
 }
 DWORD verify(bool off){
  if(!engine)return ERROR_INVALID_HANDLE;
  if(off&&filters.empty())return ERROR_NOT_FOUND;
  for(auto& entry:filters){FWPM_FILTER0* f=nullptr;DWORD e=FwpmFilterGetById0(engine,entry.id,&f);
   if(!off){if(f)FwpmFreeMemory0((void**)&f);if(e!=(DWORD)FWP_E_FILTER_NOT_FOUND)return e?e:ERROR_BUSY;continue;}
   if(e)return e;
   auto findCondition=[&](const GUID& key)->FWPM_FILTER_CONDITION0*{if(f)for(UINT32 n=0;n<f->numFilterConditions;++n)if(IsEqualGUID(f->filterCondition[n].fieldKey,key))return &f->filterCondition[n];return nullptr;};
   bool ok=f&&f->action.type==FWP_ACTION_BLOCK&&IsEqualGUID(f->layerKey,*entry.layer)&&IsEqualGUID(f->subLayerKey,sub)&&f->numFilterConditions==(meet?2u:1u);
   if(ok){auto* found=findCondition(NT_FWPM_CONDITION_ALE_APP_ID);if(!found)ok=false;else {auto& c=*found;ok=IsEqualGUID(c.fieldKey,NT_FWPM_CONDITION_ALE_APP_ID)&&c.matchType==FWP_MATCH_EQUAL&&c.conditionValue.type==FWP_BYTE_BLOB_TYPE&&c.conditionValue.byteBlob&&c.conditionValue.byteBlob->size==entry.app->size&&!memcmp(c.conditionValue.byteBlob->data,entry.app->data,entry.app->size);}}
   if(ok&&meet){auto* found=findCondition(NT_FWPM_CONDITION_IP_REMOTE_ADDRESS);if(!found)ok=false;else {auto& c=*found;auto& range=meetRanges[entry.range];ok=IsEqualGUID(c.fieldKey,NT_FWPM_CONDITION_IP_REMOTE_ADDRESS)&&c.matchType==FWP_MATCH_EQUAL;
    if(ok&&range.ipv6){IN6_ADDR ip{};InetPtonW(AF_INET6,range.address,&ip);ok=c.conditionValue.type==FWP_V6_ADDR_MASK&&c.conditionValue.v6AddrMask&&c.conditionValue.v6AddrMask->prefixLength==range.bits&&!memcmp(c.conditionValue.v6AddrMask->addr,&ip,16);}
    else if(ok){IN_ADDR ip{};InetPtonW(AF_INET,range.address,&ip);UINT32 mask=range.bits==32?0xffffffffu:(0xffffffffu<<(32-range.bits));ok=c.conditionValue.type==FWP_V4_ADDR_MASK&&c.conditionValue.v4AddrMask&&c.conditionValue.v4AddrMask->addr==ntohl(ip.S_un.S_addr)&&c.conditionValue.v4AddrMask->mask==mask;}
   }}
   if(f)FwpmFreeMemory0((void**)&f);
   if(!ok)return ERROR_INVALID_DATA;
  }
  return 0;
 }
 DWORD change(bool off){
  if(off==blocked)return 0;
  if(!engine)return ERROR_INVALID_HANDLE;
  DWORD e=FwpmTransactionBegin0(engine,0);if(e)return e;
  std::vector<Filter> created;
  if(!off){for(auto& f:filters){e=FwpmFilterDeleteById0(engine,f.id);if(e)break;}}
  else {
   const GUID* layers[]={&NT_FWPM_LAYER_ALE_AUTH_CONNECT_V4,&NT_FWPM_LAYER_ALE_AUTH_CONNECT_V6,&NT_FWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V4,&NT_FWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V6};
   for(auto* app:appIds){
    if(e)break;
    for(int li=0;li<4&&!e;++li){
     for(int ri=meet?0:-1;ri<(meet?6:0)&&!e;++ri){
      if(meet&&meetRanges[ri].ipv6!=(li%2==1))continue;
      FWPM_FILTER_CONDITION0 c[2]{};c[0].fieldKey=NT_FWPM_CONDITION_ALE_APP_ID;c[0].matchType=FWP_MATCH_EQUAL;c[0].conditionValue.type=FWP_BYTE_BLOB_TYPE;c[0].conditionValue.byteBlob=app;
      FWP_V4_ADDR_AND_MASK v4{};FWP_V6_ADDR_AND_MASK v6{};
      if(meet){auto& range=meetRanges[ri];c[1].fieldKey=NT_FWPM_CONDITION_IP_REMOTE_ADDRESS;c[1].matchType=FWP_MATCH_EQUAL;
       if(range.ipv6){IN6_ADDR ip{};if(InetPtonW(AF_INET6,range.address,&ip)!=1){e=ERROR_INVALID_DATA;break;}memcpy(v6.addr,&ip,16);v6.prefixLength=range.bits;c[1].conditionValue.type=FWP_V6_ADDR_MASK;c[1].conditionValue.v6AddrMask=&v6;}
       else {IN_ADDR ip{};if(InetPtonW(AF_INET,range.address,&ip)!=1){e=ERROR_INVALID_DATA;break;}v4.addr=ntohl(ip.S_un.S_addr);v4.mask=range.bits==32?0xffffffffu:(0xffffffffu<<(32-range.bits));c[1].conditionValue.type=FWP_V4_ADDR_MASK;c[1].conditionValue.v4AddrMask=&v4;}
      }
      FWPM_FILTER0 filter{};filter.displayData.name=(wchar_t*)(meet?L"ihatemeetings Meet media block":L"ihatemeetings Zoom block");filter.layerKey=*layers[li];filter.subLayerKey=sub;filter.weight.type=FWP_UINT8;filter.weight.uint8=15;filter.action.type=FWP_ACTION_BLOCK;filter.numFilterConditions=meet?2:1;filter.filterCondition=c;
      UINT64 id=0;e=FwpmFilterAdd0(engine,&filter,nullptr,&id);if(!e)created.push_back({id,layers[li],app,ri});
     }
    }
   }
  }
  if(e){FwpmTransactionAbort0(engine);return e;}
  e=FwpmTransactionCommit0(engine);if(e){FwpmTransactionAbort0(engine);return e;}
  blocked=off;if(off)filters=std::move(created);
  e=verify(off);if(!e&&!off)filters.clear();return e;
 }
 DWORD restore(){
  if(engine){DWORD e=FwpmEngineClose0(engine);if(e)return e;engine=nullptr;blocked=false;filters.clear();}
  for(auto* id:appIds)if(id)FwpmFreeMemory0((void**)&id);
  appIds.clear();return 0;
 }
 ~AppBackend(){restore();}
 uint64_t now(){return GetTickCount64();}
 bool cancelled(){return WaitForSingleObject(stopEvent,0)==WAIT_OBJECT_0;}
 void wait(uint32_t ms){WaitForSingleObject(stopEvent,ms);}
 void progress(const cycle::Result&r,bool off){cycles=r.completed;switches=r.switches;phase=off?1:2;}
};
static void lockControls(bool lock) {
 for(int id:{TYPE,ADAPTER,REFRESH,MODE,BEHAVIOR,OFFMS,ONMS,OFFMAX,ONMAX,RANDOMTIME,COUNT,FOREVER,LIMIT,HOTKEY,APPLY,START,TESTMODE}) EnableWindow(GetDlgItem(win,id),!lock);
 EnableWindow(GetDlgItem(win,STOP),lock);
 if(!lock) {EnableWindow(GetDlgItem(win,COUNT),IsDlgButtonChecked(win,FOREVER)!=BST_CHECKED); EnableWindow(GetDlgItem(win,START),(sel(MODE)>=2 || !adapters.empty())&&!recoveryFailed);}
}
static std::wstring keyName(WORD hk) {
 std::wstring s; BYTE mods=HIBYTE(hk),vk=LOBYTE(hk);
 if(mods&HOTKEYF_CONTROL) s+=L"Ctrl+";
 if(mods&HOTKEYF_ALT) s+=L"Alt+";
 if(mods&HOTKEYF_SHIFT) s+=L"Shift+";
 wchar_t name[80]{}; LONG scan=(LONG)MapVirtualKeyW(vk,MAPVK_VK_TO_VSC)<<16;
 if(mods&HOTKEYF_EXT) scan|=1<<24;
 GetKeyNameTextW(scan,name,80); return s+name;
}
static bool bindHotkey(WORD hk,bool initial=false) {
 BYTE vk=LOBYTE(hk),m=HIBYTE(hk);
 if(!vk || vk==VK_CONTROL || vk==VK_MENU || vk==VK_SHIFT) {error(L"Choose a key or a modifier + key combination."); return false;}
 UINT mods=MOD_NOREPEAT;
 if(m&HOTKEYF_CONTROL) mods|=MOD_CONTROL;
 if(m&HOTKEYF_ALT) mods|=MOD_ALT;
 if(m&HOTKEYF_SHIFT) mods|=MOD_SHIFT;
 if(vk==VK_F12 && (mods&(MOD_CONTROL|MOD_ALT))==(MOD_CONTROL|MOD_ALT)) {error(L"Ctrl+Alt+F12 is reserved for emergency stop.");return false;}
 if(!initial && hotkeyId && hk==hotkey) return true;
 int candidate=hotkeyId==1?3:1;
 if(!RegisterHotKey(win,candidate,mods,vk)) {error(L"That hotkey is unavailable. The previous binding has been kept.");return false;}
 if(hotkeyId) UnregisterHotKey(win,hotkeyId);
 hotkeyId=candidate;hotkey=hk; return true;
}
static void buttonLabel() {
 int mode=sel(MODE); bool manual=(mode==3||mode==5) || (mode<2 && sel(BEHAVIOR)==1);
 std::wstring label;
 if(mode==2) label=running?L"Stop Zoom Lag":L"Start Zoom Lag";
 else if(mode==3) label=running?L"Restore Zoom":L"Disconnect Zoom";
 else if(mode==4) label=running?L"Stop Meet Lag":L"Start Meet Lag";
 else if(mode==5) label=running?L"Restore Meet":L"Block Meet";
 else label=manual?(running?L"Switch ON":L"Switch OFF"):L"Start";
 if(hotkeyId) label+=L"  ("+keyName(hotkey)+L")";
 text(START,label);
}
static void behaviorControls() {
 if(running) return;
 int mode=sel(MODE);bool zoom=mode>=2;bool manual=(mode==3||mode==5) || (!zoom&&sel(BEHAVIOR)==1);
 EnableWindow(GetDlgItem(win,BEHAVIOR),!zoom);
 for(int id:{TYPE,ADAPTER,REFRESH}) EnableWindow(GetDlgItem(win,id),!zoom);
 for(int id:{OFFMS,ONMS,RANDOMTIME,COUNT,FOREVER,LIMIT}) EnableWindow(GetDlgItem(win,id),!manual);
 if(!manual) EnableWindow(GetDlgItem(win,COUNT),IsDlgButtonChecked(win,FOREVER)!=BST_CHECKED);
 bool random=!manual&&IsDlgButtonChecked(win,RANDOMTIME)==BST_CHECKED;
 EnableWindow(GetDlgItem(win,OFFMAX),random);EnableWindow(GetDlgItem(win,ONMAX),random);
 EnableWindow(GetDlgItem(win,START),(zoom || !adapters.empty())&&!recoveryFailed);
 buttonLabel();
 rate();
}
static void saveSettings() {
 if(configPath.empty()) return;
 int index=sel(ADAPTER);
 if(index>=0 && index<(int)adapters.size()) {GUID guid{};wchar_t value[64]{};if(!ConvertInterfaceLuidToGuid(&adapters[index].luid,&guid)) {StringFromGUID2(guid,value,64);WritePrivateProfileStringW(L"Settings",L"AdapterGuid",value,configPath.c_str());}}
 for(int id:{OFFMS,ONMS,OFFMAX,ONMAX,COUNT,LIMIT}) WritePrivateProfileStringW(L"Settings",std::to_wstring(id).c_str(),txt(id).c_str(),configPath.c_str());
 for(auto p:std::vector<std::pair<int,int>>{{MODE,sel(MODE)},{BEHAVIOR,sel(BEHAVIOR)},{TYPE,sel(TYPE)},{FOREVER,IsDlgButtonChecked(win,FOREVER)==BST_CHECKED},{HOTKEY,(int)hotkey},{RANDOMTIME,IsDlgButtonChecked(win,RANDOMTIME)==BST_CHECKED}})
  WritePrivateProfileStringW(L"Settings",std::to_wstring(p.first).c_str(),std::to_wstring(p.second).c_str(),configPath.c_str());
}
static void start() {
 if(running || closing) return;
 if(recoveryFailed) {error(L"Restoration failed. Close ihatemeetings to release its temporary session and let recovery retry before starting another run.");return;}
 int mode=sel(MODE);int i=sel(ADAPTER);
 if(mode<2 && (i<0||i>=(int)adapters.size())) {error(L"Select a network adapter first.");return;}
 uint64_t a=500,b=500,c=0,d=0;
 bool zoomLag=mode==2||mode==4, zoomKick=mode==3||mode==5;
 bool manual=zoomKick || (!zoomLag && sel(BEHAVIOR)==1);
 bool unlimited=IsDlgButtonChecked(win,FOREVER)==BST_CHECKED;
 if(!manual && (!number(OFFMS,10,86400000,a)||!number(ONMS,10,86400000,b)||(!unlimited&&!number(COUNT,1,1000000000,c))||!number(LIMIT,0,604800,d))) {
  error(L"Intervals: 10 to 86400000 ms.\nCycles: 1 to 1000000000, or Until stopped.\nTime limit: 0 to 604800 seconds (0 = none)."); return;
 }
 uint64_t offMax=0,onMax=0;
 bool random=!manual&&IsDlgButtonChecked(win,RANDOMTIME)==BST_CHECKED;
 if(random&&(!number(OFFMAX,a,86400000,offMax)||!number(ONMAX,b,86400000,onMax))){error(L"Each maximum must be at least its minimum, up to 86400000 ms.");return;}
 cycle::Settings settings{(uint32_t)a,(uint32_t)b,unlimited?0:c,d*1000,(uint32_t)offMax,(uint32_t)onMax};
 Adapter adapter{};if(i>=0&&i<(int)adapters.size())adapter=adapters[i];saveSettings();
 manualRun=manual;stopRequested=false;
 ResetEvent(stopEvent); ResetEvent(doneEvent); cycles=0; switches=0; phase=0; began=GetTickCount64(); lastError.clear(); running=true; lockControls(true);
 if(manual||mode>=2) EnableWindow(GetDlgItem(win,START),TRUE);
 buttonLabel();
 try { worker=std::thread([settings,adapter,mode,manual] {
  const bool timerSet=timeBeginPeriod(1)==TIMERR_NOERROR;DWORD e=0,restore=0;
  auto execute=[&](auto& backend,bool manualMode){
   DWORD x=0;try{x=backend.init();if(!x){auto r=manualMode?cycle::manual(backend):cycle::run(settings,backend);x=r.error;}}catch(...){x=ERROR_UNHANDLED_EXCEPTION;}
   phase=3;DWORD r=backend.restore();if(r)restore=r;return x;
  };
  try {if(mode>=2){AppBackend backend(mode>=4);e=execute(backend,manual);}else{Backend backend(adapter.luid,mode);e=execute(backend,manual);if(!e&&backend.guardFailed)e=ERROR_PROCESS_ABORTED;}}
  catch(...) {e=ERROR_UNHANDLED_EXCEPTION;}
  if(e==ERROR_CANCELLED)e=0;
  recoveryFailed=restore!=0;
  if(e==ERROR_FILE_NOT_FOUND && mode>=2) lastError=mode>=4?L"No supported browser found. Open Meet in Chrome, Edge, Firefox, Brave, Opera or Vivaldi, then retry.":L"Zoom was not found. Start/install the desktop Zoom client, then try again.";
  else if(e) lastError=L"Switching stopped: "+sysError(e);
  if(restore) lastError+=L"\nRestoration failed: "+sysError(restore)+L"\nClose ihatemeetings and restore networking manually if needed.";
  if(timerSet)timeEndPeriod(1);
  SetEvent(doneEvent);PostMessageW(win,WM_APP+1,0,0);
 }); } catch(...) {SetEvent(doneEvent);running=false;lockControls(false);behaviorControls();error(L"Could not start the worker thread.");}
}


static void testMode() {
 if(running||closing||recoveryFailed)return;
 int mode=sel(MODE);int i=sel(ADAPTER);
 if(mode<2&&(i<0||i>=(int)adapters.size())){error(L"Select a network adapter first.");return;}
 Adapter adapter{};if(i>=0&&i<(int)adapters.size())adapter=adapters[i];saveSettings();
 diagnosticRun=true;diagnosticCompleted=false;manualRun=false;stopRequested=false;lastError.clear();cycles=0;switches=0;phase=0;began=GetTickCount64();ResetEvent(stopEvent);ResetEvent(doneEvent);running=true;lockControls(true);text(STATUS,L"Testing selected mode...");
 try{worker=std::thread([adapter,mode]{DWORD e=0,restore=0;
  auto check=[&](auto& backend){
   try {
    e=backend.init();
    if(!e){
     e=backend.change(true);
     if(!e){
      switches=1;phase=1;backend.wait(750);
      if(!backend.cancelled()){
       e=backend.change(false);
       if(!e){switches=2;phase=2;diagnosticCompleted=true;}
      }
     }
    }
   }catch(...){e=ERROR_UNHANDLED_EXCEPTION;}
   phase=3;restore=backend.restore();
  };
  if(mode>=2){AppBackend b(mode>=4);check(b);}else{Backend b(adapter.luid,mode);check(b);}recoveryFailed=restore!=0;if(e==ERROR_CANCELLED)e=0;
  if(e==ERROR_FILE_NOT_FOUND&&mode>=2)lastError=mode>=4?L"Open Meet in a supported browser before testing.":L"Mode test failed: Zoom desktop client was not found.";else if(e)lastError=L"Mode test failed: "+sysError(e);if(restore)lastError+=L"\nRestoration failed: "+sysError(restore);SetEvent(doneEvent);PostMessageW(win,WM_APP+1,0,0);
 });}catch(...){SetEvent(doneEvent);running=false;diagnosticRun=false;lockControls(false);behaviorControls();error(L"Could not start the mode test.");}
}


static void stop() {if(running) {stopRequested=true;EnableWindow(GetDlgItem(win,START),FALSE);SetEvent(stopEvent);text(STATUS,L"Stopping and restoring...");}}
static INT_PTR CALLBACK dialog(HWND h,UINT msg,WPARAM w,LPARAM) {
 switch(msg) {
 case WM_INITDIALOG: {
  win=h;
  HINSTANCE module=GetModuleHandleW(nullptr);
  smallIcon=(HICON)LoadImageW(module,MAKEINTRESOURCEW(IDI_APP),IMAGE_ICON,GetSystemMetrics(SM_CXSMICON),GetSystemMetrics(SM_CYSMICON),0);
  bigIcon=(HICON)LoadImageW(module,MAKEINTRESOURCEW(IDI_APP),IMAGE_ICON,GetSystemMetrics(SM_CXICON),GetSystemMetrics(SM_CYICON),0);
  SendMessageW(h,WM_SETICON,ICON_SMALL,(LPARAM)smallIcon);SendMessageW(h,WM_SETICON,ICON_BIG,(LPARAM)bigIcon);
  SendDlgItemMessageW(h,ADAPTER,CB_SETDROPPEDWIDTH,460,0);
  for(int id:{OFFMS,ONMS,OFFMAX,ONMAX,COUNT,LIMIT}) SendDlgItemMessageW(h,id,EM_SETLIMITTEXT,10,0);
  add(BEHAVIOR,L"Automatic - repeat off / on cycles");add(BEHAVIOR,L"Manual - hotkey toggles OFF / ON");
  for(auto s:{L"Auto",L"Ethernet",L"Wi-Fi"}) add(TYPE,s);
  add(MODE,L"Fast mode - block / allow adapter traffic"); add(MODE,L"Adapter mode - disable / enable adapter"); add(MODE,L"Zoom Lag - Zoom-only packet-loss bursts"); add(MODE,L"Zoom Kick - block Zoom until restored"); add(MODE,L"Meet Lag - media interruption bursts"); add(MODE,L"Meet Disconnect - hold media blocked");
  wchar_t base[MAX_PATH]{};
  if(SUCCEEDED(SHGetFolderPathW(nullptr,CSIDL_LOCAL_APPDATA,nullptr,0,base))) {
   configPath=std::wstring(base)+L"\\ihatemeetings"; CreateDirectoryW(configPath.c_str(),nullptr); configPath+=L"\\settings.ini";
  }
  auto read=[&](int id,int def){return GetPrivateProfileIntW(L"Settings",std::to_wstring(id).c_str(),def,configPath.c_str());};
  SendDlgItemMessageW(h,TYPE,CB_SETCURSEL,std::min(read(TYPE,0),2u),0);
  SendDlgItemMessageW(h,MODE,CB_SETCURSEL,std::min(read(MODE,0),5u),0);
  SendDlgItemMessageW(h,BEHAVIOR,CB_SETCURSEL,std::min(read(BEHAVIOR,0),1u),0);
  for(auto p:std::vector<std::pair<int,int>>{{OFFMS,500},{ONMS,500},{OFFMAX,1000},{ONMAX,1000},{COUNT,10},{LIMIT,0}}) text(p.first,std::to_wstring(read(p.first,p.second)));
  CheckDlgButton(h,FOREVER,read(FOREVER,0)?BST_CHECKED:BST_UNCHECKED);
  CheckDlgButton(h,RANDOMTIME,read(RANDOMTIME,0)?BST_CHECKED:BST_UNCHECKED);
  WORD saved=(WORD)read(HOTKEY,VK_F6); SendDlgItemMessageW(h,HOTKEY,HKM_SETHOTKEY,saved,0);
  if(!bindHotkey(saved,true)) {if(saved!=VK_F6) bindHotkey(VK_F6,true);}
  SendDlgItemMessageW(h,HOTKEY,HKM_SETHOTKEY,hotkey,0);
  emergencyBound=RegisterHotKey(h,2,MOD_CONTROL|MOD_ALT|MOD_NOREPEAT,VK_F12)!=FALSE;
  if(!emergencyBound) error(L"Emergency hotkey Ctrl+Alt+F12 is unavailable. The Stop button and your main hotkey still work.");
  if(!emergencyBound) text(STATS,L"Emergency key unavailable; use Stop.");
  refresh();lockControls(false); behaviorControls();SetTimer(h,1,100,nullptr);return TRUE;
 }
 case WM_COMMAND: {
  int id=LOWORD(w),event=HIWORD(w);
  if(id==START) {if(running) stop();else start();return TRUE;}
  if(id==STOP) {stop();return TRUE;}
  if(id==TESTMODE) {testMode();return TRUE;}
  if(id==REFRESH||(id==TYPE&&event==CBN_SELCHANGE)) {if(!running) refresh();return TRUE;}
  if(id==APPLY) {if(bindHotkey((WORD)SendDlgItemMessageW(h,HOTKEY,HKM_GETHOTKEY,0,0))) {saveSettings();buttonLabel();text(STATUS,L"Hotkey applied");} return TRUE;}
  if(id==FOREVER) {EnableWindow(GetDlgItem(h,COUNT),IsDlgButtonChecked(h,FOREVER)!=BST_CHECKED);return TRUE;}
  if(id==RANDOMTIME){behaviorControls();return TRUE;}
  if((id==OFFMS||id==ONMS||id==OFFMAX||id==ONMAX)&&event==EN_CHANGE) {rate();return TRUE;}
  if((id==MODE||id==BEHAVIOR)&&event==CBN_SELCHANGE) {rate();behaviorControls();return TRUE;}
  if(id==IDCANCEL) {if(running) stop(); else SendMessageW(h,WM_CLOSE,0,0);return TRUE;}
  break;
 }
 case WM_HOTKEY: if(suppressHotkeys) {if(w==2)stop();return TRUE;} if(w==2) stop(); else if((int)w==hotkeyId) {if(running) stop();else start();} return TRUE;
 case WM_TIMER: if(running) {
  int p=phase.load(),m=sel(MODE);
  if(m>=2) text(STATUS,(m>=4?std::wstring(L"Meet media: "):std::wstring(L"Zoom: "))+(stopRequested?L"restoring...":p==1?L"BLOCKED":p==2?L"ALLOWED":p==3?L"restoring...":L"starting..."));
  else text(STATUS,stopRequested?L"Restoring...":p==1?L"OFF - selected adapter":p==2?L"ON - selected adapter":p==3?L"Restoring...":L"Starting...");
  wchar_t s[180]; swprintf(s,180,L"%llu cycles | %llu switches | %.1fs",cycles.load(),switches.load(),(GetTickCount64()-began)/1000.0);text(STATS,m==5?L"Meet media held blocked until restored":m==3?L"Zoom held blocked until restored":manualRun?L"Manual toggle - no cycles or timers":s);
 } return TRUE;
 case WM_APP+1:
  if(worker.joinable()) worker.join();
  running=false;lockControls(false);behaviorControls();
  if(recoveryFailed) EnableWindow(GetDlgItem(h,START),FALSE);
  if(diagnosticRun) {
   text(STATUS,!lastError.empty()?L"Test failed":diagnosticCompleted?L"API/filter checks passed - restored":L"Test cancelled - restored");
   text(STATS,lastError.empty()?L"This test does not verify a live call or packet flow.":L"See error details; adapter was restoration-attempted.");
  } else {
   text(STATUS,lastError.empty()?L"Stopped - restored":L"Stopped with an error");
   if(manualRun) text(STATS,lastError.empty()?L"ON - restored. Hotkey switches OFF.":L"Check the error details before restarting.");
  }
  if(!lastError.empty()) error(lastError);
  diagnosticRun=false;
  if(closing) EndDialog(h,0);
  return TRUE;
 case WM_CLOSE:
  saveSettings();if(running) {closing=true;stop();}else EndDialog(h,0);return TRUE;
 case WM_POWERBROADCAST: if(w==PBT_APMSUSPEND) {stop();}return TRUE;
 case WM_QUERYENDSESSION:
  SetEvent(stopEvent);
  // Allow cleanup before shutdown; veto this request if the OS call is still stuck.
  SetWindowLongPtrW(h,DWLP_MSGRESULT,!running || WaitForSingleObject(doneEvent,5000)==WAIT_OBJECT_0);
  return TRUE;
 case WM_ENDSESSION: if(w) SetEvent(stopEvent);return TRUE;
 case WM_DESTROY: UnregisterHotKey(h,1);UnregisterHotKey(h,2);UnregisterHotKey(h,3);KillTimer(h,1);if(smallIcon)DestroyIcon(smallIcon);if(bigIcon)DestroyIcon(bigIcon);return TRUE;
 }
 return FALSE;
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR,int) {
 int argc; LPWSTR* argv=CommandLineToArgvW(GetCommandLineW(),&argc);
 if(argv&&argc==6&&wcscmp(argv[1],L"--guard")==0) {
  HANDLE handles[]{(HANDLE)(uintptr_t)_wcstoui64(argv[3],nullptr,10),(HANDLE)(uintptr_t)_wcstoui64(argv[2],nullptr,10)};
  GUID adapterGuid{};if(FAILED(CLSIDFromString(argv[4],&adapterGuid))){LocalFree(argv);return 1;}
  HANDLE ready=(HANDLE)(uintptr_t)_wcstoui64(argv[5],nullptr,10);LocalFree(argv);
  DWORD flags;
  if(!GetHandleInformation(handles[0],&flags)||!GetHandleInformation(handles[1],&flags)||!GetHandleInformation(ready,&flags)) return 1;
  if(!SetEvent(ready)) return 1;
  CloseHandle(ready);
  if(WaitForMultipleObjects(2,handles,FALSE,INFINITE)==WAIT_OBJECT_0+1) {
   DWORD e=0;for(int i=0;i<5;++i){e=setAdapterGuid(adapterGuid,true);if(!e) break;Sleep(300);}
   if(e) MessageBoxW(nullptr,(L"ihatemeetings recovery could not enable the adapter. Open Network Connections (ncpa.cpl) to enable it.\n"+sysError(e)).c_str(),L"ihatemeetings recovery",MB_OK|MB_ICONERROR);
  }
  CloseHandle(handles[0]);CloseHandle(handles[1]);return 0;
 }
 if(argv && argc>1) {LocalFree(argv);return 1;}
 if(argv) LocalFree(argv);
 HANDLE singleton=CreateMutexW(nullptr,FALSE,L"Local\\ihatemeetings-1.0-SingleInstance");
 if(!singleton) {MessageBoxW(nullptr,sysError(GetLastError()).c_str(),L"ihatemeetings startup failed",MB_OK|MB_ICONERROR);return 1;}
 if(GetLastError()==ERROR_ALREADY_EXISTS) {
  HWND existing=FindWindowW(nullptr,L"ihatemeetings 1.4");if(!existing)existing=FindWindowW(nullptr,L"ihatemeetings 1.0");
  if(existing) {ShowWindow(existing,SW_RESTORE);SetForegroundWindow(existing);} else MessageBoxW(nullptr,L"ihatemeetings is already running.",L"ihatemeetings",MB_OK);
  CloseHandle(singleton);return 0;
 }
 stopEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);if(!stopEvent){CloseHandle(singleton);return 1;}
 doneEvent=CreateEventW(nullptr,TRUE,TRUE,nullptr);if(!doneEvent){CloseHandle(stopEvent);CloseHandle(singleton);return 1;}
 INITCOMMONCONTROLSEX controls{sizeof(controls),ICC_WIN95_CLASSES};InitCommonControlsEx(&controls);
 auto result=DialogBoxParamW(instance,MAKEINTRESOURCEW(IDD_MAIN),nullptr,dialog,0);
 SetEvent(stopEvent);if(worker.joinable()) worker.join();CloseHandle(stopEvent);CloseHandle(doneEvent);CloseHandle(singleton);
 if(result==-1) MessageBoxW(nullptr,L"The ihatemeetings window could not be created.",L"ihatemeetings",MB_OK|MB_ICONERROR);
 return result==-1?1:0;
}
