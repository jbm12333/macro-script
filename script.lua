--[[
================================================================================
  MACRO RECORDER v8.4 — Auto-click en posición fija (559, 511) integrado
================================================================================
  CAMBIOS v8.4:
    • Nueva sección AUTO-CLICK FIJO (559, 511) integrada en el mismo script.
    • Botón en la UI para activar/desactivar la vigilancia del cursor.
    • Cuando el cursor entra en (559, 511) ±tolerancia y hay un GuiButton
      visible/activo → hace click automático (firesignal → mousemoveabs+click
      → VIM fallback).
    • Cooldown configurable, marcador visual en la posición objetivo.
    • Todo lo de v8.3 intacto.
================================================================================
]]

--============ AUTO-RELANZADOR TRAS TELEPORT ============
do
    local RAW_URL = "https://raw.githubusercontent.com/jbm12333/macro-script/refs/heads/main/script.lua"
    local payload = 'pcall(function() loadstring(game:HttpGet("' .. RAW_URL .. '", true))() end)'
    local ok = false
    if type(queue_on_teleport) == "function" then
        ok = pcall(queue_on_teleport, payload)
    elseif type(syn) == "table" and type(syn.queue_on_teleport) == "function" then
        ok = pcall(syn.queue_on_teleport, payload)
    end
    if ok then
        print("[MacroRec] 📡 queue_on_teleport activo → " .. RAW_URL)
    else
        print("[MacroRec] ⚠ queue_on_teleport no disponible. Usa autoexec para persistencia.")
    end
end

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local unpack = table.unpack or unpack

--============ GUARD CONTRA DUPLICADOS ============
pcall(function()
    local cg = game:GetService("CoreGui")
    local old = cg:FindFirstChild("MacroRec_v8_4"); if old then old:Destroy() end
    local oldOv = cg:FindFirstChild("MacroRec_Overlay"); if oldOv then oldOv:Destroy() end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local old2 = pg:FindFirstChild("MacroRec_v8_4"); if old2 then old2:Destroy() end
        local old2ov = pg:FindFirstChild("MacroRec_Overlay"); if old2ov then old2ov:Destroy() end
    end
end)

--============ ESPERA DE CARGA (para autoexec) ============
if not game:IsLoaded() then
    print("[MacroRec] Esperando a que el juego cargue…")
    game.Loaded:Wait()
end
do
    local deadline = os.clock() + 15
    while os.clock() < deadline do
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then break end
        task.wait(0.1)
    end
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        print("[MacroRec] ✅ Juego y personaje listos")
    else
        print("[MacroRec] ⚠ Personaje no cargó en 15s, continuando igualmente…")
    end
end

local AUTO_LOAD_OUTPUT     = true
local AUTO_LOAD_JSON       = [[]]
local AUTO_EXECUTE_DELAY   = 3.0

local AUTO_CLICK_DELAY   = 2.0
local AUTO_CLICK_TIMEOUT = 15.0
local AUTO_CLICK_POLL    = 0.2

local REC_MOUSE_MIN_PIXELS = 3
local REC_TOUCH_MIN_PIXELS = 4
local REC_CAM_POS_THRESH   = 0.35
local REC_CAM_ROT_THRESH   = 0.03
local REC_CAM_FOV_THRESH   = 0.5
local REC_HRP_POS_THRESH   = 0.10
local REC_HRP_ROT_THRESH   = 0.08

local BASE_GUI_W = 400
local BASE_GUI_H = 690
local BAR_W      = 170
local BAR_H      = 52

--============ AUTO-CLICK FIJO (559, 511) ============
local FIXED_CLICK_X         = 559
local FIXED_CLICK_Y         = 511
local FIXED_CLICK_TOLERANCE = 8
local FIXED_CLICK_COOLDOWN  = 0.4

local DEBUG_KEYS = true
local FORCE_VIM  = false

--============ DETECCIÓN DE PLATAFORMA ============
local TouchEnabled    = UserInputService.TouchEnabled
local MouseEnabled    = UserInputService.MouseEnabled
local KeyboardEnabled = UserInputService.KeyboardEnabled
local isMobileMode    = TouchEnabled and not MouseEnabled
local hasFireTouchInput = (type(firetouchinput) == "function")
local hasVIMSendMouse   = (VirtualInputManager and VirtualInputManager.SendMouseButtonEvent) ~= nil
local hasVIMSendMove    = (VirtualInputManager and VirtualInputManager.SendMouseMoveEvent) ~= nil

local hasFS = (type(writefile) == "function")
          and (type(readfile)  == "function")
          and (type(isfile)    == "function")

local hasSetClipboard = (type(setclipboard) == "function")
                     or (type(toclipboard) == "function")
                     or (type(writeclipboard) == "function")
local hasGetClipboard = (type(getclipboard) == "function")

local function getClipboardSetFn()
    if type(setclipboard) == "function" then return setclipboard, "setclipboard" end
    if type(toclipboard) == "function" then return toclipboard, "toclipboard" end
    if type(writeclipboard) == "function" then return writeclipboard, "writeclipboard" end
    return nil, nil
end

local hasFireSignal = (type(firesignal) == "function")
local hasGetConns   = (type(getconnections) == "function")

local PATH_CANDIDATES = {
    "/sdcard/MacroRecorder/", "/storage/emulated/0/MacroRecorder/",
    "C:/MacroRecorder/", "D:/MacroRecorder/",
    "../../MacroRecorder/", "../MacroRecorder/",
    "workspace/MacroRecorder/", "MacroRecorder/",
}

local activeFolder = nil
if hasFS then
    for _, p in ipairs(PATH_CANDIDATES) do
        if type(makefolder) == "function" then pcall(makefolder, p) end
        local tf = p .. "._mrtest"
        local okW = pcall(writefile, tf, "x")
        local okF = okW and isfile(tf)
        local okR, content = pcall(readfile, tf)
        local ok = okF and okR and content == "x"
        print(string.format("[MacroRec] %s %s", ok and "✅" or "❌", p))
        if ok then
            if type(delfile) == "function" then pcall(delfile, tf) end
            activeFolder = p; break
        end
    end
end
local isSharedFolder = activeFolder and (activeFolder:sub(1,1) == "/"
    or activeFolder:match("^[A-Za-z]:/")) or false

local memRecordings = {}
local MAX_SIZE = 64 * 1024 * 1024

local fn = {
    keypress = keypress, keyrelease = keyrelease,
    mouse1click = mouse1click, mouse1press = mouse1press, mouse1release = mouse1release,
    mouse2click = mouse2click, mouse2press = mouse2press, mouse2release = mouse2release,
    mousemoveabs = mousemoveabs, mousemoverel = mousemoverel,
    mousescroll = mousescroll,
}

--==================================================================
--  TECLADO
--==================================================================
local function doKeyPress(kc)
    if not FORCE_VIM and type(fn.keypress) == "function" then
        local ok = pcall(fn.keypress, kc)
        if ok then
            if DEBUG_KEYS then print("[Key] press (native):", kc.Name) end
            return true
        end
    end
    local ok2 = pcall(function()
        VirtualInputManager:SendKeyEvent(true, kc, false, game)
    end)
    if DEBUG_KEYS then print("[Key] press (VIM):", kc.Name, ok2 and "OK" or "FAIL") end
    return ok2
end
local function doKeyRelease(kc)
    if not FORCE_VIM and type(fn.keyrelease) == "function" then
        local ok = pcall(fn.keyrelease, kc)
        if ok then
            if DEBUG_KEYS then print("[Key] release (native):", kc.Name) end
            return true
        end
    end
    local ok2 = pcall(function()
        VirtualInputManager:SendKeyEvent(false, kc, false, game)
    end)
    if DEBUG_KEYS then print("[Key] release (VIM):", kc.Name, ok2 and "OK" or "FAIL") end
    return ok2
end

--==================================================================
--  GUI
--==================================================================
local function getGuiParent()
    if gethui then local ok, h = pcall(gethui); if ok and h then return h end end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return LocalPlayer:WaitForChild("PlayerGui")
end
local guiParent = getGuiParent()

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MacroRec_v8_4"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999999
pcall(function() ScreenGui.Parent = guiParent end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local state = {
    recording = false, playing = false, looped = false,
    recordStart = 0, events = {}, activeKeys = {},
    currentSession = 0, playStart = nil, playLoopStart = nil,
    autoClick = false, forceMouse = false,
    moveEnabled = true,
    startHrpCFrame = nil,
    startCamCFrame = nil,
    startCamFOV    = nil,
    autoloadName   = nil,
    camKeyframes    = nil,
    hrpKeyframes    = nil,
    hasHrpData      = false,
    controlledHumanoid = nil,
    savedHumanoid      = nil,
    startViewport   = nil,
    playViewport    = nil,
    fixedClickActive = false,
    fixedClickLastAt = 0,
    fixedClickLastBtn = nil,
}

--============ CAMERA LOCK (multi-capa) ============
local camLocked          = false
local originalCamType    = nil
local originalCamSubject = nil
local lastAppliedCamCF   = nil
local lastAppliedCamFOV  = nil
local PLAYBACK_BIND      = "MacroRecPlayback"
local CAM_LOCK_BIND_HI   = "MacroRecCamLockHi"
local CAM_LOCK_BIND_LO   = "MacroRecCamLockLo"
local camLockConns       = {}
local camDriftCount      = 0
local camSetting         = false

local MacroInput = Instance.new("BindableEvent")
MacroInput.Name = "MacroInput"; MacroInput.Parent = ScreenGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, BASE_GUI_W, 0, BASE_GUI_H)
Main.Position = UDim2.new(0, 20, 0, 40)
Main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
Main.BorderSizePixel = 0; Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 8)
local MainStroke = Instance.new("UIStroke", Main)
MainStroke.Color = Color3.fromRGB(70, 70, 100)

local MainScale = Instance.new("UIScale")
MainScale.Scale = 1
MainScale.Parent = Main

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 30)
TitleBar.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
TitleBar.BorderSizePixel = 0; TitleBar.Active = true; TitleBar.Parent = Main
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 8)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 1, 0); Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1; Title.Text = "● Macro Recorder v8.4"
Title.TextColor3 = Color3.fromRGB(210, 210, 255)
Title.Font = Enum.Font.GothamBold; Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left; Title.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22); CloseBtn.Position = UDim2.new(1, -28, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60); CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.new(1, 1, 1); CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13; CloseBtn.BorderSizePixel = 0; CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 4)

local dragging, dragStart, startPos = false, nil, nil
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
       or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                  startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local Chrono = Instance.new("TextLabel")
Chrono.Size = UDim2.new(1, -20, 0, 34); Chrono.Position = UDim2.new(0, 10, 0, 36)
Chrono.BackgroundColor3 = Color3.fromRGB(12, 12, 18); Chrono.Text = "00:00.000"
Chrono.TextColor3 = Color3.fromRGB(100, 255, 120); Chrono.Font = Enum.Font.Code
Chrono.TextSize = 18; Chrono.Parent = Main
Instance.new("UICorner", Chrono).CornerRadius = UDim.new(0, 4)

local RecDot = Instance.new("Frame")
RecDot.Size = UDim2.new(0, 12, 0, 12); RecDot.Position = UDim2.new(0, 18, 0, 47)
RecDot.BackgroundColor3 = Color3.fromRGB(220, 30, 30); RecDot.Visible = false
RecDot.Parent = Main
Instance.new("UICorner", RecDot).CornerRadius = UDim.new(1, 0)

local WarnBanner = Instance.new("TextLabel")
WarnBanner.Size = UDim2.new(1, -20, 0, 26); WarnBanner.Position = UDim2.new(0, 10, 0, 74)
WarnBanner.BackgroundColor3 = Color3.fromRGB(140, 30, 30)
WarnBanner.TextColor3 = Color3.new(1, 1, 1); WarnBanner.Font = Enum.Font.GothamBold
WarnBanner.TextSize = 10; WarnBanner.TextWrapped = true; WarnBanner.Visible = false
WarnBanner.Parent = Main
Instance.new("UICorner", WarnBanner).CornerRadius = UDim.new(0, 4)

if not hasFS then
    WarnBanner.Text = "⚠ Sin FS: memoria. Usa 📤/📋 entre juegos."
    WarnBanner.Visible = true
elseif not isSharedFolder then
    WarnBanner.BackgroundColor3 = Color3.fromRGB(140, 90, 20)
    WarnBanner.Text = "⚠ Carpeta per-game. Usa 📤/📋 entre juegos."
    WarnBanner.Visible = true
end

