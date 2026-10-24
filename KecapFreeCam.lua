-- ==========================================
-- FREE CAM v17 by kecap (Content Edition)
-- P = on/off | L = hide UI | WASD/E/Q gerak | Shift cepat
-- ==========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local SETTINGS_FILE = "kecap_freecam.json"

-- ============ SOUND ============
local UI_MIN, UI_MAX, UI_STEP = 0.7, 1.4, 0.1

local CLICK_ID = "rbxassetid://6895079853"
local WHOOSH_ID = "rbxassetid://12222200"
local SOUNDS = {
    click  = { id = CLICK_ID, speed = 1.0, vol = 0.5 },
    on     = { id = CLICK_ID, speed = 1.35, vol = 0.5 },
    off    = { id = CLICK_ID, speed = 0.7, vol = 0.5 },
    whoosh = { id = WHOOSH_ID, speed = 1.0, vol = 0.6 },
    intro  = { id = WHOOSH_ID, speed = 1.2, vol = 0.6 },
}

-- ============ LOAD SETTINGS ============
local saved = {}
pcall(function()
    if typeof(isfile) == "function" and isfile(SETTINGS_FILE) then
        saved = HttpService:JSONDecode(readfile(SETTINGS_FILE))
    end
end)

local function keyFrom(name, default)
    local ok, k = pcall(function()
        return Enum.KeyCode[name]
    end)
    if ok and k then
        return k
    end
    return default
end

-- ============ CONFIG ============
local C = {
    BASE_SPEED = 40, FAST_MULT = 3,
    SPEED_MIN = 0.1, SPEED_MAX = 4,
    SENS = 0.2,
    ZOOM_STEP = 4, FOV_MIN = 20, FOV_MAX = 110,
    CAMDIST_MIN = 4, CAMDIST_MAX = 80,
    PANEL_W = 280, PANEL_H = 460, BUBBLE = 54,
    SPEC_W = 240, SPEC_H = 460, SPEC_GAP = 12,
    ACCENT = Color3.fromRGB(139, 92, 246),
    ACCENT_LIGHT = Color3.fromRGB(200, 175, 255),
    BG = Color3.fromRGB(14, 14, 20),
    BG_LIGHT = Color3.fromRGB(26, 22, 40),
    PANEL = Color3.fromRGB(30, 28, 44),
    OFF = Color3.fromRGB(58, 58, 72),
    DIM = Color3.fromRGB(150, 150, 170),
    TEXT = Color3.fromRGB(225, 225, 235),
    WHITE = Color3.fromRGB(255, 255, 255),
}

-- ============ STATE ============
local S = {
    enabled = false,
    listening = nil,
    minimized = false,
    hidden = false,
    rotating = false,
    headLock = saved.headLock == true,
    orbitCenter = nil, camDist = 12,
    dragging = false, dragMoved = false, dragStart = nil, dragPos = nil,
    pos = Vector3.new(0, 0, 0), targetPos = Vector3.new(0, 0, 0),
    yaw = 0, pitch = 0, tYaw = 0, tPitch = 0,
    savedFov = 70, curFov = 70, tFov = 70,
    savedWalk = nil, savedJump = nil,
    speed = tonumber(saved.speed) or 1.0,
    smooth = tonumber(saved.smooth) or 10,
    keybind = keyFrom(saved.keybind, Enum.KeyCode.P),
    hideKey = keyFrom(saved.hideKey, Enum.KeyCode.L),
    uiScale = math.clamp(tonumber(saved.uiScale) or 1, UI_MIN, UI_MAX),
}

local SP = { pending = nil, target = nil, active = false, pickMode = false, charConn = nil }
local UI = {}
local sliderDrag = nil
local animToken = 0
local origT = setmetatable({}, { __mode = "k" })

-- Forward declarations
local stopSpectate, applySubject, startSpectate, refreshList, setPending, setPickMode, hideSpec, showSpec

-- ============ HELPERS ============
local function tween(obj, props, t, style, dir)
    local info = TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local function playSound(key)
    local cfg = SOUNDS[key]
    if not cfg then return end
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = cfg.id
        s.Volume = cfg.vol
        s.PlaybackSpeed = cfg.speed
        s.Parent = SoundService
        s:Play()
        task.delay(6, function()
            if s.Parent then s:Destroy() end
        end)
    end)
end

local function makeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius
    c.Parent = parent
    return c
end

