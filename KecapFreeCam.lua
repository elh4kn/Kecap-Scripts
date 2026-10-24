
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============ CONFIG ============
local SOUNDS = {
    toggleOn  = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.35, vol = 0.45 },
    toggleOff = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 0.75, vol = 0.45 },
    minimize  = { id = "rbxasset://sounds/swoosh.wav", speed = 0.9, vol = 0.5 },
    expand    = { id = "rbxasset://sounds/swoosh.wav", speed = 1.25, vol = 0.5 },
    keybind   = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.6, vol = 0.35 },
    slider    = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.9, vol = 0.2 },
    intro     = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.0, vol = 0.4 },
}

local C = {
    BASE_SPEED = 40, FAST_MULT = 3,
    SPEED_MIN = 0.1, SPEED_MAX = 4,
    SENS = 0.2, SMOOTH = 10,
    ZOOM_STEP = 4, FOV_MIN = 20, FOV_MAX = 110,
    PANEL_W = 280, PANEL_H = 236, BUBBLE = 54,
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
    enabled = false, listening = false, minimized = false, animating = false,
    draggingSlider = false, rotating = false,
    bubbleDragging = false, bubbleMoved = false, dragStart = nil, dragPos = nil,
    pos = Vector3.new(0, 0, 0), targetPos = Vector3.new(0, 0, 0),
    yaw = 0, pitch = 0, tYaw = 0, tPitch = 0,
    savedCam = nil, savedFov = 70, curFov = 70, tFov = 70,
    savedWalk = nil, savedJump = nil,
    speed = 1.0, keybind = Enum.KeyCode.P,
}

local UI = {}

-- ============ GUI ROOT ============
local gui = Instance.new("ScreenGui")
gui.Name = "KecapFreecam"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true
if not pcall(function() gui.Parent = CoreGui end) or gui.Parent == nil then
    gui.Parent = player:WaitForChild("PlayerGui")
end

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

local function makeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius
    c.Parent = parent
    return c
end

local function fadeTexts(root, value, t)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            tween(obj, { TextTransparency = value }, t)
        end
    end
end

-- ============ PANEL ============
UI.panel = Instance.new("Frame")
UI.panel.Size = UDim2.fromOffset(C.BUBBLE, C.BUBBLE)
UI.panel.Position = UDim2.new(0, 24, 0.5, -C.BUBBLE / 2)
UI.panel.BackgroundColor3 = C.BG
UI.panel.BackgroundTransparency = 1
UI.panel.BorderSizePixel = 0
UI.panel.Active = true
UI.panel.Parent = gui

UI.corner = makeCorner(UI.panel, UDim.new(0.5, 0))

UI.grad = Instance.new("UIGradient")
UI.grad.Rotation = 90
UI.grad.Color = ColorSequence.new(C.BG_LIGHT, C.BG)
UI.grad.Parent = UI.panel

UI.glow1 = makeStroke(UI.panel, 1.5, 1)
UI.glow2 = makeStroke(UI.panel, 4, 1)
UI.glow3 = makeStroke(UI.panel, 9, 1)

-- ============ CONTENT ============
UI.content = Instance.new("Frame")
UI.content.Size = UDim2.new(1, 0, 1, 0)
UI.content.BackgroundTransparency = 1
UI.content.Visible = false
UI.content.Parent = UI.panel

UI.title = makeLabel(UI.content, "FREECAM", 16, 14, 180, 22, Enum.Font.GothamBlack, 17, C.WHITE)
UI.title.TextStrokeColor3 = C.ACCENT
UI.title.TextStrokeTransparency = 0.4

UI.minBtn = Instance.new("TextButton")
UI.minBtn.Size = UDim2.fromOffset(26, 26)
UI.minBtn.Position = UDim2.new(1, -40, 0, 12)
UI.minBtn.BackgroundColor3 = C.PANEL
UI.minBtn.BorderSizePixel = 0
UI.minBtn.Font = Enum.Font.GothamBold
UI.minBtn.TextSize = 16
UI.minBtn.TextColor3 = C.ACCENT_LIGHT
UI.minBtn.Text = "-"
UI.minBtn.AutoButtonColor = false
UI.minBtn.ZIndex = 5
UI.minBtn.Parent = UI.content
makeCorner(UI.minBtn, UDim.new(0, 8))

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

