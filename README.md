# Khazan Analog Menu (The First Berserker: Khazan)

Accessibility mod for **The First Berserker: Khazan** (Unreal Engine 4.27).
Lets you navigate the pause menus with the **left analog stick**, while keeping
the UI in gamepad mode (the game never switches to the keyboard/mouse UI).

## What it does

- The left stick is converted into D-pad **only while a menu is open**. During
  gameplay the input passes through untouched (normal camera).
- The generated D-pad is **pulsed** (press/release in a loop), which makes the
  menu "auto-scroll" while the stick is held — it feels native.
- Menu mode is detected automatically and can also be toggled manually with
  **F11**.
- **Auto-walk**: press **F2** to make the character keep running by itself
  (left stick forced forward); touch the stick to cancel.

## Components

```
khazan-mod/
├── xinput-proxy/                 # XINPUT1_3.dll proxy (C++)
│   ├── dllmain.cpp               # forwards XInput + stick->D-pad conversion
│   ├── exports.def               # exports by ordinal (2/3/100)
│   └── build.bat                 # MSVC x64 build
├── lt-toggle/                    # LT_Toggle.dll (optional plugin)
│   ├── dllmain.cpp
│   └── exports.def
├── Mods/
│   ├── KhazanAnalogMenu/
│   │   └── Scripts/main.lua      # UE4SS mod: detects menus and writes the flag
│   ├── mods.txt                  # enables the UE4SS mod
│   └── shared/
└── backup/ue4ss_v3.0.1_release/  # reference UE4SS copy
```

### How it works (architecture)

1. **`XINPUT1_3.dll` proxy** intercepts `XInputGetState`/`XInputGetStateEx`
   (ordinals 2, 3 and 100). The game imports the DLL by ordinal, so the proxy
   is loaded in its place and forwards to the real system DLL.
2. **`main.lua` (UE4SS)** runs every 200ms and reads the `bShowMouseCursor`
   property of the **gameplay PlayerController** (the one that has a valid pawn
   — not the UI controller, which stays `true` all the time). After 3 identical
   samples (~600ms debounce), it writes the `menu_open.flag` file.
3. **The proxy** reads `menu_open.flag` on every `XInputGetState`. If the flag
   is `'1'`, it converts the left stick into D-pad with hysteresis and a
   **pulse** (110ms press / 50ms gap), zeroing the stick to avoid double
   scrolling.
4. **Auto-walk**: the proxy reads `autorun.flag`. If it is `'1'` and the menu
   is closed, it forces `sThumbLY = 32767` (fully forward). If the player
   deflects the stick (magnitude >= 8000), the proxy **clears the flag** and
   disengages. `main.lua` sets/clears this flag via F2.
5. **`LT_Toggle.dll`** (optional plugin) receives the gamepad state through
   `KhazanLT_OnGamepadState` and toggles the virtual LT state on edge detect —
   an independent feature, it does not affect the menu.

## Deploy (in-game layout)

Copy into the game's `BBQ\Binaries\Win64\`:

```
XINPUT1_3.dll                     # from xinput-proxy (build)
LT_Toggle.dll                     # from lt-toggle (build)
Mods/
├── KhazanAnalogMenu/
│   └── Scripts/main.lua          # from Mods/KhazanAnalogMenu/Scripts/
└── mods.txt                      # KhazanAnalogMenu : 1
```

UE4SS must be installed (uses `experimental-latest`; a reference copy is
available in `backup/ue4ss_v3.0.1_release/`).

> The game must be **closed** during deploy — the DLL is loaded at boot.

## Keys

| Key  | Action |
|------|--------|
| `F11` | Cycles manual override: auto → ON → OFF → auto |
| `F2`  | Toggles auto-walk (writes `autorun.flag` for the proxy) |
| `F5`  | Dumps all controllers/pawns (diagnostics) |
| `F6`  | Dumps input/pause/menu UFunctions of the PlayerController |
| `F7`  | Dumps UserWidget instances (menus) |
| `F9`  | Isolated `GetInputAnalogStickState` test (gameplay only) |
| `F12` | Dumps the PlayerInput's input mappings (diagnostics) |

## Relevant technical details

- **`FindBestPC`**: picks the controller that has a **valid pawn** (the
  gameplay one). It does NOT use `IsPlayerControlled()` — the game returns
  `false` for the player's character, and requiring it made the code pick the
  UI controller, whose `bShowMouseCursor` never changes. The gameplay
  controller flips `false` (gameplay) ↔ `true` (pause menu).
- **PC identity comparison**: compares by `GetFullName()` (the object's unique
  name), never by Lua reference — `FindAllOf` returns a fresh wrapper on every
  call, and comparing references reset the debounce on every tick.
- **Input UFunction crashes**: calling input UFunctions via UE4SS Lua crashes
  the game (e.g. `GetInputAnalogStickState`, `ReadStickTest`). Reading
  **properties** (`bShowMouseCursor`, `Pawn`) is safe. That is why detection is
  property-based rather than stick-polling.
- **Discarded signals**: OS cursor (disappears in menus), `IsGamePaused`
  (returns nil — the game does not use UE's pause), hooks on
  `SetGamePaused`/`SetPause` (never fire). `bShowMouseCursor` of the gameplay
  controller was the winning signal.
- **Pulse vs hold**: UE4/UMG menus respond to key-down/key-up transitions;
  holding the D-pad produced a single step. The pulse produces repeated
  key-downs → auto-scroll.
- **Auto-walk cancels on stick touch**: the proxy detects left-stick magnitude
  >= 8000 and clears `autorun.flag` (it does not just stop forcing the stick).
  So the F2 toggle never stays "stuck" — taking back control disengages it
  automatically.
- **Input mappings are not accessible**: `PlayerInput.ActionMappings`/
  `AxisMappings` return `TrivialObject` — the game strips those properties from
  reflection (only `DebugExecBindings`/`InvertedAxis` remain on `UPlayerInput`).
  The game's input is custom/unreflected; that is why the toggle uses a
  keyboard key (F2) instead of a gamepad button.

## Tuning

In `xinput-proxy/dllmain.cpp` (inside `ApplyStickToDPad`):

| Constant  | Value | Effect |
|-----------|-------|--------|
| `ENGAGE`  | 12000 | deflection to engage |
| `RELEASE` | 8000  | deflection to release (hysteresis) |
| `PRESS_MS`| 110   | D-pad press duration |
| `GAP_MS`  | 50    | gap between presses (scroll speed) |

In `main.lua`:

| Constant       | Value               | Effect |
|----------------|---------------------|--------|
| `MENU_FLAG_PATH` | flag path          | must point at the game's Win64 folder |
| debounce       | 3 samples at 200ms  | ~600ms before toggling the flag |

## Build (Windows)

```bat
cd xinput-proxy
build.bat        :: generates XINPUT1_3.dll
cd ..\lt-toggle
build.bat        :: generates LT_Toggle.dll
```

Toolchain: MSVC x64 (vcvars64), `cl /LD /O2`.
