#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xinput.h>
#include <cmath>
#include <cstdio>

#pragma comment(lib, "winmm.lib")

static HMODULE g_realDll = NULL;
static HMODULE g_pluginDll = NULL;

#define X_FUNC(Ret, Name, Params) \
    typedef Ret(WINAPI *Name##_t) Params; \
    static Name##_t g_pfn_##Name = NULL

#define X_IMPL(Ret, Name, Params) \
    extern "C" Ret WINAPI Name Params

X_FUNC(DWORD, XInputGetState, (DWORD dwUserIndex, XINPUT_STATE* pState));
X_FUNC(DWORD, XInputGetStateEx, (DWORD dwUserIndex, XINPUT_STATE* pState));
X_FUNC(DWORD, XInputSetState, (DWORD dwUserIndex, XINPUT_VIBRATION* pVibration));
X_FUNC(DWORD, XInputGetCapabilities, (DWORD dwUserIndex, DWORD dwFlags, XINPUT_CAPABILITIES* pCapabilities));
X_FUNC(void, XInputEnable, (BOOL enable));
X_FUNC(DWORD, XInputGetBatteryInformation, (DWORD dwUserIndex, BYTE devType, XINPUT_BATTERY_INFORMATION* pBatteryInformation));
X_FUNC(DWORD, XInputGetKeystroke, (DWORD dwUserIndex, DWORD dwReserved, PXINPUT_KEYSTROKE pKeystroke));
X_FUNC(DWORD, XInputGetDSoundAudioDeviceGuids, (DWORD dwUserIndex, GUID* pDSoundRenderGuid, GUID* pDSoundCaptureGuid));
X_FUNC(DWORD, XInputGetAudioDeviceIds, (DWORD dwUserIndex, LPWSTR pRenderDeviceId, UINT* pRenderCount, LPWSTR pCaptureDeviceId, UINT* pCaptureCount));

// Optional plugin (LT_Toggle.dll) hook
typedef void(WINAPI *KhazanLT_OnGamepadState_t)(XINPUT_STATE* pState);
static KhazanLT_OnGamepadState_t g_pfn_KhazanLT = NULL;

void ApplyStickToDPad(XINPUT_STATE* pState);

X_IMPL(DWORD, XInputGetState, (DWORD dwUserIndex, XINPUT_STATE* pState)) {
    if (!g_pfn_XInputGetState) return ERROR_DEVICE_NOT_CONNECTED;
    DWORD r = g_pfn_XInputGetState(dwUserIndex, pState);
    if (r == ERROR_SUCCESS && pState) {
        if (g_pfn_KhazanLT) g_pfn_KhazanLT(pState);
        ApplyStickToDPad(pState);
    }
    return r;
}

X_IMPL(DWORD, XInputGetStateEx, (DWORD dwUserIndex, XINPUT_STATE* pState)) {
    if (!g_pfn_XInputGetStateEx) return ERROR_DEVICE_NOT_CONNECTED;
    DWORD r = g_pfn_XInputGetStateEx(dwUserIndex, pState);
    if (r == ERROR_SUCCESS && pState) {
        if (g_pfn_KhazanLT) g_pfn_KhazanLT(pState);
        ApplyStickToDPad(pState);
    }
    return r;
}

X_IMPL(DWORD, XInputSetState, (DWORD dwUserIndex, XINPUT_VIBRATION* pVibration)) {
    if (g_pfn_XInputSetState) return g_pfn_XInputSetState(dwUserIndex, pVibration);
    return ERROR_DEVICE_NOT_CONNECTED;
}

X_IMPL(DWORD, XInputGetCapabilities, (DWORD dwUserIndex, DWORD dwFlags, XINPUT_CAPABILITIES* pCapabilities)) {
    if (g_pfn_XInputGetCapabilities) return g_pfn_XInputGetCapabilities(dwUserIndex, dwFlags, pCapabilities);
    return ERROR_DEVICE_NOT_CONNECTED;
}

X_IMPL(void, XInputEnable, (BOOL enable)) {
    if (g_pfn_XInputEnable) g_pfn_XInputEnable(enable);
}

X_IMPL(DWORD, XInputGetBatteryInformation, (DWORD dwUserIndex, BYTE devType, XINPUT_BATTERY_INFORMATION* pBatteryInformation)) {
    if (g_pfn_XInputGetBatteryInformation) return g_pfn_XInputGetBatteryInformation(dwUserIndex, devType, pBatteryInformation);
    return ERROR_DEVICE_NOT_CONNECTED;
}

X_IMPL(DWORD, XInputGetKeystroke, (DWORD dwUserIndex, DWORD dwReserved, PXINPUT_KEYSTROKE pKeystroke)) {
    if (g_pfn_XInputGetKeystroke) return g_pfn_XInputGetKeystroke(dwUserIndex, dwReserved, pKeystroke);
    return ERROR_DEVICE_NOT_CONNECTED;
}

X_IMPL(DWORD, XInputGetDSoundAudioDeviceGuids, (DWORD dwUserIndex, GUID* pDSoundRenderGuid, GUID* pDSoundCaptureGuid)) {
    if (g_pfn_XInputGetDSoundAudioDeviceGuids) return g_pfn_XInputGetDSoundAudioDeviceGuids(dwUserIndex, pDSoundRenderGuid, pDSoundCaptureGuid);
    return ERROR_DEVICE_NOT_CONNECTED;
}

X_IMPL(DWORD, XInputGetAudioDeviceIds, (DWORD dwUserIndex, LPWSTR pRenderDeviceId, UINT* pRenderCount, LPWSTR pCaptureDeviceId, UINT* pCaptureCount)) {
    if (g_pfn_XInputGetAudioDeviceIds) return g_pfn_XInputGetAudioDeviceIds(dwUserIndex, pRenderDeviceId, pRenderCount, pCaptureDeviceId, pCaptureCount);
    return ERROR_DEVICE_NOT_CONNECTED;
}

// ---------------------------------------------------------------------------
// Stick -> D-pad translation (gamepad-level, keeps UI in gamepad mode)
// ---------------------------------------------------------------------------

static wchar_t g_flagPath[MAX_PATH] = L"";

static BOOL IsMenuOpen() {
    if (g_flagPath[0] == L'\0') return FALSE;
    HANDLE h = CreateFileW(g_flagPath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return FALSE;
    char buf[8] = { 0 };
    DWORD read = 0;
    ReadFile(h, buf, sizeof(buf) - 1, &read, NULL);
    CloseHandle(h);
    return buf[0] == '1';
}

// Converts left-stick deflection into D-pad buttons (with hysteresis), so the
// game receives only gamepad input and never switches the UI to keyboard mode.
// The D-pad button is PULSED (press/release cycle) while the stick stays
// deflected, because UE4/UMG menus respond to key-down transitions: holding
// the button continuously only produces a single navigation step. Pulses give
// the menu repeated key-downs -> auto-repeat scroll.
// No-op when the menu flag is off (gameplay untouched).
void ApplyStickToDPad(XINPUT_STATE* pState) {
    if (!pState || !IsMenuOpen()) return;

    const int ENGAGE = 12000;   // push past this to activate
    const int RELEASE = 8000;   // come back below this to release (hysteresis)
    const DWORD PRESS_MS = 110; // how long each d-pad press is held
    const DWORD GAP_MS = 50;    // gap between presses
    static SHORT lastDir = 0;   // 0 none, 1 up, 2 down, 3 left, 4 right
    static BOOL pulseOn = TRUE;
    static DWORD pulseStart = 0;
    static const WORD DPAD_DIRS[5] = {
        0, XINPUT_GAMEPAD_DPAD_UP, XINPUT_GAMEPAD_DPAD_DOWN, XINPUT_GAMEPAD_DPAD_LEFT, XINPUT_GAMEPAD_DPAD_RIGHT
    };

    SHORT lx = pState->Gamepad.sThumbLX;
    SHORT ly = pState->Gamepad.sThumbLY;
    SHORT dir = 0;
    int mag = lx * lx + ly * ly;
    int thresh = (lastDir == 0) ? ENGAGE : RELEASE;
    if (mag >= thresh * thresh) {
        int ax = abs(lx), ay = abs(ly);
        if (ax > ay)      dir = (lx > 0) ? 4 : 3;
        else              dir = (ly > 0) ? 1 : 2;
    }

    if (dir == 0) {
        // Released: clear the button and reset the pulse state machine.
        pState->Gamepad.wButtons &= ~(XINPUT_GAMEPAD_DPAD_UP | XINPUT_GAMEPAD_DPAD_DOWN | XINPUT_GAMEPAD_DPAD_LEFT | XINPUT_GAMEPAD_DPAD_RIGHT);
        lastDir = 0;
        pulseOn = TRUE;
        pulseStart = 0;
    } else {
        if (dir != lastDir) {
            // Direction changed: emit an immediate fresh press of the new dir.
            lastDir = dir;
            pulseOn = TRUE;
            pulseStart = GetTickCount();
        }
        DWORD now = GetTickCount();
        if (pulseOn) {
            if (now - pulseStart >= PRESS_MS) { pulseOn = FALSE; pulseStart = now; }
        } else {
            if (now - pulseStart >= GAP_MS)   { pulseOn = TRUE;  pulseStart = now; }
        }
        pState->Gamepad.wButtons &= ~(XINPUT_GAMEPAD_DPAD_UP | XINPUT_GAMEPAD_DPAD_DOWN | XINPUT_GAMEPAD_DPAD_LEFT | XINPUT_GAMEPAD_DPAD_RIGHT);
        if (pulseOn) pState->Gamepad.wButtons |= DPAD_DIRS[lastDir];
    }

    // Zero the stick so menus that also read analog input don't double-scroll.
    pState->Gamepad.sThumbLX = 0;
    pState->Gamepad.sThumbLY = 0;
}

static void BuildFlagPath() {
    wchar_t exePath[MAX_PATH];
    GetModuleFileNameW(NULL, exePath, MAX_PATH);
    wchar_t* slash = wcsrchr(exePath, L'\\');
    if (slash) *(slash + 1) = L'\0';
    wsprintfW(g_flagPath, L"%s%s", exePath, L"menu_open.flag");
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        wchar_t sysDir[MAX_PATH];
        GetSystemDirectoryW(sysDir, MAX_PATH);
        wchar_t realPath[MAX_PATH];
        wsprintfW(realPath, L"%s\\xinput1_3.dll", sysDir);
        g_realDll = LoadLibraryW(realPath);
        if (g_realDll) {
            g_pfn_XInputGetState = (XInputGetState_t)GetProcAddress(g_realDll, "XInputGetState");
            g_pfn_XInputSetState = (XInputSetState_t)GetProcAddress(g_realDll, "XInputSetState");
            g_pfn_XInputGetCapabilities = (XInputGetCapabilities_t)GetProcAddress(g_realDll, "XInputGetCapabilities");
            g_pfn_XInputEnable = (XInputEnable_t)GetProcAddress(g_realDll, "XInputEnable");
            g_pfn_XInputGetBatteryInformation = (XInputGetBatteryInformation_t)GetProcAddress(g_realDll, "XInputGetBatteryInformation");
            g_pfn_XInputGetKeystroke = (XInputGetKeystroke_t)GetProcAddress(g_realDll, "XInputGetKeystroke");
            g_pfn_XInputGetDSoundAudioDeviceGuids = (XInputGetDSoundAudioDeviceGuids_t)GetProcAddress(g_realDll, "XInputGetDSoundAudioDeviceGuids");
            g_pfn_XInputGetAudioDeviceIds = (XInputGetAudioDeviceIds_t)GetProcAddress(g_realDll, "XInputGetAudioDeviceIds");
            g_pfn_XInputGetStateEx = (XInputGetStateEx_t)GetProcAddress(g_realDll, (LPCSTR)100);
        }
        BuildFlagPath();

        // Load optional LT toggle plugin (same directory as this DLL).
        wchar_t selfPath[MAX_PATH];
        GetModuleFileNameW(hModule, selfPath, MAX_PATH);
        wchar_t* slash = wcsrchr(selfPath, L'\\');
        if (slash) *(slash + 1) = L'\0';
        wchar_t pluginPath[MAX_PATH];
        wsprintfW(pluginPath, L"%sLT_Toggle.dll", selfPath);
        g_pluginDll = LoadLibraryW(pluginPath);
        if (g_pluginDll) {
            g_pfn_KhazanLT = (KhazanLT_OnGamepadState_t)GetProcAddress(g_pluginDll, "KhazanLT_OnGamepadState");
        }
    } else if (reason == DLL_PROCESS_DETACH) {
        if (g_pluginDll) FreeLibrary(g_pluginDll);
        if (g_realDll) FreeLibrary(g_realDll);
    }
    return TRUE;
}
