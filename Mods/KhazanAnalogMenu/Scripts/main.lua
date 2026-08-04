-- ============================================================================
--  KhazanAnalogMenu - PROBE / diagnostic mod v0.5
--  Game: The First Berserker: Khazan (Unreal Engine 4.27)
--  Loader: UE4SS (experimental-latest, commit 662df915)
--
--  v0.5: controller detection rewritten. The old GetPC() cached the FIRST
--  valid controller (the main-menu UI controller) forever, so we kept reading
--  bShowMouseCursor from the wrong controller even during gameplay. Now we
--  re-resolve the controller that actually has a valid player-controlled pawn
--  every second, and log the FULL controller landscape + visible widget count
--  whenever anything changes, so we can find the real gameplay-vs-pause signal.
--
--  Hotkeys (while the game window is focused):
--    F5 : detailed dump of ALL controllers + visible widgets
--    F6 : dump engine + game PlayerController input/key/pause/menu UFunctions
--    F7 : dump currently existing UserWidget instances (menu widgets)
--    F11: cycles auto -> ON -> OFF -> auto (manual override)
-- ============================================================================

print("===== KhazanAnalogMenu PROBE v0.5 loaded =====")

local GameplayStaticsCDO = StaticFindObject("/Script/Engine.Default__GameplayStatics")

-- ---------------------------------------------------------------------------
-- Controller resolution
-- ---------------------------------------------------------------------------

-- Returns the controller that has a valid pawn (the gameplay controller),
-- else the first controller (menus / loading), else nil.
-- NOTE: we do NOT require IsPlayerControlled() -- this game reports false for
-- its player character, and requiring it made us pick the UI controller whose
-- bShowMouseCursor never changes. The gameplay controller's bShowMouseCursor
-- flips false (gameplay) <-> true (pause menu).
local function FindBestPC()
    local ok, result = pcall(function()
        local controllers = FindAllOf("PlayerController")
        if not controllers or #controllers == 0 then
            controllers = FindAllOf("Controller")
            if not controllers then return nil end
        end
        local first = nil
        for _, c in pairs(controllers) do
            if first == nil then first = c end
            local pawn = nil
            local okPawn = pcall(function() pawn = c.Pawn end)
            if okPawn and pawn ~= nil then
                local ok2, valid = pcall(function() return pawn:IsValid() end)
                if ok2 and valid then
                    return c
                end
            end
        end
        return first
    end)
    return ok and result or nil
end

-- Best PC as of the last 1s scan (re-resolved by the state poller, never
-- cached across gameplay transitions).
local BestPC = nil

local function HasValidPawn(pc)
    if not pc then return false end
    local pawn = nil
    local okPawn = pcall(function() pawn = pc.Pawn end)
    if not okPawn or pawn == nil then return false end
    local ok, v = pcall(function() return pawn:IsValid() end)
    return ok and v or false
end

local function IsGamePaused()
    if not GameplayStaticsCDO then return nil end
    if not BestPC then return nil end
    local ok, paused = pcall(function() return GameplayStaticsCDO:IsGamePaused(BestPC) end)
    return ok and paused or nil
end

local function ReadShowMouseCursor(pc)
    if not pc then return "N/A" end
    local ok, v = pcall(function() return pc.bShowMouseCursor end)
    return ok and tostring(v) or "ERR"
end

-- ---------------------------------------------------------------------------
-- Menu flag for the XINPUT1_3.dll proxy
-- The Lua mod is the author of menu_open.flag. Auto mode follows
-- bShowMouseCursor (UE4 sets it when UI input mode is active, e.g. pause
-- menus); F11 cycles auto -> ON -> OFF -> auto as a manual override.
-- bShowMouseCursor is a plain property read (no FName marshalling -> safe).
-- ---------------------------------------------------------------------------

local MENU_FLAG_PATH = "D:\\Games\\The First Berserker - Khazan\\BBQ\\Binaries\\Win64\\menu_open.flag"
-- 0 = auto, 1 = force ON, 2 = force OFF
local ManualState = 0
local FlagLastWrite = nil