UI.knob = Instance.new("Frame")
UI.knob.Size = UDim2.fromOffset(18, 18)
UI.knob.Position = UDim2.fromOffset(3, 3)
UI.knob.BackgroundColor3 = C.WHITE
UI.knob.BorderSizePixel = 0
UI.knob.Parent = UI.track
makeCorner(UI.knob, UDim.new(1, 0))

-- Keybind
makeLabel(UI.content, "Keybind", 16, 94, 120, 20, Enum.Font.GothamMedium, 13, C.TEXT)

UI.keyBtn = Instance.new("TextButton")
UI.keyBtn.Size = UDim2.fromOffset(78, 26)
UI.keyBtn.Position = UDim2.new(1, -94, 0, 92)
UI.keyBtn.BackgroundColor3 = C.PANEL
UI.keyBtn.BorderSizePixel = 0
UI.keyBtn.Font = Enum.Font.GothamBold
UI.keyBtn.TextSize = 12
UI.keyBtn.TextColor3 = C.ACCENT_LIGHT
UI.keyBtn.Text = S.keybind.Name
UI.keyBtn.AutoButtonColor = false
UI.keyBtn.ZIndex = 5
UI.keyBtn.Parent = UI.content
makeCorner(UI.keyBtn, UDim.new(0, 8))
local keyStroke = makeStroke(UI.keyBtn, 1, 0.5)

-- Speed slider
makeLabel(UI.content, "Speed", 16, 130, 120, 20, Enum.Font.GothamMedium, 13, C.TEXT)
UI.speedValue = makeLabel(UI.content, "1.0x", C.PANEL_W - 76, 130, 60, 20, Enum.Font.GothamBold, 13, C.ACCENT_LIGHT, Enum.TextXAlignment.Right)

UI.sliderTrack = Instance.new("Frame")
UI.sliderTrack.Size = UDim2.new(1, -32, 0, 6)
UI.sliderTrack.Position = UDim2.fromOffset(16, 162)
UI.sliderTrack.BackgroundColor3 = C.OFF
UI.sliderTrack.BorderSizePixel = 0
UI.sliderTrack.Parent = UI.content
makeCorner(UI.sliderTrack, UDim.new(1, 0))

UI.sliderFill = Instance.new("Frame")
UI.sliderFill.Size = UDim2.new(0, 0, 1, 0)
UI.sliderFill.BackgroundColor3 = C.ACCENT
UI.sliderFill.BorderSizePixel = 0
UI.sliderFill.Parent = UI.sliderTrack
makeCorner(UI.sliderFill, UDim.new(1, 0))

UI.sliderKnob = Instance.new("Frame")
UI.sliderKnob.Size = UDim2.fromOffset(14, 14)
UI.sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
UI.sliderKnob.Position = UDim2.new(0, 0, 0.5, 0)
UI.sliderKnob.BackgroundColor3 = C.WHITE
UI.sliderKnob.BorderSizePixel = 0
UI.sliderKnob.Parent = UI.sliderTrack
makeCorner(UI.sliderKnob, UDim.new(1, 0))

UI.sliderHit = Instance.new("TextButton")
UI.sliderHit.Size = UDim2.new(1, 0, 0, 24)
UI.sliderHit.Position = UDim2.new(0, 0, 0.5, -12)
UI.sliderHit.BackgroundTransparency = 1
UI.sliderHit.Text = ""
UI.sliderHit.AutoButtonColor = false
UI.sliderHit.ZIndex = 5
UI.sliderHit.Parent = UI.sliderTrack

-- Footer
makeLabel(UI.content, "Scroll = zoom  |  " .. S.keybind.Name .. " = on/off", 16, 186, C.PANEL_W - 32, 14, Enum.Font.Gotham, 10, C.DIM)
UI.footer = makeLabel(UI.content, "by kecap", 16, C.PANEL_H - 26, 120, 16, Enum.Font.GothamMedium, 11, C.DIM)
UI.footer.TextStrokeColor3 = C.ACCENT
UI.footer.TextStrokeTransparency = 0.6

-- ============ BUBBLE (K) ============
UI.kBtn = Instance.new("TextButton")
UI.kBtn.Size = UDim2.new(1, 0, 1, 0)
UI.kBtn.BackgroundTransparency = 1
UI.kBtn.Text = "K"
UI.kBtn.Font = Enum.Font.GothamBlack
UI.kBtn.TextSize = 30
UI.kBtn.TextColor3 = C.WHITE
UI.kBtn.TextStrokeColor3 = C.ACCENT
UI.kBtn.TextStrokeTransparency = 0.2
UI.kBtn.AutoButtonColor = false
UI.kBtn.Visible = false
UI.kBtn.Parent = UI.panel
local kGrad = Instance.new("UIGradient")
kGrad.Color = ColorSequence.new(C.WHITE, C.ACCENT_LIGHT)
kGrad.Rotation = 90
kGrad.Parent = UI.kBtn