local function makeStroke(parent, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = C.ACCENT
    s.Thickness = thickness
    s.Transparency = transparency
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function makeLabel(parent, text, x, y, w, h, font, size, color, align)
    local l = Instance.new("TextLabel")
    l.Position = UDim2.fromOffset(x, y)
    l.Size = UDim2.fromOffset(w, h)
    l.BackgroundTransparency = 1
    l.Font = font
    l.TextSize = size
    l.TextColor3 = color
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

local function glowText(obj, strength)
    obj.TextStrokeColor3 = C.ACCENT
    obj.TextStrokeTransparency = strength or 0.3
end

local function fadeAll(root, out, t)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("GuiObject") then
            if origT[obj] == nil then
                origT[obj] = obj.BackgroundTransparency
            end
            tween(obj, { BackgroundTransparency = out and 1 or origT[obj] }, t)
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                tween(obj, { TextTransparency = out and 1 or 0 }, t)
            end
            if obj:IsA("ImageLabel") then
                tween(obj, { ImageTransparency = out and 1 or 0 }, t)
            end
        end
    end
end

local function fadeTexts(root, value, t)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            tween(obj, { TextTransparency = value }, t)
        end
    end
end

local function makeButton(parent, text, x, y, w, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, h)
    b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = C.PANEL
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextColor3 = C.ACCENT_LIGHT
    b.Text = text
    b.AutoButtonColor = false
    b.ZIndex = 5
    b.Parent = parent
    makeCorner(b, UDim.new(0, 8))
    local st = makeStroke(b, 1.2, 0.7)
    b.MouseEnter:Connect(function()
        tween(st, { Transparency = 0.1 }, 0.2)
        tween(b, { BackgroundColor3 = C.OFF }, 0.2)
    end)
    b.MouseLeave:Connect(function()
        tween(st, { Transparency = 0.7 }, 0.2)
        tween(b, { BackgroundColor3 = C.PANEL }, 0.2)
    end)
    return b
end

local function onClick(btn, fn, snd)
    btn.Activated:Connect(function()
        if snd ~= false then
            playSound(snd or "click")
        end
        fn()
    end)
end

local function saveSettings()
    if typeof(writefile) ~= "function" then return end
    pcall(function()
        writefile(SETTINGS_FILE, HttpService:JSONEncode({
            speed = S.speed,
            smooth = S.smooth,
            keybind = S.keybind.Name,
            hideKey = S.hideKey.Name,
            uiScale = S.uiScale,
            headLock = S.headLock,
        }))
    end)
end

local function getSelfThumb()
    local ok, img = pcall(function()
        return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    end)
    return ok and img or ""
end

-- ============ GUI ROOT ============
local gui = Instance.new("ScreenGui")
gui.Name = "KecapFreecam"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true
if not pcall(function() gui.Parent = CoreGui end) or gui.Parent == nil then
    gui.Parent = player:WaitForChild("PlayerGui")
end

local function toast(_) end

-- ============ PANEL FREECAM ============
UI.panel = Instance.new("Frame")
UI.panel.AnchorPoint = Vector2.new(0.5, 0.5)
UI.panel.Size = UDim2.fromOffset(C.BUBBLE, C.BUBBLE)
UI.panel.Position = UDim2.new(0.5, -(C.PANEL_W + C.SPEC_GAP + C.SPEC_W) / 2 + C.PANEL_W / 2, 0.5, 0)
UI.panel.BackgroundColor3 = C.BG
UI.panel.BackgroundTransparency = 1
UI.panel.BorderSizePixel = 0
UI.panel.Active = true
UI.panel.Parent = gui

UI.scale = Instance.new("UIScale")
UI.scale.Scale = S.uiScale
UI.scale.Parent = UI.panel

UI.corner = makeCorner(UI.panel, UDim.new(0.5, 0))

UI.grad = Instance.new("UIGradient")
UI.grad.Rotation = 90
UI.grad.Color = ColorSequence.new(C.BG_LIGHT, C.BG)
UI.grad.Parent = UI.panel

UI.glow1 = makeStroke(UI.panel, 1.5, 1)
UI.glow2 = makeStroke(UI.panel, 4, 1)
UI.glow3 = makeStroke(UI.panel, 9, 1)

UI.content = Instance.new("Frame")
UI.content.Size = UDim2.new(1, 0, 1, 0)
UI.content.BackgroundTransparency = 1
UI.content.Visible = false
UI.content.Parent = UI.panel

-- Area drag
UI.dragBar = Instance.new("Frame")
UI.dragBar.Size = UDim2.new(1, -44, 0, 46)
UI.dragBar.BackgroundTransparency = 1
UI.dragBar.Active = true
UI.dragBar.ZIndex = 1
UI.dragBar.Parent = UI.content

UI.headImg = Instance.new("ImageLabel")
UI.headImg.Size = UDim2.fromOffset(26, 26)
UI.headImg.Position = UDim2.fromOffset(14, 10)
UI.headImg.BackgroundColor3 = C.PANEL
UI.headImg.BorderSizePixel = 0
UI.headImg.Image = ""
UI.headImg.Parent = UI.content
makeCorner(UI.headImg, UDim.new(0.5, 0))
makeStroke(UI.headImg, 1.5, 0.2)

UI.title = makeLabel(UI.content, "FREE CAM by kecap", 48, 14, 200, 22, Enum.Font.GothamBlack, 15, C.WHITE)
glowText(UI.title, 0.2)

UI.minBtn = makeButton(UI.content, "-", 0, 12, 26, 26)
UI.minBtn.Position = UDim2.new(1, -40, 0, 12)
UI.minBtn.TextSize = 16

-- Freecam toggle
makeLabel(UI.content, "Freecam", 16, 56, 90, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.statusValue = makeLabel(UI.content, "OFF", 100, 56, 40, 20, Enum.Font.GothamBold, 13, C.DIM)

UI.track = Instance.new("TextButton")
UI.track.Size = UDim2.fromOffset(46, 24)
UI.track.Position = UDim2.new(1, -62, 0, 54)
UI.track.BackgroundColor3 = C.OFF
UI.track.BorderSizePixel = 0
UI.track.Text = ""
UI.track.AutoButtonColor = false
UI.track.ZIndex = 5
UI.track.Parent = UI.content
makeCorner(UI.track, UDim.new(1, 0))
makeStroke(UI.track, 1.2, 0.6)

UI.knob = Instance.new("Frame")
UI.knob.Size = UDim2.fromOffset(18, 18)
UI.knob.Position = UDim2.fromOffset(3, 3)
UI.knob.BackgroundColor3 = C.WHITE
UI.knob.BorderSizePixel = 0
UI.knob.Parent = UI.track
makeCorner(UI.knob, UDim.new(1, 0))

-- Keybind freecam
makeLabel(UI.content, "Keybind", 16, 94, 120, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.keyBtn = makeButton(UI.content, S.keybind.Name, 0, 92, 78, 26)
UI.keyBtn.Position = UDim2.new(1, -94, 0, 92)
UI.keyBtn.TextSize = 12

-- Speed
makeLabel(UI.content, "Speed", 16, 130, 120, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.speedValue = makeLabel(UI.content, "", C.PANEL_W - 76, 130, 60, 20, Enum.Font.GothamBold, 13, C.ACCENT_LIGHT, Enum.TextXAlignment.Right)
glowText(UI.speedValue, 0.5)

-- Smooth
makeLabel(UI.content, "Smooth", 16, 180, 120, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.smoothValue = makeLabel(UI.content, "", C.PANEL_W - 76, 180, 60, 20, Enum.Font.GothamBold, 13, C.ACCENT_LIGHT, Enum.TextXAlignment.Right)
glowText(UI.smoothValue, 0.5)

-- Ukuran UI
makeLabel(UI.content, "Ukuran UI", 16, 228, 120, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.sizeValue = makeLabel(UI.content, "", C.PANEL_W - 76, 228, 60, 20, Enum.Font.GothamBold, 13, C.ACCENT_LIGHT, Enum.TextXAlignment.Right)
glowText(UI.sizeValue, 0.5)

-- Head tracking
makeLabel(UI.content, "Head tracking", 16, 278, 120, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.headBtn = makeButton(UI.content, "OFF", 0, 274, 78, 24)
UI.headBtn.Position = UDim2.new(1, -94, 0, 274)

-- Hide UI
makeLabel(UI.content, "Hide UI", 16, 318, 80, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.hideKeyBtn = makeButton(UI.content, S.hideKey.Name, 0, 314, 78, 24)
UI.hideKeyBtn.Position = UDim2.new(1, -94, 0, 314)
UI.hideKeyBtn.TextSize = 12

-- Tombol Konten Baru: Rejoin & Server Hop
local rejoinBtn = makeButton(UI.content, "Rejoin", 16, 356, 116, 28)
local hopBtn = makeButton(UI.content, "Server Hop", 140, 356, 124, 28)

onClick(rejoinBtn, function()
    rejoinBtn.Text = "Connecting..."
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end)
end)

onClick(hopBtn, function()
    hopBtn.Text = "Searching..."
    task.spawn(function()
        local suc, res = pcall(function()
            local servers = {}
            local req = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
            for _, s in ipairs(req.data) do
                if s.playing < s.maxPlayers and s.id ~= game.JobId then
                    table.insert(servers, s.id)
                end
            end
            if #servers > 0 then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1, #servers)], player)
            else
                hopBtn.Text = "No Server!"
                task.wait(2)
                hopBtn.Text = "Server Hop"
            end
        end)
        if not suc then
            hopBtn.Text = "Failed!"
            task.wait(2)
            hopBtn.Text = "Server Hop"
        end
    end)
end)

-- Hint & footer
UI.hint = makeLabel(UI.content, "", 16, 396, C.PANEL_W - 32, 14, Enum.Font.Gotham, 10, C.DIM)
UI.footer = makeLabel(UI.content, "by kecap", 16, C.PANEL_H - 26, 120, 16, Enum.Font.GothamMedium, 11, C.DIM)
glowText(UI.footer, 0.4)

-- Bulatan minimize
UI.kBtn = Instance.new("TextButton")
UI.kBtn.Size = UDim2.new(1, 0, 1, 0)
UI.kBtn.BackgroundTransparency = 1
UI.kBtn.Text = ""
UI.kBtn.AutoButtonColor = false
UI.kBtn.Visible = false
UI.kBtn.Parent = UI.panel

UI.bubbleImg = Instance.new("ImageLabel")
UI.bubbleImg.AnchorPoint = Vector2.new(0.5, 0.5)
UI.bubbleImg.Position = UDim2.new(0.5, 0, 0.5, 0)
UI.bubbleImg.Size = UDim2.new(1, -8, 1, -8)
UI.bubbleImg.BackgroundColor3 = C.PANEL
UI.bubbleImg.BorderSizePixel = 0
UI.bubbleImg.Image = ""
UI.bubbleImg.ImageTransparency = 1
UI.bubbleImg.Parent = UI.kBtn
makeCorner(UI.bubbleImg, UDim.new(0.5, 0))
makeStroke(UI.bubbleImg, 1.5, 0.2)

-- ============ SLIDER ============
local function makeSlider(y, minV, maxV, step, value, onChange)
    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -32, 0, 6)
    track.Position = UDim2.fromOffset(16, y)
    track.BackgroundColor3 = C.OFF
    track.BorderSizePixel = 0
    track.Parent = UI.content
    makeCorner(track, UDim.new(1, 0))

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = C.ACCENT
    fill.BorderSizePixel = 0
    fill.Parent = track
    makeCorner(fill, UDim.new(1, 0))

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = C.WHITE
    knob.BorderSizePixel = 0
    knob.Parent = track
    makeCorner(knob, UDim.new(1, 0))

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1, 0, 0, 24)
    hit.Position = UDim2.new(0, 0, 0.5, -12)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.ZIndex = 5
    hit.Parent = track

    local obj = { value = nil }
    local function show(v)
        local r = (v - minV) / (maxV - minV)
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, 0, 0.5, 0)
    end
    function obj.set(v)
        v = math.clamp(v, minV, maxV)
        v = math.floor(v / step + 0.5) * step
        obj.value = v
        show(v)
    end
    function obj.fromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local v = minV + rel * (maxV - minV)
        v = math.floor(v / step + 0.5) * step
        if v ~= obj.value then
            obj.value = v
            show(v)
            onChange(v)
        end
    end
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliderDrag = obj
            playSound("click")
            obj.fromX(input.Position.X)
        end
    end)
    obj.set(value)
    return obj
end

makeSlider(160, C.SPEED_MIN, C.SPEED_MAX, 0.1, S.speed, function(v)
    S.speed = v
    UI.speedValue.Text = string.format("%.1fx", v)
end)
UI.speedValue.Text = string.format("%.1fx", S.speed)

makeSlider(208, 2, 25, 1, S.smooth, function(v)
    S.smooth = v
    UI.smoothValue.Text = tostring(v)
end)
UI.smoothValue.Text = tostring(S.smooth)

makeSlider(256, UI_MIN, UI_MAX, UI_STEP, S.uiScale, function(v)
    S.uiScale = v
    tween(UI.scale, { Scale = v }, 0.15)
    UI.sizeValue.Text = string.format("%.1fx", v)
end)
UI.sizeValue.Text = string.format("%.1fx", S.uiScale)

-- ============ PANEL SPECTATE ============
local spFrame = Instance.new("Frame")
spFrame.Size = UDim2.fromOffset(C.SPEC_W, C.SPEC_H)
spFrame.Position = UDim2.fromOffset(C.PANEL_W + C.SPEC_GAP, 0)
spFrame.BackgroundColor3 = C.BG
spFrame.BackgroundTransparency = 1
spFrame.BorderSizePixel = 0
spFrame.Active = true
spFrame.Visible = false
spFrame.Parent = UI.panel
makeCorner(spFrame, UDim.new(0, 14))
UI.spFrame = spFrame

local spScale = Instance.new("UIScale")
spScale.Scale = 1
spScale.Parent = spFrame

local spG1 = makeStroke(spFrame, 1.5, 1)
local spG2 = makeStroke(spFrame, 4, 1)
local spG3 = makeStroke(spFrame, 8, 1)
TweenService:Create(
    spG3,
    TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    { Transparency = 0.75 }
):Play()

local specTitle = makeLabel(spFrame, "SPECTATE", 14, 10, 160, 20, Enum.Font.GothamBlack, 15, C.WHITE)
glowText(specTitle, 0.2)

SP.thumb = Instance.new("ImageLabel")
SP.thumb.Size = UDim2.fromOffset(52, 52)
SP.thumb.Position = UDim2.fromOffset(14, 38)
SP.thumb.BackgroundColor3 = C.PANEL
SP.thumb.BorderSizePixel = 0
SP.thumb.Image = ""
SP.thumb.Parent = spFrame
makeCorner(SP.thumb, UDim.new(0.5, 0))
makeStroke(SP.thumb, 1.5, 0.2)

SP.nameLabel = makeLabel(spFrame, "Tidak ada target", 76, 40, 152, 18, Enum.Font.GothamBold, 12, C.TEXT)
glowText(SP.nameLabel, 0.5)
SP.status = makeLabel(spFrame, "Idle", 76, 60, 152, 16, Enum.Font.GothamMedium, 11, C.DIM)
SP.info = makeLabel(spFrame, "", 14, 94, 212, 14, Enum.Font.GothamMedium, 10, C.DIM)

SP.prevBtn = makeButton(spFrame, "<", 14, 118, 26, 26)
SP.box = Instance.new("TextBox")
SP.box.Size = UDim2.fromOffset(150, 26)
SP.box.Position = UDim2.fromOffset(44, 118)
SP.box.BackgroundColor3 = C.PANEL
SP.box.BorderSizePixel = 0
SP.box.Font = Enum.Font.GothamMedium
SP.box.TextSize = 12
SP.box.TextColor3 = C.TEXT
SP.box.PlaceholderText = "nama, lalu Enter"
SP.box.PlaceholderColor3 = C.DIM
SP.box.Text = ""
SP.box.ClearTextOnFocus = false
SP.box.Parent = spFrame
makeCorner(SP.box, UDim.new(0, 8))
local boxStroke = makeStroke(SP.box, 1.2, 0.7)
SP.nextBtn = makeButton(spFrame, ">", 200, 118, 26, 26)

SP.pickBtn = makeButton(spFrame, "Klik", 14, 152, 66, 26)
SP.startBtn = makeButton(spFrame, "Start", 87, 152, 66, 26)
SP.stopBtn = makeButton(spFrame, "Stop", 160, 152, 66, 26)

makeLabel(spFrame, "Daftar player", 16, 188, 150, 16, Enum.Font.GothamBold, 11, C.DIM)
SP.list = Instance.new("ScrollingFrame")
SP.list.Size = UDim2.fromOffset(212, 220)
SP.list.Position = UDim2.fromOffset(14, 208)
SP.list.BackgroundTransparency = 1
SP.list.BorderSizePixel = 0
SP.list.ScrollBarThickness = 3
SP.list.ScrollBarImageColor3 = C.ACCENT
SP.list.CanvasSize = UDim2.fromOffset(0, 0)
SP.list.Parent = spFrame

-- ============ ESP ============
local espHi = Instance.new("Highlight")
espHi.FillColor = C.ACCENT
espHi.OutlineColor = C.WHITE
espHi.FillTransparency = 0.6
espHi.OutlineTransparency = 0
espHi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
espHi.Enabled = false
espHi.Parent = gui

local espTag = Instance.new("BillboardGui")
espTag.Size = UDim2.fromOffset(200, 36)
espTag.StudsOffset = Vector3.new(0, 3, 0)
espTag.AlwaysOnTop = true
espTag.Enabled = false
espTag.Parent = gui
local espName = makeLabel(espTag, "", 0, 0, 200, 18, Enum.Font.GothamBlack, 13, C.WHITE, Enum.TextXAlignment.Center)
glowText(espName, 0.2)
makeLabel(espTag, "klik untuk pilih", 0, 18, 200, 14, Enum.Font.GothamMedium, 10, C.ACCENT_LIGHT, Enum.TextXAlignment.Center)

-- ============ CHARACTER & CAMERA ============
local function getHumanoid()
    local char = player.Character
    if char then
        return char:FindFirstChildOfClass("Humanoid")
    end
    return nil
end

local function setFrozen(freeze)
    local hum = getHumanoid()
    if not hum then return end
    if freeze then
        S.savedWalk = hum.WalkSpeed
        S.savedJump = hum.JumpPower
        hum.WalkSpeed = 0
        hum.JumpPower = 0
    elseif S.savedWalk then
        hum.WalkSpeed = S.savedWalk
        hum.JumpPower = S.savedJump
    end
end

local function refreshToggle()
    if S.enabled then
        tween(UI.track, { BackgroundColor3 = C.ACCENT })
        tween(UI.knob, { Position = UDim2.fromOffset(25, 3) })
        UI.statusValue.Text = "ON"
        UI.statusValue.TextColor3 = C.ACCENT_LIGHT
    else
        tween(UI.track, { BackgroundColor3 = C.OFF })
        tween(UI.knob, { Position = UDim2.fromOffset(3, 3) })
        UI.statusValue.Text = "OFF"
        UI.statusValue.TextColor3 = C.DIM
    end
end

local function initRotFromCamera()
    local look = camera.CFrame.LookVector
    S.yaw = math.deg(math.atan2(-look.X, -look.Z))
    S.pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
    S.tYaw = S.yaw
    S.tPitch = S.pitch
end

local function restoreCamera()
    if S.enabled or SP.active then return end
    if S.headLock then
        camera.CameraType = Enum.CameraType.Scriptable
        S.orbitCenter = nil
        initRotFromCamera()
    else
        camera.CameraType = Enum.CameraType.Custom
        local hum = getHumanoid()
        if hum then
            camera.CameraSubject = hum
        end
    end
end

local function anchorActive()
    return S.headLock and not S.enabled and not SP.active
end

local function getAnchorPart()
    local ch = player.Character
    if not ch then return nil end
    return ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
end

local function setEnabled(state)
    if state == S.enabled then return end
    if state and SP.active then
        stopSpectate()
    end
    S.enabled = state
    playSound(state and "on" or "off")

    if state then
        S.savedFov = camera.FieldOfView
        S.curFov = S.savedFov
        S.tFov = S.savedFov
        S.orbitCenter = nil
        camera.CameraType = Enum.CameraType.Scriptable
        S.pos = camera.CFrame.Position
        S.targetPos = S.pos
        initRotFromCamera()
        setFrozen(true)
    else
        S.rotating = false
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        camera.FieldOfView = S.savedFov
        setFrozen(false)
        restoreCamera()
    end
    refreshToggle()
end

local function setHeadLock(on)
    S.headLock = on
    S.orbitCenter = nil
    UI.headBtn.Text = on and "ON" or "OFF"
    UI.headBtn.TextColor3 = on and C.ACCENT_LIGHT or C.DIM
    if on then
        if not S.enabled and not SP.active then
            initRotFromCamera()
            camera.CameraType = Enum.CameraType.Scriptable
        end
    else
        restoreCamera()
    end
    saveSettings()
end

local function setHideUI(on)
    S.hidden = on
    gui.Enabled = not on
    if on then
        setPickMode(false)
    end
    playSound("whoosh")
end

local function updateHint()
    UI.hint.Text = "Scroll = zoom/jarak  |  " .. S.keybind.Name .. " = on/off  |  " .. S.hideKey.Name .. " = hide UI"
end

local function refreshKeyButtons()
    UI.keyBtn.Text = S.keybind.Name
    UI.keyBtn.TextColor3 = C.ACCENT_LIGHT
    tween(UI.keyBtn, { BackgroundColor3 = C.PANEL })
    UI.hideKeyBtn.Text = S.hideKey.Name
    UI.hideKeyBtn.TextColor3 = C.ACCENT_LIGHT
    tween(UI.hideKeyBtn, { BackgroundColor3 = C.PANEL })
    updateHint()
end

local function startListen(which, btn)
    S.listening = which
    btn.Text = "..."
    btn.TextColor3 = C.WHITE
    tween(btn, { BackgroundColor3 = C.ACCENT })
    playSound("click")
end

-- ============ ANIMASI SPECTATE ============
local specToken = 0

showSpec = function()
    specToken = specToken + 1
    refreshList()
    spFrame.Visible = true
    spScale.Scale = 0.5
    spFrame.BackgroundTransparency = 1
    fadeTexts(spFrame, 1, 0)
    tween(spScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    tween(spFrame, { BackgroundTransparency = 0 }, 0.3)
    tween(spG1, { Transparency = 0.2 }, 0.4)
    tween(spG2, { Transparency = 0.55 }, 0.4)
    fadeTexts(spFrame, 0, 0.3)
end

hideSpec = function()
    if not spFrame.Visible then return end
    specToken = specToken + 1
    local my = specToken
    tween(spScale, { Scale = 0.5 }, 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    tween(spFrame, { BackgroundTransparency = 1 }, 0.2)
    tween(spG1, { Transparency = 1 }, 0.15)
    tween(spG2, { Transparency = 1 }, 0.15)
    fadeTexts(spFrame, 1, 0.15)
    task.delay(0.22, function()
        if specToken == my then
            spFrame.Visible = false
        end
    end)
end

-- ============ ANIMASI MINIMIZE / EXPAND (SINEMATIS & MULUS) ============
local BUBBLE_SIZE = UDim2.fromOffset(C.BUBBLE, C.BUBBLE)
local PANEL_SIZE = UDim2.fromOffset(C.PANEL_W, C.PANEL_H)

local function setMinimized(state)
    if S.minimized == state then return end
    S.minimized = state
    animToken = animToken + 1
    local my = animToken
    playSound("whoosh")

    if state then
        hideSpec()
        fadeAll(UI.content, true, 0.15)
        task.delay(0.12, function()
            if animToken ~= my then return end
            UI.content.Visible = false
            UI.kBtn.Visible = true
            UI.bubbleImg.ImageTransparency = 1
            
            -- Efek pegas/elasti halus saat menutup ke bubble
            tween(UI.panel, { Size = UDim2.fromOffset(C.BUBBLE + 8, C.BUBBLE + 8) }, 0.2, Enum.EasingStyle.Quad)
            task.delay(0.2, function()
                if animToken == my then
                    tween(UI.panel, { Size = BUBBLE_SIZE }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
                    tween(UI.corner, { CornerRadius = UDim.new(0.5, 0) }, 0.4, Enum.EasingStyle.Quint)
                end
            end)
            
            task.delay(0.25, function()
                if animToken == my then
                    tween(UI.bubbleImg, { ImageTransparency = 0 }, 0.25)
                end
            end)
        end)
    else
        tween(UI.bubbleImg, { ImageTransparency = 1 }, 0.12)
        task.delay(0.1, function()
            if animToken ~= my then return end
            UI.kBtn.Visible = false
            
            -- Efek pegas membesar yang elegan saat dibuka
            tween(UI.panel, { Size = UDim2.fromOffset(C.PANEL_W + 12, C.PANEL_H + 12) }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            tween(UI.corner, { CornerRadius = UDim.new(0, 18) }, 0.35, Enum.EasingStyle.Quint)
            
            task.delay(0.35, function()
                if animToken ~= my then return end
                -- Mengembalikan ke ukuran pas semula dengan lembut
                tween(UI.panel, { Size = PANEL_SIZE }, 0.2, Enum.EasingStyle.Quint)
                
                UI.content.Visible = true
                fadeAll(UI.content, true, 0)
                fadeAll(UI.content, false, 0.3)
                
                task.delay(0.15, function()
                    if animToken == my and not S.minimized then
                        showSpec()
                    end
                end)
            end)
        end)
    end
end

local function playIntro()
    playSound("intro")
    UI.kBtn.Visible = true
    UI.bubbleImg.ImageTransparency = 1
    UI.content.Visible = false

    tween(UI.panel, { BackgroundTransparency = 0 }, 0.6)

    task.wait(0.9)
    tween(UI.bubbleImg, { ImageTransparency = 0 }, 0.4)
    tween(UI.panel, { Size = UDim2.fromOffset(C.BUBBLE + 10, C.BUBBLE + 10) }, 0.2, Enum.EasingStyle.Back)
    task.wait(0.2)
    tween(UI.panel, { Size = BUBBLE_SIZE }, 0.15)
    task.wait(0.35)

    playSound("whoosh")
    tween(UI.bubbleImg, { ImageTransparency = 1 }, 0.25)
    tween(UI.panel, { Size = PANEL_SIZE }, 0.8, Enum.EasingStyle.Quint)
    tween(UI.corner, { CornerRadius = UDim.new(0, 16) }, 0.8, Enum.EasingStyle.Quint)
    task.wait(0.45)

    UI.kBtn.Visible = false
    UI.content.Visible = true
    fadeTexts(UI.content, 1, 0)
    fadeTexts(UI.content, 0, 0.5)

    tween(UI.glow1, { Transparency = 0.1 }, 0.5)
    tween(UI.glow2, { Transparency = 0.5 }, 0.5)
    tween(UI.glow3, { Transparency = 0.8 }, 0.5)
    showSpec()
    task.wait(0.5)

    TweenService:Create(
        UI.glow3,
        TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Transparency = 0.92 }
    ):Play()
end

-- ============ DRAG ============
local function beginDrag(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
        S.dragging = true
        S.dragMoved = false
        S.dragStart = input.Position
        S.dragPos = UI.panel.Position
    end
end

UI.dragBar.InputBegan:Connect(beginDrag)
UI.kBtn.InputBegan:Connect(beginDrag)
spFrame.InputBegan:Connect(beginDrag)

-- ============ SPECTATE LOGIC ============
local function findPlayerByName(query)
    query = string.lower(query)
    if query == "" then return nil end
    local best, bestScore = nil, 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local n = string.lower(p.Name)
            local d = string.lower(p.DisplayName)
            local score = 0
            if n == query or d == query then
                score = 4
            elseif string.sub(n, 1, #query) == query or string.sub(d, 1, #query) == query then
                score = 3
            elseif string.find(n, query, 1, true) or string.find(d, query, 1, true) then
                score = 2
            end
            if score > bestScore then
                best = p
                bestScore = score
            end
        end
    end
    return best
end

local thumbCache = {}
local function getThumb(p)
    if thumbCache[p.UserId] then
        return thumbCache[p.UserId]
    end
    local ok, img = pcall(function()
        return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    end)
    if ok then
        thumbCache[p.UserId] = img
        return img
    end
    return ""
end

refreshList = function()
    for _, c in ipairs(SP.list:GetChildren()) do
        if c:IsA("GuiObject") then
            c:Destroy()
        end
    end

    local y = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, -8, 0, 36)
            row.Position = UDim2.fromOffset(0, y)
            row.BackgroundColor3 = (p == SP.pending) and C.OFF or C.PANEL
            row.BorderSizePixel = 0
            row.Text = ""
            row.AutoButtonColor = false
            row.Parent = SP.list
            makeCorner(row, UDim.new(0, 8))

            local th = Instance.new("ImageLabel")
            th.Size = UDim2.fromOffset(28, 28)
            th.Position = UDim2.fromOffset(6, 4)
            th.BackgroundColor3 = C.BG
            th.BorderSizePixel = 0
            th.Image = ""
            th.Parent = row
            makeCorner(th, UDim.new(0.5, 0))

            makeLabel(row, p.DisplayName, 42, 4, 150, 16, Enum.Font.GothamBold, 12, C.TEXT)
            makeLabel(row, "@" .. p.Name, 42, 19, 150, 14, Enum.Font.GothamMedium, 10, C.DIM)

            onClick(row, function()
                setPending(p)
            end)

            task.spawn(function()
                th.Image = getThumb(p)
            end)
            y = y + 40
        end
    end
    SP.list.CanvasSize = UDim2.fromOffset(0, y)
end

setPending = function(p)
    SP.pending = p
    if not p then
        SP.nameLabel.Text = "Tidak ada target"
        SP.thumb.Image = ""
        if not SP.active then
            SP.status.Text = "Idle"
        end
    else
        SP.nameLabel.Text = p.DisplayName .. " (@" .. p.Name .. ")"
        SP.thumb.Image = getThumb(p)
        if not SP.active then
            SP.status.Text = "Tekan Start"
        end
    end
    refreshList()
end

applySubject = function()
    if not SP.active or not SP.target then return end
    local ch = SP.target.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if hum then
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = hum
        SP.status.Text = "Spectating"
    else
        SP.status.Text = "Menunggu karakter..."
    end
end

startSpectate = function()
    if not SP.pending then
        SP.status.Text = "Pilih player dulu"
        playSound("off")
        return
    end
    playSound("on")

    if S.enabled then
        setEnabled(false)
    end

    SP.active = true
    SP.target = SP.pending

    if SP.charConn then
        SP.charConn:Disconnect()
    end
    local target = SP.target
    SP.charConn = target.CharacterAdded:Connect(function()
        task.wait(0.3)
        if SP.active and SP.target == target then
            applySubject()
        end
    end)

    applySubject()
    refreshList()
end

stopSpectate = function()
    SP.active = false
    SP.target = nil
    if SP.charConn then
        SP.charConn:Disconnect()
        SP.charConn = nil
    end
    S.orbitCenter = nil
    restoreCamera()
    SP.status.Text = SP.pending and "Tekan Start" or "Idle"
    refreshList()
end

local function cycleTarget(dir)
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            table.insert(list, p)
        end
    end
    if #list == 0 then return end
    local idx = 0
    for i, p in ipairs(list) do
        if p == SP.pending then
            idx = i
        end
    end
    idx = ((idx - 1 + dir) % #list) + 1
    setPending(list[idx])
    if SP.active then
        startSpectate()
    end
end

local function updateInfo()
    local p = SP.pending
    if SP.active and SP.target then
        p = SP.target
    end
    if not p then
        SP.info.Text = ""
        return
    end
    local ch = p.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    local hp = hum and string.format("HP %d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth)) or "HP -"
    local dist = root and string.format("%d studs", math.floor((root.Position - camera.CFrame.Position).Magnitude)) or "- studs"
    local team = p.Team and p.Team.Name or "Tanpa tim"
    SP.info.Text = hp .. "  |  " .. dist .. "  |  " .. team
end

-- ============ MODE KLIK + ESP ============
local function getPlayerUnderMouse()
    local m = UIS:GetMouseLocation()
    local ray = camera:ViewportPointToRay(m.X, m.Y)

    local ignore = {}
    if player.Character then
        table.insert(ignore, player.Character)
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore

    local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    if not hit then return nil end
    local model = hit.Instance:FindFirstAncestorOfClass("Model")
    local p = model and Players:GetPlayerFromCharacter(model)
    if p and p ~= player then
        return p
    end
    return nil
end

local hovered = nil
local function setHover(p)
    if p == hovered then return end
    hovered = p
    if not p or not p.Character then
        espHi.Enabled = false
        espHi.Parent = gui
        espTag.Enabled = false
        espTag.Adornee = nil
        return
    end
    local ch = p.Character
    espHi.Parent = ch
    espHi.Enabled = true
    espName.Text = p.DisplayName .. " (@" .. p.Name .. ")"
    espTag.Adornee = ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
    espTag.Enabled = true
end

setPickMode = function(on)
    SP.pickMode = on
    if on then
        SP.status.Text = "Arahkan ke player..."
    else
        setHover(nil)
        SP.status.Text = SP.active and "Spectating" or (SP.pending and "Tekan Start" or "Idle")
    end
end

-- ============ EVENTS ============
onClick(UI.track, function()
    setEnabled(not S.enabled)
end, false)

onClick(UI.minBtn, function()
    setMinimized(true)
end, false)

onClick(UI.keyBtn, function()
    startListen("main", UI.keyBtn)
end, false)

onClick(UI.hideKeyBtn, function()
    startListen("hide", UI.hideKeyBtn)
end, false)

onClick(UI.headBtn, function()
    setHeadLock(not S.headLock)
end)

SP.box.Focused:Connect(function()
    playSound("click")
    tween(boxStroke, { Transparency = 0.1 }, 0.2)
end)

SP.box.FocusLost:Connect(function(enterPressed)
    tween(boxStroke, { Transparency = 0.7 }, 0.2)
    if not enterPressed then return end
    local p = findPlayerByName(SP.box.Text)
    if p then
        playSound("on")
        setPending(p)
        SP.box.Text = ""
        SP.status.Text = "Dipilih: " .. p.Name
    else
        playSound("off")
        SP.status.Text = "Player tidak ditemukan"
    end
end)

onClick(SP.prevBtn, function()
    cycleTarget(-1)
end)
onClick(SP.nextBtn, function()
    cycleTarget(1)
end)

onClick(SP.pickBtn, function()
    setPickMode(not SP.pickMode)
end)

onClick(SP.startBtn, function()
    startSpectate()
end, false)

onClick(SP.stopBtn, function()
    playSound("off")
    stopSpectate()
end, false)

UIS.InputEnded:Connect(function(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
        if sliderDrag then
            sliderDrag = nil
            saveSettings()
        end
        if S.dragging then
            S.dragging = false
            if not S.dragMoved and S.minimized then
                setMinimized(false)
            end
        end
    elseif t == Enum.UserInputType.MouseButton2 then
        S.rotating = false
        UIS.MouseBehavior = Enum.MouseBehavior.Default
    end
end)

UIS.InputBegan:Connect(function(input, gp)
    if S.listening then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode ~= Enum.KeyCode.Escape then
                if S.listening == "main" then
                    S.keybind = input.KeyCode
                else
                    S.hideKey = input.KeyCode
                end
            end
            S.listening = nil
            refreshKeyButtons()
            playSound("click")
            saveSettings()
        end
        return
    end

    if SP.pickMode and not gp and input.UserInputType == Enum.UserInputType.MouseButton1 then
        local p = getPlayerUnderMouse()
        if p then
            playSound("on")
            setPending(p)
            setPickMode(false)
        else
            playSound("off")
            SP.status.Text = "Bukan karakter player"
        end
        return
    end

    if gp then return end

    if input.KeyCode == S.keybind then
        setEnabled(not S.enabled)
    elseif input.KeyCode == S.hideKey then
        setHideUI(not gui.Enabled and false or not S.hidden)
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 and (S.enabled or anchorActive()) then
        S.rotating = true
        UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    end
end)

UIS.InputChanged:Connect(function(input)
    local t = input.UserInputType

    if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
        if S.dragging then
            local delta = input.Position - S.dragStart
            if delta.Magnitude > 6 then
                S.dragMoved = true
            end
            UI.panel.Position = UDim2.new(
                S.dragPos.X.Scale, S.dragPos.X.Offset + delta.X,
                S.dragPos.Y.Scale, S.dragPos.Y.Offset + delta.Y
            )
        end

        if sliderDrag then
            sliderDrag.fromX(input.Position.X)
        elseif S.rotating and t == Enum.UserInputType.MouseMovement then
            S.tYaw = S.tYaw - input.Delta.X * C.SENS
            S.tPitch = math.clamp(S.tPitch - input.Delta.Y * C.SENS, -89, 89)
        end
    elseif t == Enum.UserInputType.MouseWheel then
        if anchorActive() then
            S.camDist = math.clamp(S.camDist - input.Position.Z * 2, C.CAMDIST_MIN, C.CAMDIST_MAX)
        elseif S.enabled then
            S.tFov = math.clamp(S.tFov - input.Position.Z * C.ZOOM_STEP, C.FOV_MIN, C.FOV_MAX)
        end
    end
end)

-- ============ MAIN LOOP ============
local infoTimer = 0
RunService.RenderStepped:Connect(function(dt)
    infoTimer = infoTimer + dt
    if infoTimer > 0.25 then
        infoTimer = 0
        updateInfo()
    end

    if SP.pickMode then
        setHover(getPlayerUnderMouse())
    end

    local alpha = 1 - math.exp(-S.smooth * dt)
    local anchored = anchorActive()
    if not S.enabled and not anchored then return end

    S.yaw = S.yaw + (S.tYaw - S.yaw) * alpha
    S.pitch = S.pitch + (S.tPitch - S.pitch) * alpha
    local rotCF = CFrame.Angles(0, math.rad(S.yaw), 0) * CFrame.Angles(math.rad(S.pitch), 0, 0)

    if S.enabled then
        S.curFov = S.curFov + (S.tFov - S.curFov) * alpha
        camera.FieldOfView = S.curFov
    end

    if anchored then
        local anchor = getAnchorPart()
        if anchor then
            if not S.orbitCenter then
                S.orbitCenter = anchor.Position
            end
            S.orbitCenter = S.orbitCenter + (anchor.Position - S.orbitCenter) * alpha
            camera.CFrame = CFrame.new(S.orbitCenter - rotCF.LookVector * S.camDist) * rotCF
        end
        return
    end

    local move = Vector3.new(0, 0, 0)
    local forward = rotCF.LookVector
    local right = rotCF.RightVector

    if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + forward end
    if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - forward end
    if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + right end
    if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - right end
    if UIS:IsKeyDown(Enum.KeyCode.E) then move = move + Vector3.new(0, 1, 0) end
    if UIS:IsKeyDown(Enum.KeyCode.Q) then move = move - Vector3.new(0, 1, 0) end

    if move.Magnitude > 0 then
        local speed = C.BASE_SPEED * S.speed
        if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then
            speed = speed * C.FAST_MULT
        end
        S.targetPos = S.targetPos + move.Unit * speed * dt
    end

    S.pos = S.pos + (S.targetPos - S.pos) * alpha
    camera.CFrame = CFrame.new(S.pos) * rotCF
end)

player.CharacterAdded:Connect(function()
    S.orbitCenter = nil
    if S.enabled then
        S.enabled = false
        S.rotating = false
        camera.FieldOfView = S.savedFov
        refreshToggle()
    end
    if S.headLock then
        task.wait(0.3)
        if not S.enabled and not SP.active then
            camera.CameraType = Enum.CameraType.Scriptable
        end
    end
end)

Players.PlayerAdded:Connect(function()
    if spFrame.Visible then
        refreshList()
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if SP.target == p then
        stopSpectate()
    end
    if SP.pending == p then
        setPending(nil)
    end
    if spFrame.Visible then
        task.defer(refreshList)
    end
end)

-- ============ START ============
refreshKeyButtons()
refreshToggle()
UI.headBtn.Text = S.headLock and "ON" or "OFF"
UI.headBtn.TextColor3 = S.headLock and C.ACCENT_LIGHT or C.DIM
if S.headLock then
    initRotFromCamera()
    camera.CameraType = Enum.CameraType.Scriptable
end

task.spawn(function()
    local img = getSelfThumb()
    UI.headImg.Image = img
    UI.bubbleImg.Image = img
end)

task.spawn(playIntro)