local NameBox = Instance.new("TextBox")
NameBox.Size = UDim2.new(1, -20, 0, 30)
NameBox.Position = UDim2.new(0, 10, 0, (hasFS and isSharedFolder) and 78 or 104)
NameBox.BackgroundColor3 = Color3.fromRGB(40, 40, 52); NameBox.Text = ""
NameBox.PlaceholderText = "Nombre (vacío = Rec_HHMMSS)"
NameBox.TextColor3 = Color3.fromRGB(220, 220, 220)
NameBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 160)
NameBox.Font = Enum.Font.Gotham; NameBox.TextSize = 13
NameBox.ClearTextOnFocus = false; NameBox.Parent = Main
Instance.new("UICorner", NameBox).CornerRadius = UDim.new(0, 4)

local function mkBtn(txt, col, x, y, w, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, h or 32); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = col; b.Text = txt; b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.BorderSizePixel = 0
    b.Parent = Main
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end

local btnY = (hasFS and isSharedFolder) and 116 or 142
local BtnRecord = mkBtn("● Grabar",     Color3.fromRGB(180, 50, 50),  10, btnY, 92)
local BtnPlay   = mkBtn("▶ Reproducir", Color3.fromRGB(50, 130, 70),  107, btnY, 100)
local BtnStop   = mkBtn("■ Detener",    Color3.fromRGB(90, 90, 110),  212, btnY, 80)
local BtnLoop   = mkBtn("Loop: OFF",    Color3.fromRGB(60, 60, 80),   297, btnY, 93)

local autoY = btnY + 40
local BtnAuto = mkBtn("Auto: OFF", Color3.fromRGB(60, 60, 80), 10, autoY, 92)
local PathBox = Instance.new("TextBox")
PathBox.Size = UDim2.new(0, 190, 0, 32); PathBox.Position = UDim2.new(0, 107, 0, autoY)
PathBox.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
PathBox.Text = "GameUI.FinalUI.Content.PlayAgain"
PathBox.TextColor3 = Color3.fromRGB(220, 220, 220)
PathBox.Font = Enum.Font.Gotham; PathBox.TextSize = 11
PathBox.TextXAlignment = Enum.TextXAlignment.Left; PathBox.ClearTextOnFocus = false
PathBox.Parent = Main
Instance.new("UICorner", PathBox).CornerRadius = UDim.new(0, 4)
local BtnTestClick = mkBtn("Probar", Color3.fromRGB(80, 100, 140), 303, autoY, 87)

local autoY2 = autoY + 38
local function mkMiniBtn(txt, col, x, w)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 26); b.Position = UDim2.new(0, x, 0, autoY2)
    b.BackgroundColor3 = col; b.Text = txt; b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold; b.TextSize = 10; b.BorderSizePixel = 0
    b.Parent = Main
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end
local BtnInspect      = mkMiniBtn("🔍 Insp",   Color3.fromRGB(80, 80, 110),  10, 55)
local BtnMark         = mkMiniBtn("📍 Mapa",   Color3.fromRGB(80, 120, 120), 70, 65)
local BtnCapture      = mkMiniBtn("🎯 Capt",   Color3.fromRGB(120, 100, 180),140, 55)
local ForceMouseBtn   = mkMiniBtn("🖱 Forz",   Color3.fromRGB(60, 60, 80),   200, 60)
local MovToggleBtn    = mkMiniBtn("🏃 Mov ON", Color3.fromRGB(50, 130, 70),  265, 120)

-- NUEVO: fila de auto-click fijo
local fixedY = autoY2 + 30
local FixedClickBtn = Instance.new("TextButton")
FixedClickBtn.Size = UDim2.new(1, -20, 0, 24)
FixedClickBtn.Position = UDim2.new(0, 10, 0, fixedY)
FixedClickBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
FixedClickBtn.Text = "🎯 Auto-click fijo (" .. FIXED_CLICK_X .. ", " .. FIXED_CLICK_Y .. "): OFF"
FixedClickBtn.TextColor3 = Color3.new(1, 1, 1)
FixedClickBtn.Font = Enum.Font.GothamBold
FixedClickBtn.TextSize = 11
FixedClickBtn.BorderSizePixel = 0
FixedClickBtn.Parent = Main
Instance.new("UICorner", FixedClickBtn).CornerRadius = UDim.new(0, 4)

local ListHeader = Instance.new("Frame")
ListHeader.Size = UDim2.new(1, -20, 0, 22); ListHeader.Position = UDim2.new(0, 10, 0, fixedY + 28)
ListHeader.BackgroundTransparency = 1; ListHeader.Parent = Main

local ListHeaderLbl = Instance.new("TextLabel")
ListHeaderLbl.Size = UDim2.new(1, -250, 1, 0); ListHeaderLbl.Position = UDim2.new(0, 4, 0, 0)
ListHeaderLbl.BackgroundTransparency = 1; ListHeaderLbl.Text = "Grabaciones guardadas"
ListHeaderLbl.TextColor3 = Color3.fromRGB(180, 180, 210)
ListHeaderLbl.Font = Enum.Font.GothamBold; ListHeaderLbl.TextSize = 12
ListHeaderLbl.TextXAlignment = Enum.TextXAlignment.Left; ListHeaderLbl.Parent = ListHeader

local function mkHdrBtn(txt, col, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 40, 1, 0); b.Position = UDim2.new(1, x, 0, 0)
    b.BackgroundColor3 = col; b.Text = txt; b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.BorderSizePixel = 0
    b.Parent = ListHeader
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end
local ImportBtn    = mkHdrBtn("📥", Color3.fromRGB(50, 100, 150), -216)
local OpenFileBtn  = mkHdrBtn("📂", Color3.fromRGB(120, 120, 60), -172)
local PasteBtn     = mkHdrBtn("📋", Color3.fromRGB(120, 100, 180), -128)
local ExportAllBtn = mkHdrBtn("📤", Color3.fromRGB(50, 130, 80),  -84)
local RefreshBtn   = mkHdrBtn("🔄", Color3.fromRGB(60, 60, 80),   -40)

local listY = fixedY + 54
local ListFrame = Instance.new("Frame")
ListFrame.Size = UDim2.new(1, -20, 1, -(listY + 36))
ListFrame.Position = UDim2.new(0, 10, 0, listY)
ListFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 18); ListFrame.Parent = Main
Instance.new("UICorner", ListFrame).CornerRadius = UDim.new(0, 4)

local Scrolling = Instance.new("ScrollingFrame")
Scrolling.Size = UDim2.new(1, 0, 1, 0)
Scrolling.BackgroundTransparency = 1; Scrolling.BorderSizePixel = 0
Scrolling.ScrollBarThickness = 6; Scrolling.CanvasSize = UDim2.new(0, 0, 0, 0)
Scrolling.Parent = ListFrame

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 4); ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = Scrolling
ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scrolling.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 8)
end)

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -120, 0, 20); Status.Position = UDim2.new(0, 12, 1, -26)
Status.BackgroundTransparency = 1; Status.Text = ""
Status.TextColor3 = Color3.fromRGB(180, 180, 210); Status.Font = Enum.Font.Gotham
Status.TextSize = 11; Status.TextXAlignment = Enum.TextXAlignment.Left; Status.Parent = Main

local PlatformBadge = Instance.new("TextLabel")
PlatformBadge.Size = UDim2.new(0, 100, 0, 20); PlatformBadge.Position = UDim2.new(1, -112, 1, -26)
PlatformBadge.BackgroundTransparency = 1; PlatformBadge.Font = Enum.Font.GothamBold
PlatformBadge.TextSize = 10; PlatformBadge.TextXAlignment = Enum.TextXAlignment.Right
PlatformBadge.Parent = Main
if isMobileMode then
    PlatformBadge.Text = "📱 Móvil"
    PlatformBadge.TextColor3 = Color3.fromRGB(100, 220, 150)
elseif TouchEnabled then
    PlatformBadge.Text = "🖥️📱 Mixto"
    PlatformBadge.TextColor3 = Color3.fromRGB(220, 200, 100)
else
    PlatformBadge.Text = "🖥️ PC"
    PlatformBadge.TextColor3 = Color3.fromRGB(150, 160, 240)
end

local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "MacroRec_Overlay"; OverlayGui.ResetOnSpawn = false
OverlayGui.IgnoreGuiInset = true; OverlayGui.DisplayOrder = 1000000
pcall(function() OverlayGui.Parent = guiParent end)
if not OverlayGui.Parent then OverlayGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

-- Marcador del auto-click fijo
local FixedMarker = Instance.new("Frame")
FixedMarker.Size = UDim2.new(0, 16, 0, 16)
FixedMarker.Position = UDim2.new(0, FIXED_CLICK_X - 8, 0, FIXED_CLICK_Y - 8)
FixedMarker.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
FixedMarker.BackgroundTransparency = 0.35
FixedMarker.BorderSizePixel = 0
FixedMarker.ZIndex = 1000000
FixedMarker.Visible = false
FixedMarker.Parent = OverlayGui
Instance.new("UICorner", FixedMarker).CornerRadius = UDim.new(1, 0)
local fixedMarkerStroke = Instance.new("UIStroke", FixedMarker)
fixedMarkerStroke.Color = Color3.fromRGB(255, 200, 50)
fixedMarkerStroke.Thickness = 2

local Cursor = Instance.new("Frame")
Cursor.Size = UDim2.new(0, 14, 0, 14); Cursor.BackgroundColor3 = Color3.fromRGB(0, 255, 150)
Cursor.BackgroundTransparency = 0.35; Cursor.BorderSizePixel = 0; Cursor.Visible = false
Cursor.ZIndex = 1000000; Cursor.Parent = OverlayGui
Instance.new("UICorner", Cursor).CornerRadius = UDim.new(1, 0)
local CursorStroke = Instance.new("UIStroke", Cursor)
CursorStroke.Color = Color3.fromRGB(0, 255, 150); CursorStroke.Thickness = 1

local KeysLabel = Instance.new("TextLabel")
KeysLabel.Size = UDim2.new(0, 260, 0, 24); KeysLabel.Position = UDim2.new(0, 20, 1, -46)
KeysLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0); KeysLabel.BackgroundTransparency = 0.4
KeysLabel.Text = ""; KeysLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
KeysLabel.Font = Enum.Font.Code; KeysLabel.TextSize = 14
KeysLabel.TextXAlignment = Enum.TextXAlignment.Left; KeysLabel.Visible = false
KeysLabel.Parent = OverlayGui

local StopOverlay = Instance.new("TextButton")
StopOverlay.Size = UDim2.new(0, 130, 0, 34); StopOverlay.Position = UDim2.new(1, -150, 0, 20)
StopOverlay.BackgroundColor3 = Color3.fromRGB(190, 50, 50); StopOverlay.Text = "■ STOP (F10)"
StopOverlay.TextColor3 = Color3.new(1, 1, 1); StopOverlay.Font = Enum.Font.GothamBold
StopOverlay.TextSize = 13; StopOverlay.BorderSizePixel = 0; StopOverlay.Visible = false
StopOverlay.Parent = OverlayGui
Instance.new("UICorner", StopOverlay).CornerRadius = UDim.new(0, 6)

local function clickCircle(x, y, color)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(0, 10, 0, 10); c.Position = UDim2.new(0, x - 5, 0, y - 5)
    c.BackgroundColor3 = color or Color3.fromRGB(255, 90, 90); c.BackgroundTransparency = 0.2
    c.BorderSizePixel = 0; c.ZIndex = 1000001; c.Parent = OverlayGui
    Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
    local t1 = TweenService:Create(c, TweenInfo.new(0.4), {
        Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, x - 20, 0, y - 20),
        BackgroundTransparency = 1,
    })
    t1:Play(); t1.Completed:Connect(function() c:Destroy() end)
end
local function setFakeCursor(x, y) Cursor.Position = UDim2.new(0, x - 7, 0, y - 7) end

local function drawCrosshair(x, y, color, lifetime)
    color = color or Color3.fromRGB(255, 50, 50)
    lifetime = lifetime or 1.5
    local h = Instance.new("Frame")
    h.Size = UDim2.new(0, 30, 0, 2); h.Position = UDim2.new(0, x - 15, 0, y - 1)
    h.BackgroundColor3 = color; h.BorderSizePixel = 0; h.ZIndex = 1000002
    h.Parent = OverlayGui
    local v = Instance.new("Frame")
    v.Size = UDim2.new(0, 2, 0, 30); v.Position = UDim2.new(0, x - 1, 0, y - 15)
    v.BackgroundColor3 = color; v.BorderSizePixel = 0; v.ZIndex = 1000002
    v.Parent = OverlayGui
    local o = Instance.new("Frame")
    o.Size = UDim2.new(0, 18, 0, 18); o.Position = UDim2.new(0, x - 9, 0, y - 9)
    o.BackgroundTransparency = 1; o.ZIndex = 1000002
    o.Parent = OverlayGui
    Instance.new("UICorner", o).CornerRadius = UDim.new(1, 0)
    local os_ = Instance.new("UIStroke", o)
    os_.Color = color; os_.Thickness = 2
    task.delay(lifetime, function()
        h:Destroy(); v:Destroy(); o:Destroy()
    end)