-- ============ SPEED ============
local function setSpeedUI(v)
    S.speed = v
    local ratio = (v - C.SPEED_MIN) / (C.SPEED_MAX - C.SPEED_MIN)
    UI.sliderFill.Size = UDim2.new(ratio, 0, 1, 0)
    UI.sliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
    UI.speedValue.Text = string.format("%.1fx", v)
end

local function setSpeedFromX(x)
    local rel = math.clamp((x - UI.sliderTrack.AbsolutePosition.X) / UI.sliderTrack.AbsoluteSize.X, 0, 1)
    local v = C.SPEED_MIN + rel * (C.SPEED_MAX - C.SPEED_MIN)
    setSpeedUI(math.floor(v * 10 + 0.5) / 10)
end

setSpeedUI(1.0)

-- ============ FREECAM ============
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

local function setEnabled(state)
    if state == S.enabled then return end
    S.enabled = state
    playSound(S.enabled and "toggleOn" or "toggleOff")

    if S.enabled then
        S.savedCam = camera.CameraType
        S.savedFov = camera.FieldOfView
        S.curFov = S.savedFov
        S.tFov = S.savedFov
        camera.CameraType = Enum.CameraType.Scriptable

        local look = camera.CFrame.LookVector
        S.pos = camera.CFrame.Position
        S.targetPos = S.pos
        S.yaw = math.deg(math.atan2(-look.X, -look.Z))
        S.pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        S.tYaw = S.yaw
        S.tPitch = S.pitch

        setFrozen(true)
    else
        S.rotating = false
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        camera.FieldOfView = S.savedFov
        camera.CameraType = S.savedCam or Enum.CameraType.Custom
        local hum = getHumanoid()
        if hum then
            camera.CameraSubject = hum
        end
        setFrozen(false)
    end

    refreshToggle()
end

-- ============ ANIMASI ============
local function setMinimized(state)
    if S.animating or S.minimized == state then return end
    S.minimized = state
    S.animating = true

    if state then
        UI.content.Visible = false
        UI.kBtn.Visible = true
        UI.kBtn.TextTransparency = 1
        tween(UI.panel, { Size = UDim2.fromOffset(C.BUBBLE, C.BUBBLE) }, 0.6, Enum.EasingStyle.Quint)
        tween(UI.corner, { CornerRadius = UDim.new(0.5, 0) }, 0.6, Enum.EasingStyle.Quint)
        tween(UI.kBtn, { TextTransparency = 0 }, 0.5)
    else
        UI.kBtn.Visible = false
        UI.content.Visible = true
        tween(UI.panel, { Size = UDim2.fromOffset(C.PANEL_W, C.PANEL_H) }, 0.6, Enum.EasingStyle.Quint)
        tween(UI.corner, { CornerRadius = UDim.new(0, 16) }, 0.6, Enum.EasingStyle.Quint)
        fadeTexts(UI.content, 1, 0)
        fadeTexts(UI.content, 0, 0.4)
    end

    task.delay(0.6, function()
        S.animating = false
    end)
end

local function playIntro()
    S.animating = true
    UI.kBtn.Visible = true
    UI.kBtn.TextTransparency = 1
    UI.content.Visible = false

    tween(UI.panel, { BackgroundTransparency = 0 }, 0.6)

    task.wait(0.9)
    playSound("intro")
    tween(UI.kBtn, { TextTransparency = 0 }, 0.4)
    tween(UI.panel, { Size = UDim2.fromOffset(C.BUBBLE + 10, C.BUBBLE + 10) }, 0.2, Enum.EasingStyle.Back)
    task.wait(0.2)
    tween(UI.panel, { Size = UDim2.fromOffset(C.BUBBLE, C.BUBBLE) }, 0.15)
    task.wait(0.35)

    playSound("expand")
    tween(UI.kBtn, { TextTransparency = 1 }, 0.25)
    tween(UI.panel, { Size = UDim2.fromOffset(C.PANEL_W, C.PANEL_H) }, 0.9, Enum.EasingStyle.Quint)
    tween(UI.corner, { CornerRadius = UDim.new(0, 16) }, 0.9, Enum.EasingStyle.Quint)
    task.wait(0.5)

    UI.kBtn.Visible = false
    UI.content.Visible = true
    fadeTexts(UI.content, 1, 0)
    fadeTexts(UI.content, 0, 0.6)

    tween(UI.glow1, { Transparency = 0.1 }, 0.6)
    tween(UI.glow2, { Transparency = 0.5 }, 0.6)
    tween(UI.glow3, { Transparency = 0.8 }, 0.6)
    task.wait(0.6)

    TweenService:Create(
        UI.glow3,
        TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Transparency = 0.92 }
    ):Play()

    S.animating = false
