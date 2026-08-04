#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <xinput.h>

// ---------------------------------------------------------------------------
// LT toggle plugin (Steam Input style)
//
// The left trigger becomes a switch:
//   - physical press  -> flips the virtual LT state
//   - virtual state ON  -> the game sees LT held continuously (255 + button bit)
//   - virtual state OFF -> the game sees LT released (0, bit cleared)
// Initial state: OFF on every launch.
//
// Called by the XINPUT1_3.dll proxy from its intercepted XInputGetState,
// after the real state is fetched and before it is returned to the game.
// ---------------------------------------------------------------------------

static BOOL g_ltToggle = FALSE; // starts OFF
static BOOL g_ltPrev = FALSE;

#define XINPUT_GAMEPAD_LEFT_TRIGGER_BIT 0x0004

static BOOL LTPhysicalDown(const XINPUT_STATE* s) {
    if (s->Gamepad.bLeftTrigger > 60) return TRUE;
    return (s->Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_TRIGGER_BIT) != 0;
}

extern "C" __declspec(dllexport) void WINAPI KhazanLT_OnGamepadState(XINPUT_STATE* pState) {
    if (!pState) return;

    // Edge detection on the physical LT (release re-arms the trigger).
    BOOL down = LTPhysicalDown(pState);
    if (down && !g_ltPrev) {
        g_ltToggle = !g_ltToggle;
    }
    g_ltPrev = down;

    // Apply the virtual toggle state.
    if (g_ltToggle) {
        pState->Gamepad.bLeftTrigger = 255;
        pState->Gamepad.wButtons |= XINPUT_GAMEPAD_LEFT_TRIGGER_BIT;
    } else {
        pState->Gamepad.bLeftTrigger = 0;
        pState->Gamepad.wButtons &= ~XINPUT_GAMEPAD_LEFT_TRIGGER_BIT;
    }
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        g_ltToggle = FALSE;
        g_ltPrev = FALSE;
    }
    return TRUE;
}