end

--==================================================================
--  VIEWPORT + ESCALADO
--==================================================================
local function currentViewport()
    local cam = workspace.CurrentCamera
    if cam then return cam.ViewportSize end
    return Vector2.new(1920, 1080)
end

local function scalePoint(x, y)
    local oldVP = state.playViewport
    if not oldVP then return x, y end
    local newVP = currentViewport()
    if oldVP.X <= 0 or oldVP.Y <= 0 then return x, y end
    return x * (newVP.X / oldVP.X), y * (newVP.Y / oldVP.Y)
end

--==================================================================
--  MINIMIZAR VENTANA AL REPRODUCIR
--==================================================================
local savedWindow = nil

local function minimizeToRight()
    if savedWindow then return end
    savedWindow = {
        size  = Main.Size,
        pos   = Main.Position,
        scale = MainScale.Scale,
    }
    MainScale.Scale = 1
    local vp = currentViewport()
    Main.Size = UDim2.new(0, BAR_W, 0, BAR_H)
    Main.Position = UDim2.new(1, -(BAR_W + 8), 0, math.floor((vp.Y - BAR_H) / 2))

    for _, d in ipairs(Main:GetDescendants()) do
        if (d:IsA("GuiObject") or d:IsA("GuiButton")) and d ~= Main
           and d ~= TitleBar and d ~= Title and d ~= CloseBtn then
            if d.Parent ~= TitleBar then
                if d:GetAttribute("_MRVisSaved") == nil then
                    d:SetAttribute("_MRVisSaved", d.Visible and 1 or 0)
                end
                pcall(function() d.Visible = false end)
            end
        end
    end
    Title.Text = "▶ Reproduciendo"
    CloseBtn.Visible = false
end

local function restoreWindow()
    if not savedWindow then return end
    Main.Size = savedWindow.size
    Main.Position = savedWindow.pos
    MainScale.Scale = savedWindow.scale
    savedWindow = nil

    for _, d in ipairs(Main:GetDescendants()) do
        local saved = d:GetAttribute("_MRVisSaved")
        if saved ~= nil and (d:IsA("GuiObject") or d:IsA("GuiButton")) then
            pcall(function() d.Visible = (saved == 1) end)
            d:SetAttribute("_MRVisSaved", nil)
        end
    end
    Title.Text = "● Macro Recorder v8.4"
    CloseBtn.Visible = true
end

--==================================================================
--  GUI RESPONSIVE
--==================================================================
local function updateGuiScale()
    if savedWindow then return end
    local vp = currentViewport()
    local sx = (vp.X - 20) / BASE_GUI_W
    local sy = (vp.Y - 20) / BASE_GUI_H
    local newScale = math.min(sx, sy, 1)
    newScale = math.max(newScale, 0.4)

    if math.abs(newScale - MainScale.Scale) > 0.02 then
        MainScale.Scale = newScale
    end

    local scaledW = math.floor(BASE_GUI_W * newScale)
    local scaledH = math.floor(BASE_GUI_H * newScale)
    local posX = Main.Position.X.Offset
    local posY = Main.Position.Y.Offset
    if posX + scaledW > vp.X then
        posX = math.max(10, vp.X - scaledW - 10)
    end
    if posY + scaledH > vp.Y then
        posY = math.max(10, vp.Y - scaledH - 10)
    end
    if posX ~= Main.Position.X.Offset or posY ~= Main.Position.Y.Offset then
        Main.Position = UDim2.new(0, posX, 0, posY)
    end
end

--==================================================================
--  MODAL
--==================================================================
local PMBackdrop = Instance.new("Frame")
PMBackdrop.Size = UDim2.new(1, 0, 1, 0); PMBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
PMBackdrop.BackgroundTransparency = 0.5; PMBackdrop.BorderSizePixel = 0
PMBackdrop.Visible = false; PMBackdrop.ZIndex = 49; PMBackdrop.Active = true
PMBackdrop.Parent = ScreenGui

local PasteModal = Instance.new("Frame")
PasteModal.Size = UDim2.new(0, 540, 0, 470)
PasteModal.Position = UDim2.new(0.5, -270, 0.5, -235)
PasteModal.BackgroundColor3 = Color3.fromRGB(28, 28, 36); PasteModal.BorderSizePixel = 0
PasteModal.Visible = false; PasteModal.ZIndex = 50; PasteModal.Parent = ScreenGui
Instance.new("UICorner", PasteModal).CornerRadius = UDim.new(0, 8)
local PMStroke = Instance.new("UIStroke", PasteModal)
PMStroke.Color = Color3.fromRGB(120, 100, 180); PMStroke.Thickness = 2

local PMTitle = Instance.new("TextLabel")
PMTitle.Size = UDim2.new(1, -20, 0, 28); PMTitle.Position = UDim2.new(0, 10, 0, 8)
PMTitle.BackgroundTransparency = 1; PMTitle.Text = "📋 Cargar output (JSON)"
PMTitle.TextColor3 = Color3.fromRGB(210, 210, 255); PMTitle.Font = Enum.Font.GothamBold
PMTitle.TextSize = 14; PMTitle.TextXAlignment = Enum.TextXAlignment.Left
PMTitle.ZIndex = 51; PMTitle.Parent = PasteModal

local PMHelp = Instance.new("TextLabel")
PMHelp.Size = UDim2.new(1, -20, 0, 18); PMHelp.Position = UDim2.new(0, 10, 0, 34)
PMHelp.BackgroundTransparency = 1
PMHelp.Text = "Pega el JSON. Para archivos grandes usa 📂 en la lista."
PMHelp.TextColor3 = Color3.fromRGB(140, 140, 170); PMHelp.Font = Enum.Font.Gotham
PMHelp.TextSize = 11; PMHelp.TextXAlignment = Enum.TextXAlignment.Left
PMHelp.ZIndex = 51; PMHelp.Parent = PasteModal

local PMBox = Instance.new("TextBox")
PMBox.Size = UDim2.new(1, -20, 0, 320); PMBox.Position = UDim2.new(0, 10, 0, 56)
PMBox.BackgroundColor3 = Color3.fromRGB(16, 16, 22); PMBox.Text = ""
PMBox.PlaceholderText = '{"name":"mi_macro","events":[...],"duration":12.3}'
PMBox.TextColor3 = Color3.fromRGB(200, 200, 220)
PMBox.PlaceholderColor3 = Color3.fromRGB(90, 90, 110)
PMBox.Font = Enum.Font.Code; PMBox.TextSize = 11
PMBox.MultiLine = true; PMBox.TextWrapped = true
PMBox.TextXAlignment = Enum.TextXAlignment.Left
PMBox.TextYAlignment = Enum.TextYAlignment.Top
PMBox.ClearTextOnFocus = false
PMBox.ZIndex = 51; PMBox.Parent = PasteModal
Instance.new("UICorner", PMBox).CornerRadius = UDim.new(0, 4)

local PMCount = Instance.new("TextLabel")
PMCount.Size = UDim2.new(1, -20, 0, 16); PMCount.Position = UDim2.new(0, 10, 0, 380)
PMCount.BackgroundTransparency = 1; PMCount.Text = "0 bytes"
PMCount.TextColor3 = Color3.fromRGB(140, 140, 170); PMCount.Font = Enum.Font.Gotham
PMCount.TextSize = 10; PMCount.TextXAlignment = Enum.TextXAlignment.Left
PMCount.ZIndex = 51; PMCount.Parent = PasteModal

PMBox:GetPropertyChangedSignal("Text"):Connect(function()
    PMCount.Text = #PMBox.Text .. " bytes"
end)

local PMFromClip = Instance.new("TextButton")
PMFromClip.Size = UDim2.new(0, 140, 0, 32); PMFromClip.Position = UDim2.new(0, 10, 1, -42)
PMFromClip.BackgroundColor3 = Color3.fromRGB(50, 100, 150); PMFromClip.Text = "📥 Del portapapeles"
PMFromClip.TextColor3 = Color3.new(1, 1, 1); PMFromClip.Font = Enum.Font.GothamBold
PMFromClip.TextSize = 11; PMFromClip.BorderSizePixel = 0
PMFromClip.ZIndex = 51; PMFromClip.Parent = PasteModal
Instance.new("UICorner", PMFromClip).CornerRadius = UDim.new(0, 4)

local PMCancel = Instance.new("TextButton")
PMCancel.Size = UDim2.new(0, 90, 0, 32); PMCancel.Position = UDim2.new(1, -204, 1, -42)
PMCancel.BackgroundColor3 = Color3.fromRGB(90, 90, 110); PMCancel.Text = "Cancelar"
PMCancel.TextColor3 = Color3.new(1, 1, 1); PMCancel.Font = Enum.Font.GothamBold
PMCancel.TextSize = 12; PMCancel.BorderSizePixel = 0
PMCancel.ZIndex = 51; PMCancel.Parent = PasteModal
Instance.new("UICorner", PMCancel).CornerRadius = UDim.new(0, 4)

local PMCargar = Instance.new("TextButton")
PMCargar.Size = UDim2.new(0, 100, 0, 32); PMCargar.Position = UDim2.new(1, -108, 1, -42)
PMCargar.BackgroundColor3 = Color3.fromRGB(50, 150, 80); PMCargar.Text = "Cargar"
PMCargar.TextColor3 = Color3.new(1, 1, 1); PMCargar.Font = Enum.Font.GothamBold
PMCargar.TextSize = 12; PMCargar.BorderSizePixel = 0
PMCargar.ZIndex = 51; PMCargar.Parent = PasteModal
Instance.new("UICorner", PMCargar).CornerRadius = UDim.new(0, 4)

local function openPasteModal()
    PMBox.Text = ""; PMCount.Text = "0 bytes"
    PMBackdrop.Visible = true; PasteModal.Visible = true
end
local function closePasteModal()
    PMBackdrop.Visible = false; PasteModal.Visible = false
end

--==================================================================
--  JSON PARSER
--==================================================================
local function jsonEncode(t) return HttpService:JSONEncode(t) end
local function jsonDecode(s) return HttpService:JSONDecode(s) end

local function cleanRawJson(raw)
    if not raw then return nil end
    raw = tostring(raw)
    raw = raw:gsub("^\239\187\191", "")
    raw = raw:gsub("^\255\254", "")
    raw = raw:gsub("%z", "")
    raw = raw:gsub("\194\160", " ")
    raw = raw:gsub("^\194\187", "")
    return raw
end
local function tryUnescape(raw)
    if raw:sub(1, 1) == '"' and raw:sub(-1) == '"' then
        local inner = raw:sub(2, -2)
        inner = inner:gsub('\\"', '"'):gsub("\\\\", "\\"):gsub("\\n", "\n")
                     :gsub("\\t", "\t"):gsub("\\r", "\r"):gsub("\\/", "/")
        return inner
    end
    return raw
end
local function tryExtractJson(raw)
    local s1 = raw:find("{")
    local s2 = raw:find("%[")
    local startIdx = nil
    if s1 and s2 then startIdx = math.min(s1, s2)
    else startIdx = s1 or s2 end
    if not startIdx then return nil end
    local lastIdx = nil
    for i = #raw, startIdx, -1 do
        local c = raw:sub(i, i)
        if c == "}" or c == "]" then lastIdx = i; break end
    end
    if not lastIdx or lastIdx <= startIdx then return nil end
    return raw:sub(startIdx, lastIdx)