end

-- ============ EVENTS ============
UI.track.Activated:Connect(function()
    setEnabled(not S.enabled)
end)

UI.minBtn.Activated:Connect(function()
    playSound("minimize")
    setMinimized(true)
end)

UI.keyBtn.Activated:Connect(function()
    playSound("keybind")
    S.listening = true
    UI.keyBtn.Text = "..."
    UI.keyBtn.TextColor3 = C.WHITE
    tween(UI.keyBtn, { BackgroundColor3 = C.ACCENT })
end)

-- Bulatan K bisa digeser. Kalau cuma diklik (geser < 6px) panel terbuka.
UI.kBtn.InputBegan:Connect(function(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
        S.bubbleDragging = true
        S.bubbleMoved = false
        S.dragStart = input.Position
        S.dragPos = UI.panel.Position
    end
end)

UI.sliderHit.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        S.draggingSlider = true
        playSound("slider")
        setSpeedFromX(input.Position.X)
    end
end)

UIS.InputBegan:Connect(function(input, gp)
    if S.listening then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode ~= Enum.KeyCode.Escape then
                S.keybind = input.KeyCode
            end
            playSound("keybind")
            S.listening = false
            UI.keyBtn.Text = S.keybind.Name
            UI.keyBtn.TextColor3 = C.ACCENT_LIGHT
            tween(UI.keyBtn, { BackgroundColor3 = C.PANEL })
        end
        return
    end

    if gp then return end

    if input.KeyCode == S.keybind then
        setEnabled(not S.enabled)
    elseif S.enabled and input.UserInputType == Enum.UserInputType.MouseButton2 then
        S.rotating = true
        UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    end
end)

UIS.InputEnded:Connect(function(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
        S.draggingSlider = false
        if S.bubbleDragging then
            S.bubbleDragging = false
            if not S.bubbleMoved and S.minimized then
                playSound("expand")
                setMinimized(false)
            end
        end
    elseif t == Enum.UserInputType.MouseButton2 then
        S.rotating = false
        UIS.MouseBehavior = Enum.MouseBehavior.Default
    end
end)

UIS.InputChanged:Connect(function(input)
    local t = input.UserInputType

    if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
        if S.bubbleDragging and S.minimized then
            local delta = input.Position - S.dragStart
            if delta.Magnitude > 6 then
                S.bubbleMoved = true
            end
            UI.panel.Position = UDim2.new(
                S.dragPos.X.Scale, S.dragPos.X.Offset + delta.X,
                S.dragPos.Y.Scale, S.dragPos.Y.Offset + delta.Y
            )
        end

        if S.draggingSlider then
            setSpeedFromX(input.Position.X)
        elseif S.enabled and S.rotating and t == Enum.UserInputType.MouseMovement then
            S.tYaw = S.tYaw - input.Delta.X * C.SENS
            S.tPitch = math.clamp(S.tPitch - input.Delta.Y * C.SENS, -89, 89)
        end
    elseif t == Enum.UserInputType.MouseWheel and S.enabled then
        S.tFov = math.clamp(S.tFov - input.Position.Z * C.ZOOM_STEP, C.FOV_MIN, C.FOV_MAX)
    end
end)

RunService.RenderStepped:Connect(function(dt)
    if not S.enabled then return end

    local alpha = 1 - math.exp(-C.SMOOTH * dt)
    S.yaw = S.yaw + (S.tYaw - S.yaw) * alpha
    S.pitch = S.pitch + (S.tPitch - S.pitch) * alpha
    S.curFov = S.curFov + (S.tFov - S.curFov) * alpha
    camera.FieldOfView = S.curFov

    local rotCF = CFrame.Angles(0, math.rad(S.yaw), 0) * CFrame.Angles(math.rad(S.pitch), 0, 0)

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
    if S.enabled then
        S.enabled = false
        S.rotating = false
        refreshToggle()
    end
end)

-- ============ START ============
task.spawn(playIntro)