-- Debounce state for the auto flag writer (must be declared before use).
local LastMouseCursor = "N/A"
local CursorSameCount = 0
local LastAutoPCKey = ""

local function WriteFlag(open)
    local ok, f = pcall(function() return io.open(MENU_FLAG_PATH, "w") end)
    if ok and f then
        f:write(open and "1" or "0")
        f:close()
    end
end

local function SetManualState(state)
    ManualState = state
    if state == 0 then
        LastMouseCursor = "N/A"
        CursorSameCount = 0
        LastAutoPCKey = ""
        FlagLastWrite = nil
        print("[F11] manual override OFF (auto: bShowMouseCursor)")
    elseif state == 1 then
        FlagLastWrite = true
        WriteFlag(true)
        print("[F11] manual override -> ON")
    else
        FlagLastWrite = false
        WriteFlag(false)
        print("[F11] manual override -> OFF")
    end
end

-- ---------------------------------------------------------------------------
-- Auto flag writer: samples bShowMouseCursor on the 200ms poller, debounced
-- over 3 samples (~600ms) so brief flips don't toggle the flag. Writes only
-- on change.
-- ---------------------------------------------------------------------------

local function ApplyAutoFlag(pc)
    local mc = ReadShowMouseCursor(pc)
    if mc == "N/A" or mc == "ERR" then
        -- No valid PC (e.g. loading screen): don't flip the flag.
        return
    end
    -- Identify the PC by its stable name, NOT by Lua reference: FindAllOf
    -- returns a fresh wrapper object each call, so `pc ~= LastAutoPC` would
    -- ALWAYS be true and reset the debounce on every tick. The object name
    -- (unique suffix) stays constant for the same underlying controller.
    local pcKey = ""
    pcall(function() pcKey = pc:GetFullName() or "" end)
    if pcKey ~= LastAutoPCKey then
        LastAutoPCKey = pcKey
        LastMouseCursor = "N/A"
        CursorSameCount = 0
    end
    if mc ~= LastMouseCursor then
        LastMouseCursor = mc
        CursorSameCount = 1
        print(string.format("[mousemenu] bShowMouseCursor -> %s (pc=%s)", mc, pc and "Y" or "N"))
    else
        CursorSameCount = CursorSameCount + 1
    end
    if CursorSameCount >= 3 then
        local open = (mc == "true")
        if open ~= FlagLastWrite then
            FlagLastWrite = open
            WriteFlag(open)
            print(string.format("[flag] menu_open -> %s (auto)", open and "ON" or "OFF"))
        end
    end
end

local LastState = ""

-- Fast poller: only resolves the best PC and drives the auto flag. Deliberately
-- light (no widget scan) so it can run quickly and keep the menu-vs-gameplay
-- latency low. Debounce is 3 samples at 200ms (~600ms), enough to skip brief
-- flips while still feeling responsive.
LoopAsync(200, function()
    BestPC = FindBestPC()
    if ManualState == 0 and BestPC then
        ApplyAutoFlag(BestPC)
    end
    return false
end)

-- Slow poller: widget scan + status line (diagnostic). FindAllOf("UserWidget")
-- is expensive (1903 widgets), so it must NOT run on the fast path.
LoopAsync(2000, function()
    local pc = BestPC
    local pawnOk = HasValidPawn(pc)
    local paused = IsGamePaused()
    local pausedStr = paused == nil and "<unknown>" or tostring(paused)
    local state = string.format("pc=%s pawn=%s paused=%s mouseCursor=%s",
        pc and "Y" or "N", pawnOk and "Y" or "N", pausedStr, ReadShowMouseCursor(pc))
    if state ~= LastState then
        LastState = state
        print("[status] " .. state)
    end
    return false
end)

-- ---------------------------------------------------------------------------
-- Hooks: pause signals
-- ---------------------------------------------------------------------------

