#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define NOMINMAX
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <gdiplus.h>
#include <dwmapi.h>
#include <iomanip>
#include <sstream>
#include <cwchar>
#include <cstring>
#include <memory>
#include <vector>
#include "SalaryEngine.hpp"

using namespace Gdiplus;
using namespace paypulse;
namespace {
constexpr UINT TRAY_MESSAGE = WM_APP + 1, SHOW_APP = WM_APP + 2;
enum ControlId { SET_SALARY=101, SET_START, SET_END, SET_BREAK, SET_BREAK_START, SET_BREAK_END,
              SET_BASIS, SET_DAYS, SET_FOUR, SET_LOGIN, SAVE, CANCEL, OPEN_SETTINGS,
              FLOATING, PRIVACY, EXIT_APP, FLOAT_CLOSE };
constexpr int DAY_BASE = 200;
HINSTANCE instance;
HWND mainWindow = nullptr, settingsWindow = nullptr, floatingWindow = nullptr;
HFONT controlFont = nullptr, largeFont = nullptr;
HICON appIcon = nullptr;
Settings settings;
Snapshot earnings;
std::time_t currentTime = 0;
std::wstring configPath;
NOTIFYICONDATAW tray{};
UINT taskbarCreated;
bool smokeMode=false;
int smokeExitCode=0;
double testScale=0;
int settingsScroll=0;
double settingsFontScale=0;
void smokeLog(const char* message) {
    if(!smokeMode)return;
    wchar_t temp[MAX_PATH];GetTempPathW(MAX_PATH,temp);std::wstring path=std::wstring(temp)+L"PayPulse-smoke.log";
    HANDLE file=CreateFileW(path.c_str(),FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE)return;
    DWORD written;WriteFile(file,message,static_cast<DWORD>(strlen(message)),&written,nullptr);WriteFile(file,"\r\n",2,&written,nullptr);CloseHandle(file);
}
Color paper(255,248,248,241), ink(255,31,51,43), muted(255,114,128,119), green(255,39,100,74), lime(255,209,240,122), lineColor(255,225,230,219);

double scale(HWND w) { return testScale>0?testScale:GetDpiForWindow(w)/96.0; }
int px(HWND w, int value) { return static_cast<int>(value * scale(w) + .5); }
std::wstring number(double n, int digits=2) {
    std::wostringstream stream; stream.imbue(std::locale::classic()); stream << std::fixed << std::setprecision(digits) << n; return stream.str();
}
std::wstring amount(double n, int digits=2) { return settings.hidden ? L"••••" : number(n,digits); }
std::wstring clockText(int minutes) {
    wchar_t text[16]; swprintf(text, 16, L"%02d:%02d", minutes/60, minutes%60); return text;
}
std::wstring countdown() {
    if (!earnings.next) return earnings.state == State::dayOff ? L"好好生活" : L"自由时间";
    int t = static_cast<int>(std::max(0.0,std::difftime(earnings.next,currentTime)));
    wchar_t text[24]; swprintf(text,24,L"%02d:%02d:%02d",t/3600,(t/60)%60,t%60); return text;
}
std::unique_ptr<Font> uiFont(float size,bool bold=false) {
    auto style=bold?FontStyleBold:FontStyleRegular;
    auto font=std::make_unique<Font>(L"Microsoft YaHei UI",size,style,UnitPixel);
    if(font->GetLastStatus()!=Ok) font=std::make_unique<Font>(L"Segoe UI",size,style,UnitPixel);
    if(font->GetLastStatus()!=Ok) font=std::make_unique<Font>(FontFamily::GenericSansSerif(),size,style,UnitPixel);
    return font;
}
void text(Graphics& g, const std::wstring& value, float x, float y, float size, Color color, bool bold=false, float width=500) {
    auto font=uiFont(size,bold);
    SolidBrush brush(color); StringFormat format; format.SetFormatFlags(StringFormatFlagsNoWrap); format.SetTrimming(StringTrimmingEllipsisCharacter);
    g.DrawString(value.c_str(),-1,font.get(),RectF(x,y,width,size*1.8f),&format,&brush);
}
void rounded(Graphics& g, float x,float y,float w,float h,float r,Color color) {
    GraphicsPath p;
    p.AddArc(x,y,r*2,r*2,180,90); p.AddArc(x+w-r*2,y,r*2,r*2,270,90);
    p.AddArc(x+w-r*2,y+h-r*2,r*2,r*2,0,90); p.AddArc(x,y+h-r*2,r*2,r*2,90,90); p.CloseFigure();
    SolidBrush brush(color); g.FillPath(&brush,&p);
}
void logo(Graphics& g, float x,float y,float size) {
    rounded(g,x,y,size,size,size*.27f,green);
    PointF pts[]={{x+size*.18f,y+size*.52f},{x+size*.30f,y+size*.52f},{x+size*.39f,y+size*.32f},{x+size*.49f,y+size*.74f},{x+size*.60f,y+size*.22f},{x+size*.69f,y+size*.52f},{x+size*.82f,y+size*.52f}};
    Pen pen(lime,size*.055f); pen.SetLineJoin(LineJoinRound); pen.SetStartCap(LineCapRound); pen.SetEndCap(LineCapRound); g.DrawLines(&pen,pts,7);
}
void drawMain(Graphics& g) {
    g.Clear(paper); logo(g,24,22,34); text(g,L"薪跳",69,20,18,ink,true); text(g,L"PAYPULSE",70,43,9,muted,true);
    rounded(g,24,78,372,220,18,green);
    text(g,L"今日已赚",46,98,13,Color(220,255,255,255));
    text(g,stateTitle(earnings.state),299,100,11,lime,false,80);
    auto hero = L"¥ " + amount(earnings.today,settings.fourDecimals?4:2);
    text(g,hero,43,134,hero.size()>13?34:48,lime,true,330);
    std::wstring message = earnings.state==State::working ? L"+ ¥"+amount(earnings.hourly/3600,4)+L" / 秒，时间正在变成收入" : L"按设定时段自动计薪 · " + stateTitle(earnings.state);
    text(g,message,46,207,10,Color(190,255,255,255),false,330);
    rounded(g,46,251,328,4,2,Color(65,255,255,255));
    if(earnings.progress()>0) rounded(g,46,251,static_cast<float>(328*earnings.progress()),4,2,lime);
    text(g,L"已完成 "+std::to_wstring(static_cast<int>(earnings.progress()*100))+L"%",46,265,10,Color(190,255,255,255));
    text(g,L"今日预估 ¥"+amount(earnings.target),242,265,10,Color(190,255,255,255),false,132);
    text(g,L"折合时薪",24,321,12,muted); text(g,L"¥"+amount(earnings.hourly),24,345,22,ink,true,175);
    text(g,earnings.nextLabel.empty()?stateTitle(earnings.state):earnings.nextLabel,226,321,12,muted);
    text(g,countdown(),226,345,22,ink,true,174);
    Pen divider(lineColor); g.DrawLine(&divider,210,324,210,382); g.DrawLine(&divider,24,407,396,407);
    text(g,L"今日排班",24,427,12,muted);
    text(g,clockText(settings.start)+L" — "+clockText(settings.end)+(settings.end<settings.start?L" 次日":L""),223,427,12,ink,false,175);
    text(g,L"本月预估已赚",24,459,12,muted); text(g,L"¥"+amount(earnings.month),251,459,13,ink,true,147);
    text(g,L"按当前排班回算 · "+(settings.fixedBasis ? L"固定 "+number(settings.fixedDays)+L" 天/月" : L"本月 "+std::to_wstring(earnings.monthWorkdays)+L" 个排班工作日"),24,489,10,muted,false,372);
    text(g,L"仅保存在这台电脑 · 关闭窗口后继续运行",24,581,10,muted,false,350);
}
void drawFloating(Graphics& g) {
    g.Clear(paper); logo(g,15,24,36); text(g,L"今日已赚 · "+stateTitle(earnings.state),65,16,10,muted,false,230);
    auto value=L"¥ "+amount(earnings.today,settings.fourDecimals?4:2);
    text(g,value,62,37,value.size()>14?21:29,ink,true,239);
}
int readInt(const wchar_t* key,int fallback) { return GetPrivateProfileIntW(L"Salary",key,fallback,configPath.c_str()); }
double readDouble(const wchar_t* key,double fallback) {
    wchar_t b[100]; auto initial=number(fallback,6); GetPrivateProfileStringW(L"Salary",key,initial.c_str(),b,100,configPath.c_str());
    wchar_t* end; double value=wcstod(b,&end); return *end==0?value:fallback;
}
void loadSettings() {
    PWSTR path=nullptr;
    if(SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&path))) {
        std::wstring dir=std::wstring(path)+L"\\PayPulse"; CoTaskMemFree(path); CreateDirectoryW(dir.c_str(),nullptr); configPath=dir+L"\\settings.ini";
    } else configPath=L"settings.ini";
    settings.salary=readDouble(L"salary",0); settings.start=readInt(L"start",540); settings.end=readInt(L"end",1080);
    settings.breakEnabled=readInt(L"break",1)!=0; settings.breakStart=readInt(L"breakStart",720); settings.breakEnd=readInt(L"breakEnd",780);
    settings.weekdays=static_cast<unsigned>(readInt(L"weekdays",62)); settings.fixedBasis=readInt(L"fixedBasis",0)!=0; settings.fixedDays=readDouble(L"fixedDays",21.75);
    settings.hidden=readInt(L"hidden",0)!=0; settings.fourDecimals=readInt(L"fourDecimals",0)!=0;
    if(!settings.error().empty()) { settings=Settings(); }
}
bool storeSettings() {
    bool ok=true;
    auto write=[&](const wchar_t* key,std::wstring value) { ok=WritePrivateProfileStringW(L"Salary",key,value.c_str(),configPath.c_str())&&ok; };
    write(L"salary",number(settings.salary,6)); write(L"start",std::to_wstring(settings.start)); write(L"end",std::to_wstring(settings.end));
    write(L"break",settings.breakEnabled?L"1":L"0"); write(L"breakStart",std::to_wstring(settings.breakStart)); write(L"breakEnd",std::to_wstring(settings.breakEnd));
    write(L"weekdays",std::to_wstring(settings.weekdays)); write(L"fixedBasis",settings.fixedBasis?L"1":L"0"); write(L"fixedDays",number(settings.fixedDays,6));
    write(L"hidden",settings.hidden?L"1":L"0"); write(L"fourDecimals",settings.fourDecimals?L"1":L"0"); return ok;
}
bool loginEnabled() {
    HKEY key; if(RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",0,KEY_QUERY_VALUE,&key)!=ERROR_SUCCESS) return false;
    DWORD size=0; auto result=RegQueryValueExW(key,L"PayPulse",nullptr,nullptr,nullptr,&size); RegCloseKey(key); return result==ERROR_SUCCESS&&size>2;
}
bool setLogin(bool enabled) {
    HKEY key; if(RegCreateKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)!=ERROR_SUCCESS) return false;
    LSTATUS result;
    if(enabled) { wchar_t path[32768]; DWORD length=GetModuleFileNameW(nullptr,path,32768); if(!length||length>=32768) {RegCloseKey(key); return false;}
        auto value=L"\""+std::wstring(path)+L"\" --background"; result=RegSetValueExW(key,L"PayPulse",0,REG_SZ,reinterpret_cast<const BYTE*>(value.c_str()),static_cast<DWORD>((value.size()+1)*sizeof(wchar_t)));
    } else { result=RegDeleteValueW(key,L"PayPulse"); if(result==ERROR_FILE_NOT_FOUND) result=ERROR_SUCCESS; }
    RegCloseKey(key); return result==ERROR_SUCCESS;
}
struct Control { HWND window; int x,y,w,h; bool large=false; };
std::vector<Control> settingsControls;
void layoutSettings() {
    if(!settingsWindow) return;
    double s=scale(settingsWindow);
    bool fontsChanged=!controlFont||std::abs(settingsFontScale-s)>.001;
    if(fontsChanged) {
        if(controlFont) DeleteObject(controlFont);
        if(largeFont) DeleteObject(largeFont);
        controlFont=CreateFontW(-static_cast<int>(14*s),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Microsoft YaHei UI");
        largeFont=CreateFontW(-static_cast<int>(28*s),0,0,0,FW_MEDIUM,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
        settingsFontScale=s;
    }
    RECT client;GetClientRect(settingsWindow,&client);int height=static_cast<int>(client.bottom/s),viewport=std::max(1,height-64);
    settingsScroll=std::clamp(settingsScroll,0,std::max(0,604-viewport));
    SCROLLINFO info{sizeof(info),SIF_RANGE|SIF_PAGE|SIF_POS,0,603,static_cast<UINT>(viewport),settingsScroll,0};SetScrollInfo(settingsWindow,SB_VERT,&info,TRUE);
    for(auto& c:settingsControls) {
        int id=GetDlgCtrlID(c.window);bool footer=id==SAVE||id==CANCEL;int y=footer?height-53:c.y-settingsScroll;
        MoveWindow(c.window,px(settingsWindow,c.x),px(settingsWindow,y),px(settingsWindow,c.w),px(settingsWindow,c.h),TRUE);
        ShowWindow(c.window,footer||(y>=0&&y+c.h<=viewport)?SW_SHOWNA:SW_HIDE);
        if(fontsChanged)SendMessageW(c.window,WM_SETFONT,reinterpret_cast<WPARAM>(c.large?largeFont:controlFont),TRUE);
    }
}
HWND control(HWND parent,const wchar_t* cls,const wchar_t* caption,int id,int x,int y,int w,int h,DWORD extra=0,bool large=false) {
    auto result=CreateWindowExW(0,cls,caption,WS_CHILD|WS_VISIBLE|WS_TABSTOP|extra,px(parent,x),px(parent,y),px(parent,w),px(parent,h),parent,reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),instance,nullptr);
    if(parent==settingsWindow) settingsControls.push_back({result,x,y,w,h,large});
    return result;
}
void check(HWND w,int id,bool yes) { SendDlgItemMessageW(w,id,BM_SETCHECK,yes?BST_CHECKED:BST_UNCHECKED,0); }
bool checked(HWND w,int id) { return SendDlgItemMessageW(w,id,BM_GETCHECK,0,0)==BST_CHECKED; }
void setTime(HWND parent,int id,int minute) {
    SYSTEMTIME value; GetLocalTime(&value); value.wHour=static_cast<WORD>(minute/60); value.wMinute=static_cast<WORD>(minute%60); value.wSecond=0;
    SendDlgItemMessageW(parent,id,DTM_SETFORMATW,0,reinterpret_cast<LPARAM>(L"HH:mm")); SendDlgItemMessageW(parent,id,DTM_SETSYSTEMTIME,GDT_VALID,reinterpret_cast<LPARAM>(&value));
}
int getTime(HWND parent,int id) {
    SYSTEMTIME value{}; if(SendDlgItemMessageW(parent,id,DTM_GETSYSTEMTIME,0,reinterpret_cast<LPARAM>(&value))!=GDT_VALID) return -1;
    return value.wHour*60+value.wMinute;
}
double inputDouble(HWND parent,int id) {
    wchar_t value[128]; GetDlgItemTextW(parent,id,value,128); std::wstring cleaned;
    for(wchar_t c:std::wstring(value)) if(c!=L','&&c!=L'，'&&c!=L' ') cleaned+=c;
    wchar_t* end=nullptr; double number=wcstod(cleaned.c_str(),&end); return !cleaned.empty()&&end&&*end==0?number:0;
}
Settings formSettings() {
    Settings s=settings;
    s.salary=inputDouble(settingsWindow,SET_SALARY); s.start=getTime(settingsWindow,SET_START); s.end=getTime(settingsWindow,SET_END);
    s.breakEnabled=checked(settingsWindow,SET_BREAK); s.breakStart=getTime(settingsWindow,SET_BREAK_START); s.breakEnd=getTime(settingsWindow,SET_BREAK_END);
    s.weekdays=0; for(int d=0;d<7;d++) if(checked(settingsWindow,DAY_BASE+d)) s.weekdays|=1u<<d;
    s.fixedBasis=SendDlgItemMessageW(settingsWindow,SET_BASIS,CB_GETCURSEL,0,0)==1;
    s.fixedDays=inputDouble(settingsWindow,SET_DAYS); s.fourDecimals=checked(settingsWindow,SET_FOUR); return s;
}
void updateEnabledControls() {
    EnableWindow(GetDlgItem(settingsWindow,SET_BREAK_START),checked(settingsWindow,SET_BREAK)); EnableWindow(GetDlgItem(settingsWindow,SET_BREAK_END),checked(settingsWindow,SET_BREAK));
    EnableWindow(GetDlgItem(settingsWindow,SET_DAYS),SendDlgItemMessageW(settingsWindow,SET_BASIS,CB_GETCURSEL,0,0)==1);
    RECT rateRect{px(settingsWindow,28),px(settingsWindow,480),px(settingsWindow,506),px(settingsWindow,511)};
    InvalidateRect(settingsWindow,&rateRect,FALSE);
}
void makeSettingsControls() {
    smokeLog("settings controls begin");
    settingsControls.clear();
    control(settingsWindow,L"EDIT",settings.salary>0?number(settings.salary).c_str():L"",SET_SALARY,62,112,444,48,WS_BORDER|ES_AUTOHSCROLL,true);
    control(settingsWindow,DATETIMEPICK_CLASSW,L"",SET_START,28,238,215,30,DTS_TIMEFORMAT|DTS_UPDOWN);
    control(settingsWindow,DATETIMEPICK_CLASSW,L"",SET_END,291,238,215,30,DTS_TIMEFORMAT|DTS_UPDOWN);
    control(settingsWindow,L"BUTTON",L"扣除不计薪休息",SET_BREAK,28,283,230,26,BS_AUTOCHECKBOX);
    control(settingsWindow,DATETIMEPICK_CLASSW,L"",SET_BREAK_START,28,318,215,30,DTS_TIMEFORMAT|DTS_UPDOWN);
    control(settingsWindow,DATETIMEPICK_CLASSW,L"",SET_BREAK_END,291,318,215,30,DTS_TIMEFORMAT|DTS_UPDOWN);
    const wchar_t* days[]={L"日",L"一",L"二",L"三",L"四",L"五",L"六"};
    for(int i=0;i<7;i++) { int d=(i+1)%7; control(settingsWindow,L"BUTTON",days[d],DAY_BASE+d,28+i*69,366,62,32,BS_AUTOCHECKBOX|BS_PUSHLIKE); check(settingsWindow,DAY_BASE+d,(settings.weekdays&(1u<<d))!=0); }
    auto basis=control(settingsWindow,L"COMBOBOX",L"",SET_BASIS,28,442,320,150,CBS_DROPDOWNLIST|WS_VSCROLL);
    SendMessageW(basis,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(L"按本月排班工时")); SendMessageW(basis,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(L"固定月计薪天数")); SendMessageW(basis,CB_SETCURSEL,settings.fixedBasis?1:0,0);
    control(settingsWindow,L"EDIT",number(settings.fixedDays).c_str(),SET_DAYS,382,442,90,29,WS_BORDER|ES_AUTOHSCROLL);
    control(settingsWindow,L"BUTTON",L"今日金额显示 4 位小数",SET_FOUR,28,515,460,26,BS_AUTOCHECKBOX);
    control(settingsWindow,L"BUTTON",L"登录 Windows 时自动启动",SET_LOGIN,28,548,460,26,BS_AUTOCHECKBOX);
    control(settingsWindow,L"BUTTON",L"取消",CANCEL,28,615,225,36,BS_OWNERDRAW);
    control(settingsWindow,L"BUTTON",L"保存并开始计薪",SAVE,277,615,229,36,BS_OWNERDRAW|BS_DEFPUSHBUTTON);
    check(settingsWindow,SET_BREAK,settings.breakEnabled); check(settingsWindow,SET_FOUR,settings.fourDecimals); check(settingsWindow,SET_LOGIN,loginEnabled());
    setTime(settingsWindow,SET_START,settings.start); setTime(settingsWindow,SET_END,settings.end); setTime(settingsWindow,SET_BREAK_START,settings.breakStart); setTime(settingsWindow,SET_BREAK_END,settings.breakEnd);
    layoutSettings(); updateEnabledControls();
    smokeLog("settings controls ready");
}
void paintSettings(Graphics& g) {
    g.Clear(paper);RECT client;GetClientRect(settingsWindow,&client);auto state=g.Save();
    g.SetClip(RectF(0,0,static_cast<REAL>(client.right/scale(settingsWindow)),static_cast<REAL>(client.bottom/scale(settingsWindow)-64)));
    g.TranslateTransform(0,static_cast<REAL>(-settingsScroll));
    logo(g,28,23,36); text(g,L"让收入跟上你的节奏",79,20,22,ink,true,440); text(g,L"设置一次，薪跳会在工作时段自动计薪。",80,51,11,muted,false,425);
    text(g,L"01   你的月薪",28,88,12,green,true); text(g,L"¥",28,121,25,green);
    text(g,L"02   工作与休息",28,190,12,green,true); text(g,L"上班",28,215,11,muted); text(g,L"下班 · 早于上班表示次日",291,215,11,muted,false,220);
    text(g,L"—",261,241,14,muted); text(g,L"—",261,321,14,muted);
    text(g,L"选择每周工作日；暂不自动识别法定节假日与调休。",28,404,10,muted,false,478);
    text(g,L"03   计薪口径",28,424,12,green,true); text(g,L"天/月",480,447,11,muted,false,50);
    auto draft=formSettings();
    auto label=draft.error().empty()?L"折合时薪 ¥ "+number(snapshot(currentTime,draft).hourly)+L" / 小时":L"填写有效月薪、时间和工作日后计算时薪";
    text(g,label,28,483,12,green,true,478);
    text(g,L"仅本机保存 · 修改规则会回算本月预估收入，不是实际工资单。",28,585,10,muted,false,478);
    g.Restore(state);
}
void trayUpdate(bool add=false) {
    std::wstring tip=L"薪跳 · "+stateTitle(earnings.state)+L"\n今日已赚 ¥"+amount(earnings.today,settings.fourDecimals?4:2)+L"\n点击查看详情，右键打开菜单";
    wcsncpy(tray.szTip,tip.c_str(),127); tray.szTip[127]=0;
    tray.uFlags=add?(NIF_ICON|NIF_MESSAGE|NIF_TIP):NIF_TIP;
    Shell_NotifyIconW(add?NIM_ADD:NIM_MODIFY,&tray);
}
void tick() {
    currentTime=std::time(nullptr); earnings=snapshot(currentTime,settings); trayUpdate();
    if(IsWindowVisible(mainWindow)) InvalidateRect(mainWindow,nullptr,FALSE);
    if(floatingWindow&&IsWindowVisible(floatingWindow)) InvalidateRect(floatingWindow,nullptr,FALSE);
}
void showMain() { ShowWindow(mainWindow,SW_SHOWNORMAL); SetForegroundWindow(mainWindow); tick(); }
void showSettings(); void toggleFloating();
void quit() { smokeLog("destroying main window"); DestroyWindow(mainWindow); }
void drawButton(const DRAWITEMSTRUCT& d) {
    wchar_t label[128]; GetWindowTextW(d.hwndItem,label,128);
    Graphics g(d.hDC); auto s=scale(d.hwndItem); g.ScaleTransform(static_cast<REAL>(s),static_cast<REAL>(s)); g.SetSmoothingMode(SmoothingModeAntiAlias);
    float w=static_cast<float>((d.rcItem.right-d.rcItem.left)/s),h=static_cast<float>((d.rcItem.bottom-d.rcItem.top)/s);
    bool primary=d.CtlID==SAVE||d.CtlID==OPEN_SETTINGS;
    rounded(g,0,0,w,h,8,primary?green:Color(255,255,255,255));
    if(d.itemState&ODS_SELECTED) { SolidBrush overlay(Color(30,0,0,0)); g.FillRectangle(&overlay,0.f,0.f,w,h); }
    auto font=uiFont(12); SolidBrush brush(primary?Color(255,255,255,255):ink); StringFormat f; f.SetAlignment(StringAlignmentCenter); f.SetLineAlignment(StringAlignmentCenter);
    g.DrawString(label,-1,font.get(),RectF(0,0,w,h),&f,&brush);
    if(d.itemState&ODS_FOCUS) { Pen focus(Color(180,160,175,160)); focus.SetDashStyle(DashStyleDot); g.DrawRectangle(&focus,3.f,3.f,w-6,h-6); }
}
void trayMenu() {
    HMENU menu=CreatePopupMenu(); AppendMenuW(menu,MF_STRING,1,L"查看今日收入"); AppendMenuW(menu,MF_STRING,2,L"薪资与排班…");
    AppendMenuW(menu,MF_STRING,3,floatingWindow&&IsWindowVisible(floatingWindow)?L"收起悬浮窗":L"桌面悬浮窗"); AppendMenuW(menu,MF_STRING,4,settings.hidden?L"显示金额":L"隐藏金额"); AppendMenuW(menu,MF_SEPARATOR,0,nullptr); AppendMenuW(menu,MF_STRING,5,L"退出薪跳");
    POINT p; GetCursorPos(&p); SetForegroundWindow(mainWindow); auto result=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,p.x,p.y,0,mainWindow,nullptr); DestroyMenu(menu); PostMessageW(mainWindow,WM_NULL,0,0);
    if(result==1) showMain(); else if(result==2) showSettings(); else if(result==3) toggleFloating(); else if(result==4) {settings.hidden=!settings.hidden;storeSettings();tick();} else if(result==5) quit();
}
void paintBuffered(HWND w,void (*draw)(Graphics&)) {
    PAINTSTRUCT ps;HDC destination=BeginPaint(w,&ps);RECT rect;GetClientRect(w,&rect);
    HDC memory=CreateCompatibleDC(destination);HBITMAP image=CreateCompatibleBitmap(destination,rect.right,rect.bottom);HGDIOBJ old=SelectObject(memory,image);
    {
        Graphics g(memory);g.ScaleTransform(static_cast<REAL>(scale(w)),static_cast<REAL>(scale(w)));g.SetSmoothingMode(SmoothingModeAntiAlias);g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);draw(g);
    }
    // GDI preserves BeginPaint's child-window and update-region clipping. GDI+
    // DrawImage into the window DC can overwrite native HWND controls.
    int saved=SaveDC(destination);
    for(HWND child=GetWindow(w,GW_CHILD);child;child=GetWindow(child,GW_HWNDNEXT)) {
        if(!IsWindowVisible(child))continue;
        RECT childRect;GetWindowRect(child,&childRect);MapWindowPoints(HWND_DESKTOP,w,reinterpret_cast<POINT*>(&childRect),2);
        ExcludeClipRect(destination,childRect.left,childRect.top,childRect.right,childRect.bottom);
    }
    BitBlt(destination,0,0,rect.right,rect.bottom,memory,0,0,SRCCOPY);
    RestoreDC(destination,saved);
    SelectObject(memory,old);DeleteObject(image);DeleteDC(memory);EndPaint(w,&ps);
}
bool captureWindow(HWND w,const wchar_t* name) {
    // Exercise real HWND painting, including parent-only updates that previously
    // covered controls. Read the resulting client pixels instead of re-rendering it.
    SetWindowPos(w,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
    RedrawWindow(w,nullptr,nullptr,RDW_INVALIDATE|RDW_ALLCHILDREN|RDW_UPDATENOW);
    for(int i=0;i<3;i++) {RedrawWindow(w,nullptr,nullptr,RDW_INVALIDATE|RDW_NOCHILDREN|RDW_UPDATENOW);GdiFlush();DwmFlush();}
    RECT r;GetClientRect(w,&r);HDC dc=GetDC(nullptr),memory=CreateCompatibleDC(dc);HBITMAP image=CreateCompatibleBitmap(dc,r.right,r.bottom);
    HGDIOBJ old=SelectObject(memory,image);
    POINT origin{0,0};ClientToScreen(w,&origin);
    BitBlt(memory,0,0,r.right,r.bottom,dc,origin.x,origin.y,SRCCOPY|CAPTUREBLT);
    bool persisted=true;
    if(w==mainWindow||w==settingsWindow) {
        HWND button=GetDlgItem(w,w==mainWindow?OPEN_SETTINGS:SAVE);RECT buttonRect;GetWindowRect(button,&buttonRect);MapWindowPoints(HWND_DESKTOP,w,reinterpret_cast<POINT*>(&buttonRect),2);
        COLORREF color=GetPixel(memory,buttonRect.left+px(w,13),buttonRect.top+px(w,10));
        persisted=color!=CLR_INVALID&&GetGValue(color)>GetRValue(color)+20&&GetGValue(color)>GetBValue(color)+10;
        if(w==settingsWindow) {
            COLORREF field=GetPixel(memory,px(w,490),px(w,130));
            persisted=persisted&&field!=CLR_INVALID&&GetRValue(field)>=250&&GetGValue(field)>=250&&GetBValue(field)>=250;
        }
        smokeLog(persisted?"native save/settings button survives parent repaint":"ERROR: native button disappeared after parent repaint");
    }
    UINT count=0,bytes=0;GetImageEncodersSize(&count,&bytes);std::vector<BYTE> info(bytes);auto codecs=reinterpret_cast<ImageCodecInfo*>(info.data());GetImageEncoders(count,bytes,codecs);
    wchar_t temp[MAX_PATH];GetTempPathW(MAX_PATH,temp);std::wstring filename=name;
    if(testScale>1)filename.insert(filename.size()-4,L"-125");
    std::wstring path=std::wstring(temp)+filename;
    {Bitmap bitmap(image,nullptr);for(UINT i=0;i<count;i++)if(wcscmp(codecs[i].MimeType,L"image/png")==0){bitmap.Save(path.c_str(),&codecs[i].Clsid,nullptr);break;}}
    SelectObject(memory,old);DeleteObject(image);DeleteDC(memory);ReleaseDC(nullptr,dc);
    return persisted;
}
LRESULT CALLBACK mainProc(HWND w,UINT msg,WPARAM wp,LPARAM lp) {
    if(msg==taskbarCreated) { trayUpdate(true); return 0; }
    switch(msg) {
        case WM_CREATE:
            mainWindow=w;
            control(w,L"BUTTON",L"隐藏金额",PRIVACY,316,22,80,32,BS_OWNERDRAW);
            control(w,L"BUTTON",L"桌面悬浮窗",FLOATING,24,530,177,36,BS_OWNERDRAW);
            control(w,L"BUTTON",L"薪资与排班",OPEN_SETTINGS,215,530,181,36,BS_OWNERDRAW);
            control(w,L"BUTTON",L"退出",EXIT_APP,355,578,41,25,BS_OWNERDRAW);
            SetTimer(w,1,1000,nullptr); return 0;
        case WM_TIMER:
            if(wp==2) {
                smokeLog("smoke timer fired");
                bool mainOk=captureWindow(mainWindow,L"PayPulse-main.png"),settingsOk=captureWindow(settingsWindow,L"PayPulse-settings.png");captureWindow(floatingWindow,L"PayPulse-floating.png");
                if(!mainOk||!settingsOk)smokeExitCode=4;
                quit();return 0;
            }
            tick(); return 0;
        case SHOW_APP: showMain(); return 0;
        case TRAY_MESSAGE:
            if(lp==WM_LBUTTONUP||lp==WM_LBUTTONDBLCLK) showMain(); else if(lp==WM_RBUTTONUP) trayMenu(); return 0;
        case WM_COMMAND:
            switch(LOWORD(wp)) {
                case OPEN_SETTINGS: showSettings(); break;
                case FLOATING: toggleFloating(); break;
                case PRIVACY: settings.hidden=!settings.hidden; storeSettings(); tick(); break;
                case EXIT_APP: quit(); break;
            } return 0;
        case WM_DRAWITEM: drawButton(*reinterpret_cast<DRAWITEMSTRUCT*>(lp)); return TRUE;
        case WM_ERASEBKGND: return 1;
        case WM_PAINT:paintBuffered(w,drawMain);return 0;
        case WM_CLOSE: ShowWindow(w,SW_HIDE); return 0;
        case WM_DESTROY:
            Shell_NotifyIconW(NIM_DELETE,&tray); if(settingsWindow) DestroyWindow(settingsWindow); if(floatingWindow) DestroyWindow(floatingWindow); PostQuitMessage(0);return 0;
    }
    return DefWindowProcW(w,msg,wp,lp);
}
LRESULT CALLBACK settingsProc(HWND w,UINT msg,WPARAM wp,LPARAM lp) {
    switch(msg) {
        case WM_CREATE: settingsWindow=w;settingsScroll=0;makeSettingsControls();return 0;
        case WM_SIZE:if(!settingsControls.empty())layoutSettings();return 0;
        case WM_MOUSEWHEEL:
            settingsScroll-=GET_WHEEL_DELTA_WPARAM(wp)/WHEEL_DELTA*36;layoutSettings();InvalidateRect(w,nullptr,FALSE);return 0;
        case WM_VSCROLL:{
            SCROLLINFO info{sizeof(info),SIF_ALL,0,0,0,0,0};GetScrollInfo(w,SB_VERT,&info);
            switch(LOWORD(wp)) {
                case SB_LINEUP:settingsScroll-=24;break;case SB_LINEDOWN:settingsScroll+=24;break;
                case SB_PAGEUP:settingsScroll-=static_cast<int>(info.nPage);break;case SB_PAGEDOWN:settingsScroll+=static_cast<int>(info.nPage);break;
                case SB_THUMBTRACK:case SB_THUMBPOSITION:settingsScroll=info.nTrackPos;break;
                case SB_TOP:settingsScroll=0;break;case SB_BOTTOM:settingsScroll=info.nMax;break;
            }
            layoutSettings();InvalidateRect(w,nullptr,FALSE);return 0;
        }
        case WM_COMMAND:
            if(LOWORD(wp)==SAVE||LOWORD(wp)==IDOK) {
                auto updated=formSettings(); auto error=updated.error(); if(!error.empty()) {MessageBoxW(w,error.c_str(),L"请检查设置",MB_OK|MB_ICONINFORMATION);return 0;}
                bool login=checked(w,SET_LOGIN);
                Settings previous=settings; settings=updated;
                if(!storeSettings()) {settings=previous;MessageBoxW(w,L"设置保存失败，请检查本地应用数据文件夹的写入权限。",L"薪跳",MB_OK|MB_ICONERROR);return 0;}
                if(login!=loginEnabled()&&!setLogin(login)) MessageBoxW(w,L"薪资设置已保存，但自动启动设置未成功。可以稍后重试。",L"薪跳",MB_OK|MB_ICONINFORMATION);
                DestroyWindow(w); tick(); showMain(); if(!floatingWindow) toggleFloating(); return 0;
            }
            if(LOWORD(wp)==CANCEL||LOWORD(wp)==IDCANCEL) {DestroyWindow(w);return 0;}
            if(HIWORD(wp)==BN_CLICKED||HIWORD(wp)==CBN_SELCHANGE||HIWORD(wp)==EN_CHANGE) updateEnabledControls();
            return 0;
        case WM_NOTIFY:
            // Native controls also notify while painting. Invalidating the whole
            // parent for those notifications creates an endless paint loop and
            // starves low-priority WM_TIMER messages.
            if(reinterpret_cast<NMHDR*>(lp)->code==DTN_DATETIMECHANGE) {
                RECT rateRect{px(w,28),px(w,480),px(w,506),px(w,511)};
                InvalidateRect(w,&rateRect,FALSE);
            }
            return 0;
        case WM_DRAWITEM: drawButton(*reinterpret_cast<DRAWITEMSTRUCT*>(lp));return TRUE;
        case WM_CTLCOLORBTN: case WM_CTLCOLORSTATIC: {HDC dc=reinterpret_cast<HDC>(wp);SetBkColor(dc,RGB(248,248,241));SetTextColor(dc,RGB(31,51,43));static HBRUSH brush=CreateSolidBrush(RGB(248,248,241));return reinterpret_cast<LRESULT>(brush);}
        case WM_ERASEBKGND:return 1;
        case WM_PAINT:paintBuffered(w,paintSettings);return 0;
        case WM_CLOSE:DestroyWindow(w);return 0;
        case WM_DESTROY:settingsWindow=nullptr;settingsControls.clear();return 0;
    }
    return DefWindowProcW(w,msg,wp,lp);
}
LRESULT CALLBACK floatingProc(HWND w,UINT msg,WPARAM wp,LPARAM lp) {
    switch(msg) {
        case WM_CREATE:control(w,L"BUTTON",L"×",FLOAT_CLOSE,299,5,26,25,BS_OWNERDRAW);return 0;
        case WM_NCHITTEST: {auto hit=DefWindowProcW(w,msg,wp,lp);return hit==HTCLIENT?HTCAPTION:hit;}
        case WM_COMMAND:if(LOWORD(wp)==FLOAT_CLOSE) ShowWindow(w,SW_HIDE);return 0;
        case WM_DRAWITEM:drawButton(*reinterpret_cast<DRAWITEMSTRUCT*>(lp));return TRUE;
        case WM_ERASEBKGND:return 1;
        case WM_PAINT:paintBuffered(w,drawFloating);return 0;
        case WM_CLOSE:ShowWindow(w,SW_HIDE);return 0;
    }
    return DefWindowProcW(w,msg,wp,lp);
}
HWND makeWindow(const wchar_t* cls,const wchar_t* title,int width,int height,DWORD style,DWORD ex=0) {
    UINT dpi=testScale>0?static_cast<UINT>(96*testScale):GetDpiForSystem();RECT rect{0,0,MulDiv(width,static_cast<int>(dpi),96),MulDiv(height,static_cast<int>(dpi),96)};
    AdjustWindowRectExForDpi(&rect,style,FALSE,ex,dpi);
    RECT work;SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0);int w=rect.right-rect.left,h=rect.bottom-rect.top;
    int x=work.left+(work.right-work.left-w)/2,y=std::max(work.top,work.top+(work.bottom-work.top-h)/2);
    return CreateWindowExW(ex,cls,title,style|WS_CLIPCHILDREN,x,y,w,h,nullptr,nullptr,instance,nullptr);
}
void showSettings() {
    if(!settingsWindow) makeWindow(L"PayPulse.Settings",L"薪跳 · 薪资与排班",534,668,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_VSCROLL,WS_EX_CONTROLPARENT);
    ShowWindow(settingsWindow,SW_SHOW);SetForegroundWindow(settingsWindow);SetFocus(GetDlgItem(settingsWindow,SET_SALARY));SendDlgItemMessageW(settingsWindow,SET_SALARY,EM_SETSEL,0,-1);
}
void toggleFloating() {
    if(floatingWindow&&IsWindowVisible(floatingWindow)) {ShowWindow(floatingWindow,SW_HIDE);return;}
    if(!floatingWindow) {
        floatingWindow=makeWindow(L"PayPulse.Floating",L"薪跳 · 今日收入",332,94,WS_POPUP|WS_BORDER,WS_EX_TOOLWINDOW|WS_EX_TOPMOST);
        RECT work;SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0);SetWindowPos(floatingWindow,HWND_TOPMOST,work.right-px(floatingWindow,352),work.top+px(floatingWindow,28),0,0,SWP_NOSIZE|SWP_NOACTIVATE);
    }
    ShowWindow(floatingWindow,SW_SHOWNOACTIVATE);InvalidateRect(floatingWindow,nullptr,FALSE);
}
}
int WINAPI wWinMain(HINSTANCE h,HINSTANCE,PWSTR command,int) {
    instance=h;
    smokeMode=wcsstr(command,L"--smoke-test")!=nullptr;
    if(smokeMode&&wcsstr(command,L"--scale125"))testScale=1.25;
    smokeLog("starting");
    HANDLE mutex=CreateMutexW(nullptr,FALSE,L"Local\\PayPulse.Desktop.Instance");
    if(GetLastError()==ERROR_ALREADY_EXISTS) {HWND existing=FindWindowW(L"PayPulse.Main",nullptr);if(existing)PostMessageW(existing,SHOW_APP,0,0);if(mutex)CloseHandle(mutex);return 0;}
    // System DPI awareness keeps native controls and custom drawing at one consistent scale.
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_SYSTEM_AWARE);
    INITCOMMONCONTROLSEX common{sizeof(common),ICC_DATE_CLASSES|ICC_STANDARD_CLASSES};InitCommonControlsEx(&common);
    GdiplusStartupInput startup;ULONG_PTR token=0;if(GdiplusStartup(&token,&startup,nullptr)!=Ok)return 1;
    smokeLog("GDI ready");
    appIcon=LoadIconW(h,MAKEINTRESOURCEW(1));
    auto reg=[&](const wchar_t* name,WNDPROC proc) {WNDCLASSEXW c{};c.cbSize=sizeof(c);c.hInstance=h;c.lpszClassName=name;c.lpfnWndProc=proc;c.hCursor=LoadCursorW(nullptr,IDC_ARROW);c.hIcon=appIcon;c.hIconSm=appIcon;return RegisterClassExW(&c);};
    reg(L"PayPulse.Main",mainProc);reg(L"PayPulse.Settings",settingsProc);reg(L"PayPulse.Floating",floatingProc);
    loadSettings();currentTime=std::time(nullptr);earnings=snapshot(currentTime,settings);
    const bool smokeTest=wcsstr(command,L"--smoke-test")!=nullptr;
    if(smokeTest) {settings=Settings();settings.salary=18000;earnings=snapshot(currentTime,settings);}
    taskbarCreated=RegisterWindowMessageW(L"TaskbarCreated");
    mainWindow=makeWindow(L"PayPulse.Main",L"薪跳 PayPulse",420,608,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX);
    smokeLog("main window created");
    if(!mainWindow){GdiplusShutdown(token);return 1;}
    tray.cbSize=sizeof(tray);tray.hWnd=mainWindow;tray.uID=1;tray.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP;tray.uCallbackMessage=TRAY_MESSAGE;tray.hIcon=appIcon;trayUpdate(true);
    smokeLog("tray ready");
    if(smokeTest) {
        showMain();smokeLog("main shown");toggleFloating();smokeLog("floating ready");showSettings();smokeLog("settings shown");
        if(!floatingWindow||!settingsWindow||!GetDlgItem(settingsWindow,SET_SALARY)||!GetDlgItem(settingsWindow,SET_START)) {DestroyWindow(mainWindow);GdiplusShutdown(token);return 2;}
        SetTimer(mainWindow,2,1500,nullptr);
        smokeLog("timer armed");
    }
    else if(!settings.error().empty())showSettings();
    else {toggleFloating();if(!wcsstr(command,L"--background"))showMain();}
    smokeLog("message loop");
    MSG msg;while(GetMessageW(&msg,nullptr,0,0)>0){if(settingsWindow&&IsDialogMessageW(settingsWindow,&msg))continue;TranslateMessage(&msg);DispatchMessageW(&msg);}
    smokeLog("message loop exited");
    if(controlFont)DeleteObject(controlFont);
    if(largeFont)DeleteObject(largeFont);
    GdiplusShutdown(token);
    smokeLog("shutdown complete");
    if(mutex)CloseHandle(mutex);
    return smokeExitCode;
}