end
local function robustJsonDecode(raw)
    if not raw then return nil, "nil" end
    raw = cleanRawJson(raw)
    if not raw then return nil, "clean nil" end
    raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if raw == "" then return nil, "vacío" end

    local ok, res = pcall(jsonDecode, raw)
    if ok and type(res) == "table" then return res, nil, "directo" end

    local un = tryUnescape(raw)
    if un ~= raw then
        local ok2, res2 = pcall(jsonDecode, un)
        if ok2 and type(res2) == "table" then return res2, nil, "un-escape" end
    end

    local ext = tryExtractJson(un)
    if ext and ext ~= un then
        local ok3, res3 = pcall(jsonDecode, ext)
        if ok3 and type(res3) == "table" then return res3, nil, "extraído" end
        local extU = tryUnescape(ext)
        if extU ~= ext then
            local ok4, res4 = pcall(jsonDecode, extU)
            if ok4 and type(res4) == "table" then return res4, nil, "extraído+unesc" end
        end
    end

    if type(loadstring) == "function" then
        local cand = ext or un or raw
        local ok5, fn2 = pcall(loadstring, "return " .. cand)
        if ok5 and fn2 then
            local ok6, res5 = pcall(fn2)
            if ok6 and type(res5) == "table" then return res5, nil, "lua" end
        end
    end

    local ok7, res7 = pcall(jsonDecode, raw)
    if ok7 and type(res7) == "string" then
        local ok8, res8 = pcall(jsonDecode, res7)
        if ok8 and type(res8) == "table" then return res8, nil, "doble" end
    end

    local preview = raw:sub(1, 80)
    if #raw > 80 then preview = preview .. "…" end
    preview = preview:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return nil, "JSON inválido | " .. #raw .. "B | inicio: [" .. preview .. "]"
end

--==================================================================
--  ARCHIVOS
--==================================================================
local function folderPath(name) return activeFolder and (activeFolder .. name .. ".json") or nil end
local function indexPath() return activeFolder and (activeFolder .. "index.json") or nil end
local function autoloadPath() return activeFolder and (activeFolder .. "autoload.json") or nil end

local function readIndex()
    if not activeFolder then return {} end
    local p = indexPath(); if not p or not isfile(p) then return {} end
    local ok, raw = pcall(readfile, p); if not ok or not raw then return {} end
    local ok2, dec = pcall(jsonDecode, raw)
    if ok2 and type(dec) == "table" then return dec end
    return {}
end
local function writeIndex(names)
    if not activeFolder then return end
    local p = indexPath(); if not p then return end
    local ok, enc = pcall(jsonEncode, names); if ok then pcall(writefile, p, enc) end
end

local function readAutoload()
    if not activeFolder then return nil end
    local p = autoloadPath()
    if not p or not isfile(p) then return nil end
    local ok, raw = pcall(readfile, p); if not ok or not raw then return nil end
    local ok2, dec = pcall(jsonDecode, raw)
    if ok2 and type(dec) == "table" and dec.name then return tostring(dec.name) end
    return nil
end
local function writeAutoload(name)
    if not activeFolder then return end
    local p = autoloadPath(); if not p then return end
    local payload = name and { name = name } or {}
    local ok, enc = pcall(jsonEncode, payload)
    if ok then pcall(writefile, p, enc) end
end

local function saveRecording(name, events, duration, created, extra)
    local payload = { name = name, events = events,
        created = created or os.time(), duration = duration or 0 }
    if extra then
        for k, v in pairs(extra) do payload[k] = v end
    end
    local ok, encoded = pcall(jsonEncode, payload)
    if not ok then return false, "JSONEncode falló" end
    if #encoded > MAX_SIZE then return false, "Excede " .. math.floor(MAX_SIZE/1048576) .. "MB" end
    if activeFolder then
        local p = folderPath(name)
        local okW = pcall(writefile, p, encoded)
        if okW and isfile(p) then
            local okR, back = pcall(readfile, p)
            if okR and back and #back > 10 then
                local names = readIndex()
                local found = false
                for _, n in ipairs(names) do if n == name then found = true break end end
                if not found then table.insert(names, name); writeIndex(names) end
                return true, "disco: " .. activeFolder
            end
        end
    end
    memRecordings[name] = payload
    return false, "memoria"
end
local function loadRecording(name)
    if memRecordings[name] then return memRecordings[name] end
    if not activeFolder then return nil end
    local p = folderPath(name); if not p or not isfile(p) then return nil end
    local ok, raw = pcall(readfile, p); if not ok or not raw then return nil end
    local ok2, dec = pcall(jsonDecode, raw); if not ok2 then return nil end
    return dec
end
local function deleteRecording(name)
    if activeFolder then
        local p = folderPath(name)
        if p and isfile(p) and type(delfile) == "function" then pcall(delfile, p) end
        local names = readIndex()
        for i, n in ipairs(names) do if n == name then table.remove(names, i); break end end
        writeIndex(names)
    end
    memRecordings[name] = nil
end
local function getAllNames()
    local names, seen = {}, {}
    if activeFolder then
        for _, n in ipairs(readIndex()) do
            if not seen[n] then table.insert(names, n); seen[n] = true end
        end
        if type(listfiles) == "function" then
            local okL, files = pcall(listfiles, activeFolder)
            if okL and files then
                for _, f in ipairs(files) do
                    local base = tostring(f):match("([^/\\]+)%.json$")
                    if base and base ~= "index" and base ~= "autoload" and not seen[base] then
                        table.insert(names, base); seen[base] = true
                    end
                end
            end
        end
    end
    for k in pairs(memRecordings) do
        if not seen[k] then table.insert(names, k); seen[k] = true end
    end
    table.sort(names)
    return names
end
local function fmtDuration(s)
    s = tonumber(s) or 0
    return string.format("%02d:%06.3f", math.floor(s / 60), s - math.floor(s / 60) * 60)
end
local function fmtDate(ts)
    if not ts then return "" end
    local ok, d = pcall(os.date, "%Y-%m-%d %H:%M", ts); return ok and d or ""
end

--==================================================================
--  IMPORT
--==================================================================
local function importFromText(raw)
    if not raw or raw:gsub("%s", "") == "" then
        return 0, 0, "Texto vacío", nil, nil
    end
    local dec, err, method = robustJsonDecode(raw)
    if not dec then return 0, 0, err or "JSON inválido", nil, nil end

    local saved, skipped = 0, 0
    local firstName = nil
    local function trySave(rec)
        if type(rec) ~= "table" or not rec.name or not rec.events then
            skipped = skipped + 1; return
        end
        local n = tostring(rec.name):gsub("[^%w_%-]", "_")
        local extra = {}
        if rec.startHrpCFrame then extra.startHrpCFrame = rec.startHrpCFrame end
        if rec.startCamCFrame then extra.startCamCFrame = rec.startCamCFrame end
        if rec.startCamFOV    then extra.startCamFOV    = rec.startCamFOV    end
        if rec.startViewport  then extra.startViewport  = rec.startViewport  end
        local okS = saveRecording(n, rec.events, rec.duration or 0, rec.created, extra)
        if okS then
            saved = saved + 1
            if not firstName then firstName = n end
        else skipped = skipped + 1 end
    end

    if dec.name and dec.events then
        trySave(dec)
    elseif #dec > 0 then
        for _, r in ipairs(dec) do trySave(r) end
    else
        return 0, 0, "JSON sin grabaciones", nil, method
    end
    return saved, skipped, nil, firstName, method
end

--==================================================================
--  HELPERS
--==================================================================
local function cframesDiffer(a, b, posT, rotT)
    if not a or not b then return true end
    if (a.Position - b.Position).Magnitude > posT then return true end
    local ac, bc = {a:GetComponents()}, {b:GetComponents()}
    for i = 4, 12 do if math.abs(ac[i] - bc[i]) > rotT then return true end end
    return false
end
local function getMainBounds()
    if savedWindow then
        local x = Main.Position.X.Offset
        local y = Main.Position.Y.Offset
        return x, y, BAR_W, BAR_H
    end
    local scale = (MainScale and MainScale.Scale) or 1
    local x = Main.Position.X.Offset
    local y = Main.Position.Y.Offset
    local w = math.floor(BASE_GUI_W * scale)
    local h = math.floor(BASE_GUI_H * scale)
    return x, y, w, h
end
local function isOverGui()
    if not Main.Visible then return false end
    local mp = UserInputService:GetMouseLocation()
    local x, y, w, h = getMainBounds()
    return mp.X >= x and mp.X <= x + w and mp.Y >= y and mp.Y <= y + h
end
local function isPointOverMainGui(px, py)
    if not Main.Visible then return false end
    local x, y, w, h = getMainBounds()
    return px >= x and px <= x + w and py >= y and py <= y + h
end

local function findBracket(kfs, t)
    local n = #kfs
    if n == 0 then return nil, nil, 0 end
    if t <= kfs[1].t then return kfs[1], kfs[1], 0 end
    if t >= kfs[n].t then return kfs[n], kfs[n], 1 end
    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if kfs[mid].t <= t then lo = mid else hi = mid - 1 end
    end
    local a, b = kfs[lo], kfs[lo + 1]
    if not b then return a, a, 0 end
    local span = b.t - a.t
    local alpha = span > 0 and (t - a.t) / span or 0
    return a, b, alpha
end

--==================================================================
--  CAMERA LOCK (multi-capa)
--==================================================================
local function enforceCamLock()
    if not camLocked then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    camSetting = true

    if cam.CameraType ~= Enum.CameraType.Scriptable then
        pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
    end
    if lastAppliedCamCF then
        local drift = (cam.CFrame.Position - lastAppliedCamCF.Position).Magnitude
        if drift > 0.01 then camDriftCount = camDriftCount + 1 end
        pcall(function() cam.CFrame = lastAppliedCamCF end)
    end
    if lastAppliedCamFOV then
        pcall(function() cam.FieldOfView = lastAppliedCamFOV end)
    end

    camSetting = false
end

local function lockCamera()
    if camLocked then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    originalCamType    = cam.CameraType
    originalCamSubject = cam.CameraSubject
    camLocked          = true
    camDriftCount      = 0

    pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)

    pcall(function()
        RunService:BindToRenderStep(CAM_LOCK_BIND_HI, 10000, enforceCamLock)
    end)
    pcall(function()
        RunService:BindToRenderStep(CAM_LOCK_BIND_LO, Enum.RenderPriority.Camera.Value + 2, enforceCamLock)
    end)
    table.insert(camLockConns, RunService.Heartbeat:Connect(enforceCamLock))
    table.insert(camLockConns, RunService.Stepped:Connect(enforceCamLock))

    table.insert(camLockConns, cam:GetPropertyChangedSignal("CameraType"):Connect(function()
        if camLocked and cam.CameraType ~= Enum.CameraType.Scriptable then
            pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)
        end
    end))
    table.insert(camLockConns, cam:GetPropertyChangedSignal("CFrame"):Connect(function()
        if not camLocked or not lastAppliedCamCF or camSetting then return end
        if (cam.CFrame.Position - lastAppliedCamCF.Position).Magnitude < 0.001 then return end
        enforceCamLock()
    end))

    print("[MacroRec] 🔒 Cámara bloqueada (RenderStep+Heartbeat+Stepped+Watchdogs)")
end

local function unlockCamera()
    if not camLocked then return end
    camLocked = false

    pcall(function() RunService:UnbindFromRenderStep(CAM_LOCK_BIND_HI) end)
    pcall(function() RunService:UnbindFromRenderStep(CAM_LOCK_BIND_LO) end)
    for _, c in ipairs(camLockConns) do
        pcall(function() c:Disconnect() end)
    end
    camLockConns = {}

    local cam = workspace.CurrentCamera
    if cam then
        if originalCamType then
            pcall(function() cam.CameraType = originalCamType end)
        end
        if originalCamSubject then
            pcall(function() cam.CameraSubject = originalCamSubject end)
        end
    end

    if camDriftCount > 0 then
        print(string.format("[MacroRec] 🔓 Cámara desbloqueada (%d correcciones)", camDriftCount))
    end

    lastAppliedCamCF   = nil
    lastAppliedCamFOV  = nil
    originalCamType    = nil
    originalCamSubject = nil
    camDriftCount      = 0
end

--==================================================================
--  TELETRANSPORTE
--==================================================================
local function teleportToStart(rec)
    if not rec or not rec.startHrpCFrame then
        return false, "sin posición guardada"
    end
    local deadline = os.clock() + 5
    local char = LocalPlayer.Character
    while os.clock() < deadline do
        if char and char:FindFirstChild("HumanoidRootPart") then break end
        task.wait(0.1)
        char = LocalPlayer.Character
    end
    if not char then return false, "sin character" end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "sin HRP" end
    local targetCF = CFrame.new(unpack(rec.startHrpCFrame))
    if char.PivotTo then
        pcall(function() char:PivotTo(targetCF) end)
    end
    task.wait(0.05)
    if (hrp.Position - targetCF.Position).Magnitude > 2 then
        pcall(function() hrp.CFrame = targetCF end)
    end
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)
    task.wait(0.3)
    if rec.startCamCFrame then
        local cam = workspace.CurrentCamera
        if cam then
            local targetCamCF = CFrame.new(unpack(rec.startCamCFrame))
            lastAppliedCamCF = targetCamCF
            if rec.startCamFOV then lastAppliedCamFOV = rec.startCamFOV end
            pcall(function()
                if cam.CameraType ~= Enum.CameraType.Scriptable then
                    cam.CameraType = Enum.CameraType.Scriptable
                end
                cam.CFrame = targetCamCF
                if rec.startCamFOV then cam.FieldOfView = rec.startCamFOV end
            end)
        end
    end
    local dist = (hrp.Position - targetCF.Position).Magnitude
    if dist > 5 then
        print(string.format("[MacroRec] ⚠ Teleport dudoso (Δ=%.1f)", dist))
    else
        print(string.format("[MacroRec] 📍 Teleport OK (Δ=%.1f)", dist))
    end
    return true, string.format("📍 restaurado (Δ=%.1f)", dist)