pcall(function()
    RegisterHook("/Script/Engine.GameplayStatics:SetGamePaused", function(ctx, worldCtx, paused)
        local p = paused:get()
        print(string.format("[hook] GameplayStatics.SetGamePaused -> %s", tostring(p)))
    end)
    print("[hook] registered GameplayStatics.SetGamePaused")
end)

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:SetPause", function(ctx, paused)
        local p = paused:get()
        print(string.format("[hook] PlayerController.SetPause -> %s", tostring(p)))
    end)
    print("[hook] registered PlayerController.SetPause")
end)

-- ---------------------------------------------------------------------------
-- Hooks: UMG widget lifecycle (find menu widget classes)
-- ---------------------------------------------------------------------------

local menuKeywords = { "menu", "screen", "popup", "pop up", "pause", "title", "inventory", "skill", "gear", "item", "option", "setting", "map", "dialogue", "dialog", "ui", "hud" }

local function LooksLikeMenuWidget(fullName)
    local lower = string.lower(fullName)
    for _, kw in ipairs(menuKeywords) do
        if string.find(lower, kw, 1, true) then return true end
    end
    return false
end

pcall(function()
    RegisterHook("/Script/UMG.UserWidget:Construct", function(ctx)
        local w = ctx:get()
        if w and w:IsValid() then
            local fullName = w:GetFullName()
            if LooksLikeMenuWidget(fullName) then
                print(string.format("[widget+] %s", fullName))
            end
        end
    end)
    print("[hook] registered UMG.UserWidget:Construct")
end)

pcall(function()
    RegisterHook("/Script/UMG.UserWidget:Destruct", function(ctx)
        local w = ctx:get()
        if w and w:IsValid() then
            local fullName = w:GetFullName()
            if LooksLikeMenuWidget(fullName) then
                print(string.format("[widget-] %s", fullName))
            end
        end
    end)
    print("[hook] registered UMG.UserWidget:Destruct")
end)

-- ---------------------------------------------------------------------------
-- Hotkeys
-- ---------------------------------------------------------------------------

local function GetPlayerInput(pc)
    if not pc then return nil end
    local ok, pi = pcall(function() return pc.PlayerInput end)
    if ok and pi then return pi end
    return nil
end

local function ReadStickTest()
    local pc = FindBestPC()
    if not pc then return "readStick: no-pc" end
    if not GetPlayerInput(pc) then return "readStick: no PlayerInput (outside gameplay?)" end
    -- GetInputAnalogKeyState (float return, no out-params -- the safe primitive)
    local ok2, lx = pcall(function() return pc:GetInputAnalogKeyState(FName("Gamepad_LeftX")) end)
    local ok3, ly = pcall(function() return pc:GetInputAnalogKeyState(FName("Gamepad_LeftY")) end)
    local lxs = ok2 and string.format("%.3f", tonumber(lx) or -1) or "ERR"
    local lys = ok3 and string.format("%.3f", tonumber(ly) or -1) or "ERR"
    return "readStick: analogKey(LeftX=" .. lxs .. " LeftY=" .. lys .. ")"
end

RegisterKeyBind(Key.F5, function()
    print("[F5] ALL PlayerControllers/Controllers:")
    local ok, controllers = pcall(function() return FindAllOf("PlayerController") end)
    if not ok or not controllers or #controllers == 0 then
        ok, controllers = pcall(function() return FindAllOf("Controller") end)
    end
    if controllers then
        for i, c in ipairs(controllers) do
            local okName, cname = pcall(function() return c:GetFullName() end)
            local pawn = nil
            local okPawn, pv = pcall(function() pawn = c.Pawn return pawn ~= nil end)
            local pawnName = "none"
            local pawnCtrl = "?"
            if okPawn and pv and pawn then
                local okPN, pn = pcall(function() return pawn:GetFullName() end)
                pawnName = okPN and pn or "<err>"
                local okIC, ic = pcall(function() return pawn:IsPlayerControlled() end)
                pawnCtrl = okIC and tostring(ic) or "ERR"
            end
            local mc = ReadShowMouseCursor(c)
            print(string.format("   [%d] %s pawn=%s (%s) mouseCursor=%s",
                i, okName and cname or "<err>", pawnName, pawnCtrl, mc))
        end
    end
    local best = FindBestPC()
    print("[F5] bestPC=" .. (best and "Y" or "N") .. " pawn=" .. (HasValidPawn(best) and "Y" or "N"))
end)

