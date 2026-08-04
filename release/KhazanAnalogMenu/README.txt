==========================================================
  Khazan Analog Menu
  Navigate menus with the LEFT STICK in
  The First Berserker: Khazan
==========================================================

WHAT IT DOES
----------------------------------------------------------
- Lets you navigate every menu (pause, inventory, skills,
  map, etc.) with the LEFT ANALOG STICK instead of the
  D-pad.
- Keeps the game in GAMEPAD UI mode the whole time (no
  mouse/keyboard UI flicker).
- Auto-scroll: hold the stick to keep moving through menu
  items, just like a native gamepad D-pad.
- Fully automatic: enables itself when a menu is open and
  disables itself when you go back to gameplay (camera
  controls stay untouched).
- Manual override with F11 if you ever need it.

This mod is designed for people who cannot comfortably use
the D-pad (or keyboard) but want to keep playing with the
game's native gamepad UI.

REQUIREMENTS
----------------------------------------------------------
- Windows 10/11 (x64)
- A working XInput gamepad (Xbox 360 / Xbox One / Series,
  or anything XInput-compatible, e.g. many controllers via
  Steam Input set to "Xbox" mode)
- The First Berserker: Khazan (any recent build)
- ANTIVIRUS NOTE: this mod ships DLL files (a proxy
  XINPUT1_3.dll). Some antivirus products flag DLL proxies
  as suspicious. If your AV blocks or quarantines it, add
  an exception. The DLLs only touch XInput (gamepad input)
  and read/write a small text flag file.

INSTALLATION (FRESH - includes UE4SS)
----------------------------------------------------------
1. Locate your game folder, e.g.:
     ...\Steam\steamapps\common\The First Berserker - Khazan\
   and inside it:
     BBQ\Binaries\Win64\
2. Copy the CONTENTS of this archive into the Win64 folder,
   so that you end up with:
     Win64\XINPUT1_3.dll
     Win64\LT_Toggle.dll
     Win64\UE4SS.dll
     Win64\dwmapi.dll
     Win64\UE4SS-settings.ini
     Win64\Mods\mods.txt
     Win64\Mods\KhazanAnalogMenu\Scripts\main.lua
3. Launch the game. You should see the UE4SS console briefly
   at startup (that is normal). Play and open a menu, then
   use the LEFT STICK to navigate.

UPGRADING (if you already have this mod installed)
----------------------------------------------------------
- Close the game and replace XINPUT1_3.dll and the
  Mods\KhazanAnalogMenu\Scripts\main.lua with the new ones.

INSTALLING ALONGSIDE OTHER UE4SS MODS
----------------------------------------------------------
If you already use UE4SS with other mods, do NOT overwrite
your existing Mods\mods.txt. Instead:
1. Copy XINPUT1_3.dll, LT_Toggle.dll into Win64.
2. Copy the Mods\KhazanAnalogMenu\ folder into your existing
   Mods\ folder.
3. Open your existing Mods\mods.txt and add this line:
       KhazanAnalogMenu : 1

UNINSTALL
----------------------------------------------------------
- Delete XINPUT1_3.dll and LT_Toggle.dll from Win64.
- (Optional) delete Mods\KhazanAnalogMenu\ and remove the
  "KhazanAnalogMenu : 1" line from Mods\mods.txt.
- XINPUT1_3.dll is NOT part of the base game (the game loads
  the system XInput DLL when ours is absent), so removing it
  fully restores the original behavior.

CONTROLS
----------------------------------------------------------
  Left stick (in menus)  navigate
  F11                    cycle: auto -> force ON -> force OFF -> auto

F11 is only a manual override. In normal use you never need
it: the mod auto-detects when a menu is open.

HOW IT WORKS (for the curious)
----------------------------------------------------------
- XINPUT1_3.dll is a proxy that forwards XInput to the real
  system DLL, but while a menu is open it translates the
  left-stick deflection into D-pad button presses (with a
  pulse so menus auto-scroll, plus hysteresis to avoid
  jitter).
- A small UE4SS Lua mod watches the game's menu state and
  writes a tiny text file (menu_open.flag) next to the DLL.
  The proxy reads it every poll; when the flag is set, it
  does the stick->D-pad conversion, otherwise the input is
  untouched.
- LT_Toggle.dll is an OPTIONAL plugin (Steam-Input style):
  it turns the left trigger into a toggle switch. If you
  don't want it, just delete the file.

KNOWN ISSUES
----------------------------------------------------------
- Some antivirus software may flag the DLL proxy. Add an
  exception if needed.
- The UE4SS GUI console shows by default only for
  troubleshooting; you can disable it in UE4SS-settings.ini
  ([Debug] GuiConsoleVisible = 0).

SUPPORT / FEEDBACK
----------------------------------------------------------
If something does not work, check the file UE4SS.log in the
Win64 folder - it contains the mod's diagnostic output.

Enjoy!