end

--==================================================================
--  PLAYBACK RENDERSTEP
--==================================================================
local function playbackRenderStep()
    if not state.playing then return end
    local now = os.clock()
    local base = state.playLoopStart or state.playStart or now
    local elapsed = now - base

    local camKFs = state.camKeyframes
    if camKFs and #camKFs > 0 then
        local a, b, alpha = findBracket(camKFs, elapsed)
        if a and b then
            local cf = a.cf:Lerp(b.cf, alpha)
            lastAppliedCamCF = cf
            local cam = workspace.CurrentCamera
            if cam then
                if cam.CameraType ~= Enum.CameraType.Scriptable then
                    cam.CameraType = Enum.CameraType.Scriptable
                end
                cam.CFrame = cf
                local fovA, fovB = a.fov, b.fov
                if fovA or fovB then
                    fovA = fovA or fovB
                    fovB = fovB or fovA
                    local fov = fovA + (fovB - fovA) * alpha
                    lastAppliedCamFOV = fov
                    cam.FieldOfView = fov
                end
            end
        end
    end

    if state.hasHrpData and state.moveEnabled then
        local hrpKFs = state.hrpKeyframes
        if hrpKFs and #hrpKFs > 0 then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local a, b, alpha = findBracket(hrpKFs, elapsed)
                if a and b then
                    local cf = a.cf:Lerp(b.cf, alpha)
                    pcall(function()
                        hrp.CFrame = cf
                        hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
                        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    end)
                end
            end
        end
    end
end

--==================================================================
--  CALIBRACIÓN
--==================================================================
local function mousemoveToRoblox(targetX, targetY, maxIter)
    maxIter = maxIter or 6
    if not fn.mousemoveabs then return false, "no mousemoveabs", 0 end
    local guessX, guessY = targetX, targetY
    local lastErr = math.huge
    for i = 1, maxIter do
        pcall(fn.mousemoveabs, guessX, guessY)
        task.wait(0.03)
        local actual = UserInputService:GetMouseLocation()
        local dx = targetX - actual.X
        local dy = targetY - actual.Y
        local err = math.sqrt(dx*dx + dy*dy)
        if err < 3 then return true, "OK", i end
        if err >= lastErr then return false, "no converge", i end
        lastErr = err
        guessX = guessX + dx
        guessY = guessY + dy
    end
    return false, "max iter", maxIter
end

--==================================================================
--  AUTO-CLICK
--==================================================================
local function resolveGuiPath(relPath)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil, "PlayerGui no existe" end
    relPath = relPath:gsub("/", ".")
    if relPath:sub(1, 10):lower() == "playergui." then relPath = relPath:sub(11) end
    local obj = pg
    for part in string.gmatch(relPath, "[^%.]+") do
        local child = obj:FindFirstChild(part)
        if not child then
            local ok, w = pcall(function() return obj:WaitForChild(part, 0.3) end)
            if not ok or not w then return nil, "No existe: " .. part end
            child = w
        end
        obj = child
    end
    return obj