RegisterKeyBind(Key.F11, function()
    SetManualState((ManualState + 1) % 3)
end)

-- F9: isolated test of the function suspected of crashing (GetInputAnalogStickState).
-- Run it ONLY inside gameplay (with a loaded save). If it crashes the game, we know
-- that primitive is unusable and stickState is abandoned in favor of analogKey.
RegisterKeyBind(Key.F9, function()
    local pc = FindBestPC()
    if not pc then print("[F9] no-pc") return end
    if not GetPlayerInput(pc) then print("[F9] no PlayerInput (outside gameplay?)") return end
    print("[F9] calling GetInputAnalogStickState(0)...")
    local ok, sx, sy = pcall(function() return pc:GetInputAnalogStickState(0) end)
    if ok then
        print(string.format("[F9] stickState(X=%s Y=%s)", tostring(sx), tostring(sy)))
    else
        print("[F9] stickState ERR: " .. tostring(sx))
    end
end)

RegisterKeyBind(Key.F6, function()
    print("[F6] Engine APlayerController input/key/pause UFunctions:")
    local enginePC = StaticFindObject("/Script/Engine.PlayerController")
    if enginePC then
        enginePC:ForEachFunction(function(f)
            local n = f:GetFName():ToString()
            local lower = string.lower(n)
            if string.find(lower, "input") or string.find(lower, "key") or string.find(lower, "pause") then
                print("   engine::" .. n)
            end
        end)
    end
    local pc = FindBestPC()
    if pc then
        print("[F6] Game PlayerController subclass UFunctions (input/key/pause/menu):")
        pc:GetClass():ForEachFunction(function(f)
            local n = f:GetFName():ToString()
            local lower = string.lower(n)
            if string.find(lower, "input") or string.find(lower, "key") or string.find(lower, "pause") or string.find(lower, "menu") then
                print("   game::" .. n)
            end
        end)
    end
end)

RegisterKeyBind(Key.F7, function()
    local widgets = FindAllOf("UserWidget") or {}
    local visCount = 0
    local menuCount = 0
    print(string.format("[F7] UserWidget instances: %d", #widgets))
    for _, w in ipairs(widgets) do
        local okVis, vis = pcall(function() return w:IsVisible() end)
        local okName, name = pcall(function() return w:GetFullName() end)
        if okName and name and LooksLikeMenuWidget(name) then
            menuCount = menuCount + 1
        end
        if okVis and vis and visCount < 40 then
            print(string.format("   VISIBLE: %s", okName and name or "<no-name>"))
            visCount = visCount + 1
        end
    end
    print(string.format("[F7] visible widgets: %d, menu-like total: %d", visCount, menuCount))
end)

RegisterKeyBind(Key.F8, function()
    local pc = FindBestPC()
    if not pc then print("[F8] no pc") return end
    local ok, res = pcall(function()
        return pc:InputKey(FName("Gamepad_DPad_Up"), 1, 1.0, true)
    end)
    if ok then
        print(string.format("[F8] pc:InputKey returned: %s", tostring(res)))
    else
        print(string.format("[F8] pc:InputKey FAILED: %s", tostring(res):sub(1, 120)))
    end
end)

-- ---------------------------------------------------------------------------
-- Startup banner / instructions
-- ---------------------------------------------------------------------------

print("================================================================")
print(" KhazanAnalogMenu v0.5 + XInput proxy")
print(" Steps:")
print("  1) Start the game with the XINPUT1_3.dll proxy in the Win64 folder.")
print("  2) Enter a real PAUSE MENU during gameplay (auto flag = bShowMouseCursor).")
print("  3) F11 cycles auto -> ON -> OFF -> auto (manual override).")
print("  4) Use the LEFT STICK to navigate; F5 (dump controllers), F7 (widgets).")
print("================================================================")