end
local function getActiveSignals(btn)
    local active = {}
    if not hasGetConns then return active end
    for _, sigName in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up"}) do
        local sig = btn[sigName]
        if sig then
            local ok, conns = pcall(getconnections, sig)
            if ok and conns and #conns > 0 then
                table.insert(active, { name = sigName, count = #conns })
            end
        end
    end
    return active
end
local function inspectPath()
    local path = (PathBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then Status.Text = "⚠ Path vacío"; return end
    local btn, err = resolveGuiPath(path)
    if not btn then Status.Text = "❌ " .. tostring(err); return end
    Status.Text = string.format("🔍 %s @ %.0f,%.0f", btn.ClassName,
        btn.AbsolutePosition.X, btn.AbsolutePosition.Y)
end
local function forceMouseClickCalibrated(btn)
    if not btn or not btn:IsA("GuiButton") then return false, "no GuiButton" end
    if not btn.Visible then return false, "invisible" end
    local ap, as = btn.AbsolutePosition, btn.AbsoluteSize
    if as.X < 1 or as.Y < 1 then return false, "tamaño=0" end
    local cx = ap.X + as.X / 2
    local cy = ap.Y + as.Y / 2
    drawCrosshair(cx, cy, Color3.fromRGB(255, 50, 50), 2)
    mousemoveToRoblox(cx, cy)
    local finalPos = UserInputService:GetMouseLocation()
    local onTarget = finalPos.X >= ap.X and finalPos.X <= ap.X + as.X
                 and finalPos.Y >= ap.Y and finalPos.Y <= ap.Y + as.Y
    if not onTarget then return false, "cursor no calibró" end
    task.wait(0.05)
    if type(fn.mouse1click) == "function" then
        pcall(fn.mouse1click); task.wait(0.08)
    end
    if type(fn.mouse1press) == "function" and type(fn.mouse1release) == "function" then
        pcall(fn.mouse1press); task.wait(0.05); pcall(fn.mouse1release)
    end
    return true, "físico"
end
local function mobileClickButton(btn)
    if not btn or not btn:IsA("GuiButton") then return false, "no GuiButton" end
    if not btn.Visible then return false, "invisible" end
    if hasFireSignal and hasGetConns then
        local active = getActiveSignals(btn)
        for _, s in ipairs(active) do
            local sig = btn[s.name]
            if sig then
                local ok = pcall(firesignal, sig)
                if ok then return true, "firesignal(" .. s.name .. ")" end
            end
        end
    end
    local ap, as = btn.AbsolutePosition, btn.AbsoluteSize
    if as.X < 1 or as.Y < 1 then return false, "tamaño=0" end
    local cx = ap.X + as.X / 2
    local cy = ap.Y + as.Y / 2
    if hasFireTouchInput then
        pcall(firetouchinput, cx, cy, 0)
        task.wait(0.05)
        pcall(firetouchinput, cx, cy, 1)
        return true, "firetouchinput"
    elseif hasVIMSendMouse then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.08)
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
        end)
        return true, "VIM-touch"
    end
    return false, "sin método móvil"
end
local function markPath()
    local path = (PathBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then Status.Text = "⚠ Path vacío"; return end
    local btn, err = resolveGuiPath(path)
    if not btn then Status.Text = "❌ " .. tostring(err); return end
    local cx = btn.AbsolutePosition.X + btn.AbsoluteSize.X / 2
    local cy = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y / 2
    drawCrosshair(cx, cy, Color3.fromRGB(50, 200, 255), 3)
    local f = UserInputService:GetMouseLocation()
    Status.Text = string.format("📍 %.0f,%.0f → %.0f,%.0f", f.X, f.Y, cx, cy)
end
local function tryClickButton(btn)
    if not btn or not btn:IsA("GuiButton") then return false, "no GuiButton" end
    if not MouseEnabled then
        return mobileClickButton(btn)
    end
    if state.forceMouse then return forceMouseClickCalibrated(btn) end
    local active = getActiveSignals(btn)
    if #active > 0 and hasFireSignal then
        for _, s in ipairs(active) do
            local sig = btn[s.name]
            if sig then
                local ok = pcall(firesignal, sig)
                if ok then return true, "firesignal(" .. s.name .. ")" end
            end
        end
    end
    return forceMouseClickCalibrated(btn)
end
local function clickPlayAgain()
    local path = (PathBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then Status.Text = "⚠ Path vacío"; return false end
    local deadline = os.clock() + AUTO_CLICK_TIMEOUT
    local btn = nil
    while os.clock() < deadline do
        local b = resolveGuiPath(path)
        if b then btn = b; break end
        task.wait(AUTO_CLICK_POLL)
    end
    if not btn then Status.Text = "❌ Botón no encontrado"; return false end
    local ok, method = tryClickButton(btn)
    if ok then Status.Text = "✅ " .. method; return true
    else Status.Text = "❌ " .. tostring(method); return false end
end

--==================================================================
--  AUTO-CLICK FIJO (559, 511)
--==================================================================
local function getButtonAtFixedPos(x, y)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end

    local function checkChild(parent, gui)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("GuiButton") and child.Visible and child.Active then
                local ap, as = child.AbsolutePosition, child.AbsoluteSize
                if as.X > 0 and as.Y > 0
                   and x >= ap.X and x <= ap.X + as.X
                   and y >= ap.Y and y <= ap.Y + as.Y then
                    local p = child.Parent
                    local visibleChain = true
                    while p and p ~= gui do
                        if p:IsA("GuiObject") and not p.Visible then
                            visibleChain = false; break
                        end
                        p = p.Parent
                    end
                    if visibleChain then return child end
                end
            end
            local found = checkChild(child, gui)
            if found then return found end
        end
        return nil
    end

    for _, gui in ipairs(pg:GetChildren()) do
        if gui:IsA("LayerCollector") and gui.Enabled then
            local found = checkChild(gui, gui)
            if found then return found end
        end
    end
    return nil
end

local function tryFixedClick()
    if not state.fixedClickActive then return end
    local now = os.clock()
    if now - state.fixedClickLastAt < FIXED_CLICK_COOLDOWN then return end

    local mp = UserInputService:GetMouseLocation()
    local dx = mp.X - FIXED_CLICK_X
    local dy = mp.Y - FIXED_CLICK_Y
    if math.sqrt(dx*dx + dy*dy) > FIXED_CLICK_TOLERANCE then return end

    local btn = getButtonAtFixedPos(FIXED_CLICK_X, FIXED_CLICK_Y)
    if not btn then return end

    local ok, method = false, "?"
    if tryClickButton(btn) then ok = true; method = "auto" end

    if ok then
        state.fixedClickLastAt = now
        state.fixedClickLastBtn = btn
        Status.Text = "🎯 Click → " .. btn.ClassName .. " (" .. method .. ")"
        clickCircle(FIXED_CLICK_X, FIXED_CLICK_Y, Color3.fromRGB(255, 200, 50))
    end
end

--==================================================================
--  CAPTURA / HOOK
--==================================================================
local captureMode = false
local captureConns = {}

local function hookForCapture(d)
    if not d:IsA("GuiButton") then return end
    if d:IsDescendantOf(ScreenGui) or d:IsDescendantOf(OverlayGui) then return end
    if d:GetAttribute("_MRCaptured") then return end
    d:SetAttribute("_MRCaptured", true)
    local conn = d.Activated:Connect(function()
        if captureMode then
            captureMode = false
            local full = d:GetFullName()
            local relPath = full
                :gsub("^Players%.LocalPlayer%.PlayerGui%.", "")
                :gsub("^PlayerGui%.", ""):gsub("^CoreGui%.", "")
            PathBox.Text = relPath
            Status.Text = "🎯 Path: " .. relPath
            for _, c in ipairs(captureConns) do pcall(function() c:Disconnect() end) end
            captureConns = {}
        end
    end)
    table.insert(captureConns, conn)
end
local function startCapture()
    captureMode = true
    Status.Text = "🎯 Haz clic en PlayAgain"
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then for _, d in ipairs(pg:GetDescendants()) do hookForCapture(d) end end
end
local pgRef = LocalPlayer:FindFirstChildOfClass("PlayerGui")
if pgRef then pgRef.DescendantAdded:Connect(function(d) hookForCapture(d) end) end

local function hookButton(btn)
    if not btn:IsA("GuiButton") then return end
    if btn:IsDescendantOf(ScreenGui) or btn:IsDescendantOf(OverlayGui) then return end
    if btn:GetAttribute("_MRHooked") then return end
    btn:SetAttribute("_MRHooked", true)
    btn.Activated:Connect(function()
        if state.recording then
            local t = os.clock() - state.recordStart
            table.insert(state.events, { t = t, type = "gui", path = btn:GetFullName() })
        end
    end)
end
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(3)
        if state.recording then
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then for _, d in ipairs(pg:GetDescendants()) do hookButton(d) end end
        end
    end
end)
if pgRef then pgRef.DescendantAdded:Connect(function(d) hookButton(d) end) end

--==================================================================
--  GRABACIÓN
--==================================================================
local lastMousePos, lastCamCFrame, lastCamFOV = Vector2.new(-100,-100), nil, nil
local lastHrpCFrame = nil

local touchMap = {}
local nextTouchId = 0
local lastTouchPositions = {}

local function resetTouchRecording()
    touchMap = {}
    nextTouchId = 0
    lastTouchPositions = {}
end

local function pushEvent(ev)
    if not state.recording then return end
    ev.t = os.clock() - state.recordStart
    table.insert(state.events, ev)
end

local function startRecording()
    if state.playing then return end
    state.events = {}; state.recordStart = os.clock(); state.recording = true
    lastMousePos, lastCamCFrame, lastCamFOV = Vector2.new(-100,-100), nil, nil
    lastHrpCFrame = nil
    resetTouchRecording()

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    state.startHrpCFrame = hrp and hrp.CFrame or nil
    local cam = workspace.CurrentCamera
    state.startCamCFrame = cam and cam.CFrame or nil
    state.startCamFOV    = cam and cam.FieldOfView or nil
    state.startViewport  = currentViewport()

    if state.startHrpCFrame then
        local p = state.startHrpCFrame.Position
        print(string.format("[MacroRec] Pos inicial: (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z))
    else
        print("[MacroRec] ⚠ No pude capturar HRP inicial")
    end
    print(string.format("[MacroRec] Viewport grabado: %dx%d",
        state.startViewport.X, state.startViewport.Y))

    RecDot.Visible = true; BtnRecord.Text = "■ Parar"
    BtnRecord.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    Status.Text = "Grabando…"
end

local function stopRecording()
    if not state.recording then return end
    state.recording = false
    RecDot.Visible = false
    BtnRecord.Text = "● Grabar"
    BtnRecord.BackgroundColor3 = Color3.fromRGB(180, 50, 50)

    if #state.events < 2 then
        Status.Text = "Grabación vacía."
        return
    end

    local name = NameBox.Text:gsub("[^%w_%-]", "_")
    if name == "" then
        name = "Rec_" .. os.date("%H%M%S")
        NameBox.Text = name
    end
    local duration = state.events[#state.events].t or 0

    local extra = {}
    if state.startHrpCFrame then
        extra.startHrpCFrame = { state.startHrpCFrame:GetComponents() }
    end
    if state.startCamCFrame then
        extra.startCamCFrame = { state.startCamCFrame:GetComponents() }
    end
    if state.startCamFOV then
        extra.startCamFOV = state.startCamFOV
    end
    if state.startViewport then
        extra.startViewport = { state.startViewport.X, state.startViewport.Y }
    end

    local okSave, msgSave = saveRecording(name, state.events, duration, nil, extra)
    print("[MacroRec] save:", okSave and "OK" or "FAIL", "-", tostring(msgSave))

    local counts = { cam = 0, hrp = 0, touch = 0, key = 0, mouse = 0 }
    for _, ev in ipairs(state.events) do
        local t = ev.type
        if t == "cam" then counts.cam = counts.cam + 1
        elseif t == "hrp" then counts.hrp = counts.hrp + 1
        elseif t == "touchdown" or t == "touchmove" or t == "touchup"
            or t == "tap" or t == "pan" or t == "longpress" then
            counts.touch = counts.touch + 1
        elseif t == "keydown" or t == "keyup" then counts.key = counts.key + 1
        elseif t == "mouse" or t == "m1down" or t == "m1up"
            or t == "m2down" or t == "m2up" or t == "wheel" then
            counts.mouse = counts.mouse + 1
        end
    end
    print(string.format("[MacroRec] %d ev | cam=%d hrp=%d touch=%d key=%d mouse=%d",
        #state.events, counts.cam, counts.hrp, counts.touch, counts.key, counts.mouse))

    local payload = { name = name, events = state.events,
        created = os.time(), duration = duration }
    for k, v in pairs(extra) do payload[k] = v end
    local okE, enc = pcall(jsonEncode, payload)

    local clipMsg = ""
    if not okE or not enc then
        clipMsg = " ❌ encode"
    else
        local clipFn, clipName = getClipboardSetFn()
        if clipFn then
            local okC = pcall(clipFn, enc)
            if okC then clipMsg = " 📤 " .. #enc .. "B"
            else clipMsg = " ❌ " .. clipName end
        else clipMsg = " ⚠ sin clipboard" end
    end

    Status.Text = (okSave and "✅ " or "⚠ ") .. name .. clipMsg
    pcall(refreshList)
end

UserInputService.InputBegan:Connect(function(input, gp)
    if not state.recording or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F8 or input.KeyCode == Enum.KeyCode.F9
       or input.KeyCode == Enum.KeyCode.F10 or isOverGui() then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        pushEvent({ type = "keydown", key = input.KeyCode.Name })
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then pushEvent({ type = "m1down" })
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then pushEvent({ type = "m2down" }) end
end)
UserInputService.InputEnded:Connect(function(input, gp)
    if not state.recording or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F8 or input.KeyCode == Enum.KeyCode.F9
       or input.KeyCode == Enum.KeyCode.F10 or isOverGui() then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        pushEvent({ type = "keyup", key = input.KeyCode.Name })
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then pushEvent({ type = "m1up" })
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then pushEvent({ type = "m2up" }) end
end)
UserInputService.InputChanged:Connect(function(input)
    if not state.recording then return end
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        pushEvent({ type = "wheel", delta = input.Position.Z })
    end
end)

-- ====== GRABACIÓN TÁCTIL ======
if TouchEnabled then
    UserInputService.InputBegan:Connect(function(input, gp)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not state.recording then return end
        if isPointOverMainGui(input.Position.X, input.Position.Y) then return end
        if touchMap[input] then return end

        nextTouchId = nextTouchId + 1
        local id = nextTouchId
        touchMap[input] = { id = id, x = input.Position.X, y = input.Position.Y }
        lastTouchPositions[id] = Vector2.new(input.Position.X, input.Position.Y)
        pushEvent({ type = "touchdown", x = input.Position.X, y = input.Position.Y, id = id })
    end)

    UserInputService.InputChanged:Connect(function(input, gp)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not state.recording then return end
        local info = touchMap[input]
        if not info then return end
        if isPointOverMainGui(input.Position.X, input.Position.Y) then return end

        local newPos = Vector2.new(input.Position.X, input.Position.Y)
        local last = lastTouchPositions[info.id]
        if last and (newPos - last).Magnitude < REC_TOUCH_MIN_PIXELS then return end
        lastTouchPositions[info.id] = newPos

        info.x, info.y = newPos.X, newPos.Y
        pushEvent({ type = "touchmove", x = newPos.X, y = newPos.Y, id = info.id })
    end)

    UserInputService.InputEnded:Connect(function(input, gp)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not state.recording then return end
        local info = touchMap[input]
        if not info then return end

        touchMap[input] = nil
        lastTouchPositions[info.id] = nil
        pushEvent({ type = "touchup", x = input.Position.X, y = input.Position.Y, id = info.id })
    end)
end

RunService.RenderStepped:Connect(function()
    if state.recording then
        Chrono.Text = fmtDuration(os.clock() - state.recordStart)
        if MouseEnabled then
            local mp = UserInputService:GetMouseLocation()
            if (mp - lastMousePos).Magnitude > REC_MOUSE_MIN_PIXELS then
                pushEvent({ type = "mouse", x = mp.X, y = mp.Y }); lastMousePos = mp
            end
        end
        local cam = workspace.CurrentCamera
        if cam then
            local cfChanged  = cframesDiffer(lastCamCFrame, cam.CFrame, REC_CAM_POS_THRESH, REC_CAM_ROT_THRESH)
            local fovChanged = lastCamFOV == nil or math.abs(lastCamFOV - cam.FieldOfView) > REC_CAM_FOV_THRESH
            if cfChanged or fovChanged then
                pushEvent({ type = "cam", cframe = { cam.CFrame:GetComponents() }, fov = cam.FieldOfView })
                lastCamCFrame = cam.CFrame
                lastCamFOV    = cam.FieldOfView
            end
        end
        if state.moveEnabled then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                if cframesDiffer(lastHrpCFrame, hrp.CFrame, REC_HRP_POS_THRESH, REC_HRP_ROT_THRESH) then
                    pushEvent({ type = "hrp", cframe = { hrp.CFrame:GetComponents() } })
                    lastHrpCFrame = hrp.CFrame
                end
            end
        end
    elseif state.playing then
        if state.playStart then Chrono.Text = fmtDuration(os.clock() - state.playStart) end
    else
        Chrono.Text = "00:00.000"
    end
    pcall(tryFixedClick)
end)

--==================================================================
--  REPRODUCCIÓN
--==================================================================
local function waitUntil(targetT)
    while true do
        local now = os.clock()
        if now >= targetT then return end
        local d = targetT - now
        if d > 0.003 then task.wait(d - 0.002) end
    end
end
local function setMainInteractive(enabled)
    Main.Active = enabled
    for _, d in ipairs(Main:GetDescendants()) do
        if d:IsA("GuiObject") then pcall(function() d.Active = enabled end) end
    end
end
local function refreshKeysLabel()
    local list = {}
    for k in pairs(state.activeKeys) do table.insert(list, k) end
    table.sort(list)
    KeysLabel.Text = (#list > 0) and ("⌨ " .. table.concat(list, " + ")) or ""
end

local function prepareCamKeyframes(events, rec)
    local kfs = {}
    if rec and rec.startCamCFrame then
        table.insert(kfs, { t = 0, cf = CFrame.new(unpack(rec.startCamCFrame)), fov = rec.startCamFOV })
    end
    for _, ev in ipairs(events) do
        if ev.type == "cam" and ev.cframe then
            table.insert(kfs, { t = ev.t, cf = CFrame.new(unpack(ev.cframe)), fov = ev.fov })
        end
    end
    if #kfs == 0 then
        local cam = workspace.CurrentCamera
        if cam then table.insert(kfs, { t = 0, cf = cam.CFrame, fov = cam.FieldOfView }) end
    end
    return kfs
end

local function prepareHrpKeyframes(events, rec)
    local kfs = {}
    local count = 0
    if rec and rec.startHrpCFrame then
        table.insert(kfs, { t = 0, cf = CFrame.new(unpack(rec.startHrpCFrame)) })
    end
    for _, ev in ipairs(events) do
        if ev.type == "hrp" and ev.cframe then
            table.insert(kfs, { t = ev.t, cf = CFrame.new(unpack(ev.cframe)) })
            count = count + 1
        end
    end
    return kfs, count
end

local activeTouchIds = {}

local function fireTouchDown(x, y, fingerId)
    fingerId = fingerId or 1
    if activeTouchIds[fingerId] then return end
    activeTouchIds[fingerId] = { x = x, y = y }
    if hasVIMSendMouse then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, fingerId)
        end)
    end
    if hasFireTouchInput then
        pcall(firetouchinput, x, y, 0)
    end
end

local function fireTouchMove(x, y, fingerId)
    fingerId = fingerId or 1
    local active = activeTouchIds[fingerId]
    if not active then return end
    active.x, active.y = x, y
    if hasVIMSendMove then
        pcall(function()
            VirtualInputManager:SendMouseMoveEvent(x, y, game)
        end)
    end
    if hasFireTouchInput then
        pcall(firetouchinput, x, y, 2)
    end
end

local function fireTouchUp(x, y, fingerId)
    fingerId = fingerId or 1
    if not activeTouchIds[fingerId] then return end
    activeTouchIds[fingerId] = nil
    if hasVIMSendMouse then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, fingerId)
        end)
    end
    if hasFireTouchInput then
        pcall(firetouchinput, x, y, 1)
    end
end

local function releaseAllTouches()
    for fingerId, pos in pairs(activeTouchIds) do
        if hasVIMSendMouse then
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(pos.x, pos.y, 0, false, game, fingerId)
            end)
        end
        if hasFireTouchInput then
            pcall(firetouchinput, pos.x, pos.y, 1)
        end
    end
    activeTouchIds = {}
end

local function fireLegacyTap(x, y)
    if hasVIMSendMouse then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
            task.wait(0.03)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end)
    elseif hasFireTouchInput then
        pcall(firetouchinput, x, y, 0)
        task.wait(0.03)
        pcall(firetouchinput, x, y, 1)
    end
end
local function fireLegacyLongPress(x, y)
    if hasVIMSendMouse then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
        end)
        task.wait(0.5)
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end)
    elseif hasFireTouchInput then
        pcall(firetouchinput, x, y, 0)
        task.wait(0.5)
        pcall(firetouchinput, x, y, 1)
    end
end
local function fireLegacyPan(x, y)
    if hasFireTouchInput then
        pcall(firetouchinput, x, y, 2)
    elseif hasVIMSendMove then
        pcall(function()
            VirtualInputManager:SendMouseMoveEvent(x, y, game)
        end)
    end
end

local function applyEvent(ev)
    local t = ev.type
    if t == "keydown" then
        local kc = Enum.KeyCode[ev.key]
        if kc then doKeyPress(kc) end
        state.activeKeys[ev.key] = true
    elseif t == "keyup" then
        local kc = Enum.KeyCode[ev.key]
        if kc then doKeyRelease(kc) end
        state.activeKeys[ev.key] = nil
    elseif t == "m1down" then
        if fn.mouse1press then pcall(fn.mouse1press) end
        local cx, cy = Cursor.AbsolutePosition.X + 7, Cursor.AbsolutePosition.Y + 7
        clickCircle(cx, cy, Color3.fromRGB(255, 90, 90))
    elseif t == "m1up" then
        if fn.mouse1release then pcall(fn.mouse1release) end
    elseif t == "m2down" then
        if fn.mouse2press then pcall(fn.mouse2press) end
        local cx, cy = Cursor.AbsolutePosition.X + 7, Cursor.AbsolutePosition.Y + 7
        clickCircle(cx, cy, Color3.fromRGB(90, 150, 255))
    elseif t == "m2up" then
        if fn.mouse2release then pcall(fn.mouse2release) end
    elseif t == "wheel" then
        if fn.mousescroll then pcall(fn.mousescroll, ev.delta) end
    elseif t == "mouse" then
        local sx, sy = scalePoint(ev.x, ev.y)
        setFakeCursor(sx, sy)
        if fn.mousemoveabs then pcall(fn.mousemoveabs, sx, sy) end
    elseif t == "touchdown" then
        local sx, sy = scalePoint(ev.x, ev.y)
        fireTouchDown(sx, sy, ev.id)
        clickCircle(sx, sy, Color3.fromRGB(255, 200, 50))
    elseif t == "touchmove" then
        local sx, sy = scalePoint(ev.x, ev.y)
        fireTouchMove(sx, sy, ev.id)
    elseif t == "touchup" then
        local sx, sy = scalePoint(ev.x, ev.y)
        fireTouchUp(sx, sy, ev.id)
    elseif t == "tap" then
        local sx, sy = scalePoint(ev.x, ev.y)
        fireLegacyTap(sx, sy)
        clickCircle(sx, sy, Color3.fromRGB(255, 200, 50))
    elseif t == "pan" then
        local sx, sy = scalePoint(ev.x, ev.y)
        fireLegacyPan(sx, sy)
    elseif t == "longpress" then
        local sx, sy = scalePoint(ev.x, ev.y)
        fireLegacyLongPress(sx, sy)
        clickCircle(sx, sy, Color3.fromRGB(200, 100, 255))
    end
    refreshKeysLabel()
    pcall(function() MacroInput:Fire(ev) end)
end

local function restoreHumanoid()
    local h = state.controlledHumanoid
    local s = state.savedHumanoid
    if h and s and h.Parent then
        pcall(function()
            h.WalkSpeed = s.WalkSpeed
            h.JumpPower = s.JumpPower
            h.AutoRotate = s.AutoRotate
        end)
    end
    state.controlledHumanoid = nil
    state.savedHumanoid = nil
end

local function stopPlayback()
    if not state.playing then return end
    pcall(function() RunService:UnbindFromRenderStep(PLAYBACK_BIND) end)
    releaseAllTouches()
    restoreHumanoid()
    unlockCamera()
    state.playing = false; state.currentSession = state.currentSession + 1
    state.camKeyframes = nil; state.hrpKeyframes = nil; state.hasHrpData = false
    state.playViewport = nil
    Cursor.Visible = false; KeysLabel.Visible = false; StopOverlay.Visible = false
    restoreWindow()
    setMainInteractive(true)
    for k in pairs(state.activeKeys) do
        local kc = Enum.KeyCode[k]; if kc then doKeyRelease(kc) end
    end
    state.activeKeys = {}; KeysLabel.Text = ""
    Status.Text = "Detenido."
end

local function playRecording(events, name, looped, rec)
    if state.recording then stopRecording() end
    if state.playing then stopPlayback() end
    if not events or #events == 0 then Status.Text = "Grabación vacía."; return end

    local focused = UserInputService:GetFocusedTextBox()
    if focused and focused.ReleaseFocus then
        pcall(function() focused:ReleaseFocus() end)
    end

    if rec and rec.startViewport and #rec.startViewport == 2 then
        state.playViewport = { X = rec.startViewport[1], Y = rec.startViewport[2] }
        local cur = currentViewport()
        print(string.format("[MacroRec] 🔍 Escalando %dx%d → %dx%d (sx=%.2f sy=%.2f)",
            state.playViewport.X, state.playViewport.Y, cur.X, cur.Y,
            cur.X / state.playViewport.X, cur.Y / state.playViewport.Y))
    else
        local cur = currentViewport()
        state.playViewport = { X = cur.X, Y = cur.Y }
        print("[MacroRec] ℹ️ Macro sin viewport guardado → sin escalar")
    end

    lockCamera()

    if rec and rec.startHrpCFrame then
        Status.Text = "📍 Restaurando posición…"
        local ok, msg = teleportToStart(rec)
        if ok then Status.Text = msg else Status.Text = "⚠ " .. msg end
        task.wait(0.2)
    end

    state.camKeyframes = prepareCamKeyframes(events, rec)
    local hrpKFs, hrpCount = prepareHrpKeyframes(events, rec)
    state.hrpKeyframes = hrpKFs
    state.hasHrpData = (hrpCount > 0)
    activeTouchIds = {}

    if state.hasHrpData and state.moveEnabled then
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            state.controlledHumanoid = humanoid
            state.savedHumanoid = {
                WalkSpeed = humanoid.WalkSpeed,
                JumpPower = humanoid.JumpPower,
                AutoRotate = humanoid.AutoRotate,
            }
            pcall(function()
                humanoid.WalkSpeed  = 0
                humanoid.JumpPower  = 0
                humanoid.AutoRotate = false
            end)
        end
        print(string.format("[MacroRec] Movimiento ON (%d keyframes HRP)", hrpCount))
    else
        print("[MacroRec] Movimiento OFF")
    end

    do
        local cam = workspace.CurrentCamera
        if cam and #state.camKeyframes > 0 then
            local k0 = state.camKeyframes[1]
            lastAppliedCamCF = k0.cf
            if k0.fov then lastAppliedCamFOV = k0.fov end
            pcall(function()
                if cam.CameraType ~= Enum.CameraType.Scriptable then
                    cam.CameraType = Enum.CameraType.Scriptable
                end
                cam.CFrame = k0.cf
                if k0.fov then cam.FieldOfView = k0.fov end
            end)
        end
    end

    state.playing = true; state.currentSession = state.currentSession + 1
    state.playStart = os.clock(); state.playLoopStart = state.playStart
    local session = state.currentSession

    pcall(function()
        RunService:BindToRenderStep(PLAYBACK_BIND, Enum.RenderPriority.Camera.Value + 1, playbackRenderStep)
    end)

    setMainInteractive(false)
    minimizeToRight()
    Cursor.Visible = true; KeysLabel.Visible = true; StopOverlay.Visible = true
    if not (rec and rec.startHrpCFrame) then
        Status.Text = "Reproduciendo: " .. tostring(name)
    end

    task.spawn(function()
        while state.playing and session == state.currentSession do
            local startT = os.clock()
            state.playLoopStart = startT
            for i = 1, #events do
                if not state.playing or session ~= state.currentSession then return end
                local ev = events[i]
                waitUntil(startT + ev.t)
                if not state.playing or session ~= state.currentSession then return end
                if ev.type ~= "cam" and ev.type ~= "hrp" then
                    pcall(applyEvent, ev)
                end
            end
            if not looped then break end
            task.wait(0.05)
        end
        if session == state.currentSession then
            stopPlayback()
            if state.autoClick then
                Status.Text = "⏳ Auto-click en " .. AUTO_CLICK_DELAY .. "s…"
                task.wait(AUTO_CLICK_DELAY)
                if not state.playing and session == state.currentSession then
                    clickPlayAgain()
                end
            end
        end
    end)
end

--==================================================================
--  LISTA
--==================================================================
function refreshList()
    for _, c in ipairs(Scrolling:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
    end
    local names = getAllNames()
    if #names == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, -10, 0, 60); empty.BackgroundTransparency = 1
        empty.Text = "No hay grabaciones."
        empty.TextColor3 = Color3.fromRGB(120, 120, 140); empty.Font = Enum.Font.Gotham
        empty.TextSize = 12; empty.TextWrapped = true; empty.LayoutOrder = 1
        empty.Parent = Scrolling
        return
    end
    for i, name in ipairs(names) do
        local rec = loadRecording(name) or {}
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -10, 0, 42)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 38); row.BorderSizePixel = 0
        row.LayoutOrder = i; row.Parent = Scrolling
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, -130, 0, 20); nameLbl.Position = UDim2.new(0, 10, 0, 2)
        nameLbl.BackgroundTransparency = 1; nameLbl.Text = name
        nameLbl.TextColor3 = Color3.fromRGB(230, 230, 255); nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 13; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd; nameLbl.Parent = row

        local infoLbl = Instance.new("TextLabel")
        infoLbl.Size = UDim2.new(1, -130, 0, 16); infoLbl.Position = UDim2.new(0, 10, 0, 22)
        infoLbl.BackgroundTransparency = 1
        infoLbl.Text = "⏱ " .. fmtDuration(rec.duration or 0) .. "   📅 " .. fmtDate(rec.created)
        infoLbl.TextColor3 = Color3.fromRGB(150, 150, 180); infoLbl.Font = Enum.Font.Gotham
        infoLbl.TextSize = 11; infoLbl.TextXAlignment = Enum.TextXAlignment.Left; infoLbl.Parent = row

        local function mkSmallBtn(txt, col, x)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, 28, 0, 30); b.Position = UDim2.new(1, x, 0, 6)
            b.BackgroundColor3 = col; b.Text = txt; b.TextColor3 = Color3.new(1, 1, 1)
            b.Font = Enum.Font.GothamBold; b.TextSize = 16; b.BorderSizePixel = 0
            b.Parent = row; Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
            return b
        end

        local isAutoload = (name == state.autoloadName)
        local autoBtn = mkSmallBtn(
            isAutoload and "🍌" or "🐵",
            isAutoload and Color3.fromRGB(200, 160, 40) or Color3.fromRGB(90, 70, 50),
            -124
        )
        autoBtn.MouseButton1Click:Connect(function()
            if state.autoloadName == name then
                state.autoloadName = nil
                writeAutoload(nil)
                Status.Text = "🍌 Auto-ejecutar desactivado"
            else
                state.autoloadName = name
                writeAutoload(name)
                Status.Text = "🐵 Auto-ejecutar: " .. name
            end
            refreshList()
        end)

        local pBtn = mkSmallBtn("▶", Color3.fromRGB(50, 150, 80), -94)
        local eBtn = mkSmallBtn("📤", Color3.fromRGB(50, 100, 150), -64)
        local dBtn = mkSmallBtn("X", Color3.fromRGB(190, 60, 60), -34)

        row.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local r = loadRecording(name)
                if r and r.events then playRecording(r.events, name, state.looped, r) end
            end
        end)
        nameLbl.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then NameBox.Text = name end
        end)
        pBtn.MouseButton1Click:Connect(function()
            local r = loadRecording(name)
            if r and r.events then NameBox.Text = name; playRecording(r.events, name, state.looped, r) end
        end)
        eBtn.MouseButton1Click:Connect(function()
            local rec2 = loadRecording(name)
            if not rec2 then Status.Text = "❌ No carga"; return end
            local okE, enc = pcall(jsonEncode, rec2)
            if not okE then Status.Text = "❌ encode"; return end
            local clipFn = getClipboardSetFn()
            if clipFn then
                local okC = pcall(clipFn, enc)
                if okC then Status.Text = "📤 " .. name .. " (" .. #enc .. "B)"
                else Status.Text = "❌ clipboard" end
            else
                Status.Text = "⚠ sin clipboard — en consola"
                print("=== COPY " .. name .. " ==="); print(enc); print("=== FIN ===")
            end
        end)
        dBtn.MouseButton1Click:Connect(function()
            deleteRecording(name)
            if state.autoloadName == name then
                state.autoloadName = nil
                writeAutoload(nil)
            end
            Status.Text = "🗑 " .. name
            refreshList()
        end)
    end
end

--==================================================================
--  CONEXIONES
--==================================================================
BtnRecord.MouseButton1Click:Connect(function()
    if state.recording then stopRecording() else startRecording() end
end)
BtnPlay.MouseButton1Click:Connect(function()
    local name = NameBox.Text:gsub("[^%w_%-]", "_")
    if name == "" then Status.Text = "Escribe un nombre."; return end
    local r = loadRecording(name)
    if not r or not r.events then Status.Text = "No existe: " .. name; return end
    playRecording(r.events, name, state.looped, r)
end)
BtnStop.MouseButton1Click:Connect(function()
    if state.recording then stopRecording() end
    if state.playing then stopPlayback() end
end)
BtnLoop.MouseButton1Click:Connect(function()
    state.looped = not state.looped
    BtnLoop.Text = "Loop: " .. (state.looped and "ON" or "OFF")
    BtnLoop.BackgroundColor3 = state.looped and Color3.fromRGB(50, 130, 70) or Color3.fromRGB(60, 60, 80)
end)
BtnAuto.MouseButton1Click:Connect(function()
    state.autoClick = not state.autoClick
    BtnAuto.Text = "Auto: " .. (state.autoClick and "ON" or "OFF")
    BtnAuto.BackgroundColor3 = state.autoClick and Color3.fromRGB(50, 130, 70) or Color3.fromRGB(60, 60, 80)
end)
BtnTestClick.MouseButton1Click:Connect(function() task.spawn(clickPlayAgain) end)
BtnInspect.MouseButton1Click:Connect(inspectPath)
BtnMark.MouseButton1Click:Connect(markPath)
BtnCapture.MouseButton1Click:Connect(function()
    if captureMode then captureMode = false; Status.Text = "🎯 Cancelado"
    else startCapture() end
end)
ForceMouseBtn.MouseButton1Click:Connect(function()
    state.forceMouse = not state.forceMouse
    ForceMouseBtn.BackgroundColor3 = state.forceMouse
        and Color3.fromRGB(50, 130, 70) or Color3.fromRGB(60, 60, 80)
    Status.Text = state.forceMouse and "🖱 Forzar mouse ON" or "Método auto"
end)
MovToggleBtn.MouseButton1Click:Connect(function()
    state.moveEnabled = not state.moveEnabled
    if state.moveEnabled then
        MovToggleBtn.Text = "🏃 Mov ON"
        MovToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 130, 70)
        Status.Text = "🏃 Movimiento del personaje ON"
    else
        MovToggleBtn.Text = "🏃 Mov OFF"
        MovToggleBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 60)
        Status.Text = "Movimiento del personaje OFF (solo teclas/touch)"
    end
end)

FixedClickBtn.MouseButton1Click:Connect(function()
    state.fixedClickActive = not state.fixedClickActive
    if state.fixedClickActive then
        FixedClickBtn.Text = "🎯 Auto-click fijo (" .. FIXED_CLICK_X .. ", " .. FIXED_CLICK_Y .. "): ON"
        FixedClickBtn.BackgroundColor3 = Color3.fromRGB(50, 130, 70)
        FixedMarker.Visible = true
        Status.Text = "🎯 Vigilando (" .. FIXED_CLICK_X .. ", " .. FIXED_CLICK_Y .. ")"
    else
        FixedClickBtn.Text = "🎯 Auto-click fijo (" .. FIXED_CLICK_X .. ", " .. FIXED_CLICK_Y .. "): OFF"
        FixedClickBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        FixedMarker.Visible = false
        Status.Text = "Auto-click fijo desactivado"
    end
end)

ImportBtn.MouseButton1Click:Connect(function()
    if not hasGetClipboard then Status.Text = "❌ getclipboard no disponible"; return end
    local ok, raw = pcall(getclipboard)
    if not ok or not raw or raw == "" then Status.Text = "❌ Portapapeles vacío"; return end
    local saved, skipped, err, fname, method = importFromText(raw)
    if err then Status.Text = "❌ " .. err:sub(1, 60); return end
    if fname and saved == 1 then NameBox.Text = fname end
    Status.Text = "📥 " .. saved .. " (" .. skipped .. ") via " .. tostring(method or "?")
    refreshList()
end)

OpenFileBtn.MouseButton1Click:Connect(function()
    if not hasFS then Status.Text = "❌ executor sin FS"; return end
    local fname = NameBox.Text:gsub("[^%w_%-]", "_")
    if fname == "" then
        local files = {}
        if activeFolder and type(listfiles) == "function" then
            local okL, list = pcall(listfiles, activeFolder)
            if okL and list then
                for _, f in ipairs(list) do
                    local base = tostring(f):match("([^/\\]+)%.json$")
                    if base and base ~= "index" and base ~= "autoload" then table.insert(files, base) end
                end
            end
        end
        if #files == 0 then Status.Text = "❌ No hay .json en " .. tostring(activeFolder)
        else Status.Text = "📂 Escribe uno: " .. table.concat(files, ", "):sub(1, 80) end
        return
    end
    local target = activeFolder .. fname .. ".json"
    if not isfile(target) then
        Status.Text = "❌ No existe " .. target
        print("[MacroRec] No existe: " .. target)
        return
    end
    local ok, raw = pcall(readfile, target)
    if not ok or not raw then Status.Text = "❌ readfile falló"; return end
    print("[MacroRec] 📂 abriendo " .. target .. " (" .. #raw .. " bytes)")
    local saved, skipped, err, first, method = importFromText(raw)
    if err then Status.Text = "❌ " .. err:sub(1, 60); print("[MacroRec] " .. err); return end
    if first and saved == 1 then NameBox.Text = first end
    Status.Text = "📂 " .. saved .. " (" .. skipped .. ") via " .. tostring(method or "?")
    refreshList()
end)

PasteBtn.MouseButton1Click:Connect(function() openPasteModal() end)

ExportAllBtn.MouseButton1Click:Connect(function()
    local all = {}
    for _, name in ipairs(getAllNames()) do
        local r = loadRecording(name); if r then table.insert(all, r) end
    end
    if #all == 0 then Status.Text = "❌ Nada"; return end
    local clipFn = getClipboardSetFn()
    if not clipFn then
        Status.Text = "⚠ sin clipboard — en consola"
        print("=== EXPORT ALL ==="); print(jsonEncode(all)); print("=== FIN ===")
        return
    end
    local okE, enc = pcall(jsonEncode, all)
    if not okE then Status.Text = "❌ encode"; return end
    local okC = pcall(clipFn, enc)
    if okC then Status.Text = "📤 " .. #all .. " copiadas (" .. #enc .. "B)"
    else Status.Text = "❌ clipboard"; print("=== EXPORT ALL ==="); print(enc); print("=== FIN ===") end
end)
RefreshBtn.MouseButton1Click:Connect(function()
    refreshList(); Status.Text = "Recargado"
end)
StopOverlay.MouseButton1Click:Connect(function()
    if state.recording then stopRecording() end
    if state.playing then stopPlayback() end
end)
CloseBtn.MouseButton1Click:Connect(function()
    if state.recording then stopRecording() end
    if state.playing then stopPlayback() end
    releaseAllTouches()
    unlockCamera()
    restoreWindow()
    pcall(function() ScreenGui:Destroy() end); pcall(function() OverlayGui:Destroy() end)
end)

PMFromClip.MouseButton1Click:Connect(function()
    if not hasGetClipboard then PMCount.Text = "❌ getclipboard no disponible"; return end
    local ok, raw = pcall(getclipboard)
    if ok and raw and raw ~= "" then PMBox.Text = raw
    else PMCount.Text = "❌ Portapapeles vacío" end
end)
PMCancel.MouseButton1Click:Connect(closePasteModal)
PMCargar.MouseButton1Click:Connect(function()
    local raw = PMBox.Text
    if not raw or raw:gsub("%s", "") == "" then PMCount.Text = "❌ Caja vacía"; return end
    local saved, skipped, err, fname, method = importFromText(raw)
    if err then
        PMCount.Text = "❌ " .. err
        print("[MacroRec] Import error: " .. err)
        return
    end
    if fname and saved == 1 then NameBox.Text = fname end
    Status.Text = "📋 " .. saved .. " (" .. skipped .. ") via " .. tostring(method or "?")
    closePasteModal()
    refreshList()
end)
PMBackdrop.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        closePasteModal()
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F8 then
        if state.recording then stopRecording() else startRecording() end
    elseif input.KeyCode == Enum.KeyCode.F9 then
        local name = NameBox.Text:gsub("[^%w_%-]", "_")
        if name ~= "" then
            local r = loadRecording(name)
            if r and r.events then playRecording(r.events, name, state.looped, r) end
        end
    elseif input.KeyCode == Enum.KeyCode.F10 then
        if state.recording then stopRecording() end
        if state.playing then stopPlayback() end
    elseif input.KeyCode == Enum.KeyCode.F11 then
        -- Toggle rápido del auto-click fijo
        if FixedClickBtn and FixedClickBtn.Parent then
            FixedClickBtn:FireClick()
        end
    end
end)

--==================================================================
--  INIT
--==================================================================
updateGuiScale()

do
    local lastVP = currentViewport()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not Main or not Main.Parent then
            pcall(function() conn:Disconnect() end)
            return
        end
        local vp = currentViewport()
        if vp.X ~= lastVP.X or vp.Y ~= lastVP.Y then
            lastVP = vp
            pcall(updateGuiScale)
        end
    end)
end

state.autoloadName = readAutoload()
if state.autoloadName then
    print("[MacroRec] 🍌 Auto-load configurada: " .. state.autoloadName)
end

refreshList()

if not hasFS then Status.Text = "⚠ Sin FS: usa 📤/📋 entre juegos"
elseif isSharedFolder then Status.Text = "✅ Compartida: " .. activeFolder
else Status.Text = "⚠ Carpeta per-game: " .. activeFolder end

if AUTO_LOAD_OUTPUT then
    local trimmed = AUTO_LOAD_JSON:gsub("^%s+", ""):gsub("%s+$", "")
    if #trimmed > 10 then
        print("[MacroRec] AUTO_LOAD: JSON de " .. #trimmed .. "B")
        local saved, skipped, err, fname, method = importFromText(trimmed)
        if err then
            warn("[MacroRec] AUTO_LOAD falló: " .. tostring(err))
            Status.Text = "⚠ AUTO_LOAD: " .. tostring(err):sub(1, 60)
        else
            print("[MacroRec] AUTO_LOAD OK via " .. tostring(method) .. " → " .. saved)
            if fname and saved == 1 then NameBox.Text = fname; Status.Text = "✅ AUTO_LOAD: " .. fname
            else Status.Text = "✅ AUTO_LOAD: " .. saved .. " grabaciones" end
            refreshList()
        end
    else
        print("[MacroRec] AUTO_LOAD_JSON vacío (" .. #trimmed .. "B)")
    end
end

if state.autoloadName then
    local r = loadRecording(state.autoloadName)
    if not r or not r.events then
        print("[MacroRec] ⚠ Auto-load: '" .. state.autoloadName .. "' no existe. Limpiando.")
        state.autoloadName = nil
        writeAutoload(nil)
        refreshList()
    else
        print(string.format("[MacroRec] 🐵 Auto-ejecutando '%s' en %.1fs…",
            state.autoloadName, AUTO_EXECUTE_DELAY))
        local nameToPlay = state.autoloadName
        task.spawn(function()
            task.wait(AUTO_EXECUTE_DELAY)
            local r2 = loadRecording(nameToPlay)
            if r2 and r2.events then
                Status.Text = "🐵 Auto-ejecutando: " .. nameToPlay
                NameBox.Text = nameToPlay
                playRecording(r2.events, nameToPlay, state.looped, r2)
            else
                Status.Text = "⚠ Auto-load: " .. nameToPlay .. " desapareció"
            end
        end)
    end
end

print("=== Macro Recorder v8.4 ===")
print(string.format("[Plataforma] Touch=%s Mouse=%s Keyboard=%s | firetouchinput=%s VIM=%s",
    tostring(TouchEnabled), tostring(MouseEnabled), tostring(KeyboardEnabled),
    tostring(hasFireTouchInput), tostring(hasVIMSendMouse)))
print(string.format("[Viewport inicial] %dx%d",
    currentViewport().X, currentViewport().Y))
print(string.format("[Auto-click fijo] (%d, %d) ±%d px | cooldown %.2fs",
    FIXED_CLICK_X, FIXED_CLICK_Y, FIXED_CLICK_TOLERANCE, FIXED_CLICK_COOLDOWN))
print("F8=Grabar  F9=Reproducir  F10=Detener  F11=Auto-click fijo ON/OFF")
print("🐵 = auto-ejecutar  🍌 = quitar  |  🎯 = vigilar (559, 511)")
print("Carpeta activa: " .. tostring(activeFolder))
