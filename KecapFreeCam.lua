976964-- ==========================================
-- FREECAM v6 by kecap
-- P = on/off (bisa diganti di GUI)
-- WASD = gerak, E/Q = naik/turun, Shift = cepat
-- Klik kanan tahan = putar kamera
-- Scroll = zoom, slider = atur speed (default 1.0x)
-- ==========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============ SOUND ============
-- id: sumber suara, speed: nada (makin kecil makin dalam), vol: volume
-- Ganti id dengan rbxassetid://ID kalau mau suara sendiri
local SOUNDS = {
    toggleOn  = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.35, vol = 0.45 },
    toggleOff = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 0.75, vol = 0.45 },
    minimize  = { id = "rbxasset://sounds/swoosh.wav",              speed = 0.9,  vol = 0.5 },
    expand    = { id = "rbxasset://sounds/swoosh.wav",              speed = 1.25, vol = 0.5 },
    keybind   = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.6,  vol = 0.35 },
    slider    = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.9,  vol = 0.2 },
    bubble    = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.1,  vol = 0.4 },
    intro     = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 1.0,  vol = 0.4 },
}

-- ============ CONFIG ============
local BASE_SPEED = 40
local FAST_MULT = 3
local SPEED_MIN = 0.1
local SPEED_MAX = 4
local SENSITIVITY = 0.2
local SMOOTHNESS = 10
local ZOOM_STEP = 4
local FOV_MIN = 20
local FOV_MAX = 110

local PANEL_W = 280
local PANEL_H = 236
local BUBBLE = 54

local ACCENT = Color3.fromRGB(139, 92, 246)
local ACCENT_LIGHT = Color3.fromRGB(200, 175, 255)
local BG = Color3.fromRGB(14, 14, 20)
local BG_LIGHT = Color3.fromRGB(26, 22, 40)
local PANEL = Color3.fromRGB(30, 28, 44)
local OFF_COLOR = Color3.fromRGB(58, 58, 72)
local TEXT_DIM = Color3.fromRGB(150, 150, 170)
local WHITE = Color3.fromRGB(255, 255, 255)

local keybind = Enum.KeyCode.P

-- ============ STATE ============
local enabled = false
local listening = false
local minimized = false
local animating = false
local draggingSlider = false
local rotating = false
local bubbleDragging = false
local bubbleMoved = false
local bubbleDragStart = nil
local bubbleStartPos = nil

local pos = Vector3.new(0, 0, 0)
local targetPos = Vector3.new(0, 0, 0)
local yaw, pitch = 0, 0
local targetYaw, targetPitch = 0, 0
local savedCameraType = nil
local savedFov = 70
local currentFov = 70
local targetFov = 70
local savedWalk = nil
local savedJump = nil
local speedMult = 1.0

-- ============ GUI ROOT ============
local gui = Instance.new("ScreenGui")
gui.Name = "KecapFreecam"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true

local okCore = pcall(function()
    gui.Parent = CoreGui
end)
if not okCore or gui.Parent == nil then
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
    if not cfg then
        return
    end
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = cfg.id
        s.Volume = cfg.vol
        s.PlaybackSpeed = cfg.speed
        s.Parent = SoundService
        s:Play()
        s.Ended:Connect(function()
            s:Destroy()
        end)
        task.delay(6, function()
            if s.Parent then
                s:Destroy()
            end
        end)
    end)
end

local function makeStroke(parent, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = ACCENT
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

local function fadeTexts(root, value, t)
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            tween(obj, {TextTransparency = value}, t)
        end
    end
end

-- ============ PANEL (bulat -> kotak) ============
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(BUBBLE, BUBBLE)
panel.Position = UDim2.new(0, 24, 0.5, -BUBBLE / 2)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0.5, 0)
panelCorner.Parent = panel

local panelGrad = Instance.new("UIGradient")
panelGrad.Rotation = 90
panelGrad.Color = ColorSequence.new(BG_LIGHT, BG)
panelGrad.Parent = panel

local glowInner = makeStroke(panel, 1.5, 1)
local glowMid = makeStroke(panel, 4, 1)
local glowOuter = makeStroke(panel, 9, 1)

-- ============ CONTENT (kotak) ============
local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.Visible = false
content.Parent = panel

local title = makeLabel(content, "FREECAM", 16, 14, 180, 22, Enum.Font.GothamBlack, 17, WHITE)
title.TextStrokeColor3 = ACCENT
title.TextStrokeTransparency = 0.4

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(26, 26)
minBtn.Position = UDim2.new(1, -40, 0, 12)
minBtn.BackgroundColor3 = PANEL
minBtn.BorderSizePixel = 0
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 16
minBtn.TextColor3 = ACCENT_LIGHT
minBtn.Text = "-"
minBtn.AutoButtonColor = false
minBtn.ZIndex = 5
minBtn.Parent = content
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 8)
minCorner.Parent = minBtn

-- Freecam toggle
makeLabel(content, "Freecam", 16, 56, 90, 20, Enum.Font.GothamMedium, 13, Color3.fromRGB(225, 225, 235))
local statusValue = makeLabel(content, "OFF", 100, 56, 40, 20, Enum.Font.GothamBold, 13, TEXT_DIM)

local track = Instance.new("TextButton")
track.Size = UDim2.fromOffset(46, 24)
track.Position = UDim2.new(1, -62, 0, 54)
track.BackgroundColor3 = OFF_COLOR
track.BorderSizePixel = 0
track.Text = ""
track.AutoButtonColor = false
track.ZIndex = 5
track.Parent = content
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local knob = Instance.new("Frame")
knob.Size = UDim2.fromOffset(18, 18)
knob.Position = UDim2.fromOffset(3, 3)
knob.BackgroundColor3 = WHITE
knob.BorderSizePixel = 0
knob.Parent = track
local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(1, 0)
knobCorner.Parent = knob

-- Keybind
makeLabel(content, "Keybind", 16, 94, 120, 20, Enum.Font.GothamMedium, 13, Color3.fromRGB(225, 225, 235))

local keyBtn = Instance.new("TextButton")
keyBtn.Size = UDim2.fromOffset(78, 26)
keyBtn.Position = UDim2.new(1, -94, 0, 92)
keyBtn.BackgroundColor3 = PANEL
keyBtn.BorderSizePixel = 0
keyBtn.Font = Enum.Font.GothamBold
keyBtn.TextSize = 12
keyBtn.TextColor3 = ACCENT_LIGHT
keyBtn.Text = keybind.Name
keyBtn.AutoButtonColor = false
keyBtn.ZIndex = 5
keyBtn.Parent = content
local keyCorner = Instance.new("UICorner")
keyCorner.CornerRadius = UDim.new(0, 8)
keyCorner.Parent = keyBtn
local keyStroke = Instance.new("UIStroke")
keyStroke.Color = ACCENT
keyStroke.Thickness = 1
keyStroke.Transparency = 0.5
keyStroke.Parent = keyBtn

-- Speed slider
makeLabel(content, "Speed", 16, 130, 120, 20, Enum.Font.GothamMedium, 13, Color3.fromRGB(225, 225, 235))
local speedValue = makeLabel(content, "1.0x", PANEL_W - 76, 130, 60, 20, Enum.Font.GothamBold, 13, ACCENT_LIGHT, Enum.TextXAlignment.Right)

local sliderTrack = Instance.new("Frame")
sliderTrack.Size = UDim2.new(1, -32, 0, 6)
sliderTrack.Position = UDim2.fromOffset(16, 162)
sliderTrack.BackgroundColor3 = OFF_COLOR
sliderTrack.BorderSizePixel = 0
sliderTrack.Parent = content
local trackRound = Instance.new("UICorner")
trackRound.CornerRadius = UDim.new(1, 0)
trackRound.Parent = sliderTrack

local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.new(0, 0, 1, 0)
sliderFill.BackgroundColor3 = ACCENT
sliderFill.BorderSizePixel = 0
sliderFill.Parent = sliderTrack
local fillRound = Instance.new("UICorner")
fillRound.CornerRadius = UDim.new(1, 0)
fillRound.Parent = sliderFill

local sliderKnob = Instance.new("Frame")
sliderKnob.Size = UDim2.fromOffset(14, 14)
sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sliderKnob.Position = UDim2.new(0, 0, 0.5, 0)
sliderKnob.BackgroundColor3 = WHITE
sliderKnob.BorderSizePixel = 0
sliderKnob.Parent = sliderTrack
local knobRound2 = Instance.new("UICorner")
knobRound2.CornerRadius = UDim.new(1, 0)
knobRound2.Parent = sliderKnob

local sliderHit = Instance.new("TextButton")
sliderHit.Size = UDim2.new(1, 0, 0, 24)
sliderHit.Position = UDim2.new(0, 0, 0.5, -12)
sliderHit.BackgroundTransparency = 1
sliderHit.Text = ""
sliderHit.AutoButtonColor = false
sliderHit.ZIndex = 5
sliderHit.Parent = sliderTrack

-- Footer
makeLabel(content, "Scroll = zoom  |  P = on/off", 16, 186, PANEL_W - 32, 14, Enum.Font.Gotham, 10, TEXT_DIM)
local footer = makeLabel(content, "by kecap", 16, PANEL_H - 26, 120, 16, Enum.Font.GothamMedium, 11, TEXT_DIM)
footer.TextStrokeColor3 = ACCENT
footer.TextStrokeTransparency = 0.6

-- ============ BUBBLE (minimize) ============
local kBtn = Instance.new("TextButton")
kBtn.Size = UDim2.new(1, 0, 1, 0)
kBtn.BackgroundTransparency = 1
kBtn.Text = "K"
kBtn.Font = Enum.Font.GothamBlack
kBtn.TextSize = 30
kBtn.TextColor3 = WHITE
kBtn.TextStrokeColor3 = ACCENT
kBtn.TextStrokeTransparency = 0.2
kBtn.AutoButtonColor = false
kBtn.Visible = false
kBtn.Parent = panel
local kGrad = Instance.new("UIGradient")
kGrad.Color = ColorSequence.new(WHITE, ACCENT_LIGHT)
kGrad.Rotation = 90
kGrad.Parent = kBtn

-- ============ SPEED ============
local function setSpeedUI(v)
    speedMult = v
    local ratio = (v - SPEED_MIN) / (SPEED_MAX - SPEED_MIN)
    sliderFill.Size = UDim2.new(ratio, 0, 1, 0)
    sliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
    speedValue.Text = string.format("%.1fx", v)
end

local function setSpeedFromX(x)
    local rel = (x - sliderTrack.AbsolutePosition.X) / sliderTrack.AbsoluteSize.X
    rel = math.clamp(rel, 0, 1)
    local v = SPEED_MIN + rel * (SPEED_MAX - SPEED_MIN)
    v = math.floor(v * 10 + 0.5) / 10
    setSpeedUI(v)
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
    if not hum then
        return
    end
    if freeze then
        savedWalk = hum.WalkSpeed
        savedJump = hum.JumpPower
        hum.WalkSpeed = 0
        hum.JumpPower = 0
    elseif savedWalk then
        hum.WalkSpeed = savedWalk
        hum.JumpPower = savedJump
    end
end

local function refreshToggle()
    if enabled then
        tween(track, {BackgroundColor3 = ACCENT})
        tween(knob, {Position = UDim2.fromOffset(25, 3)})
        statusValue.Text = "ON"
        statusValue.TextColor3 = ACCENT_LIGHT
    else
        tween(track, {BackgroundColor3 = OFF_COLOR})
        tween(knob, {Position = UDim2.fromOffset(3, 3)})
        statusValue.Text = "OFF"
        statusValue.TextColor3 = TEXT_DIM
    end
end

local function setEnabled(state)
    if state == enabled then
        return
    end
    enabled = state
    playSound(enabled and "toggleOn" or "toggleOff")

    if enabled then
        savedCameraType = camera.CameraType
        savedFov = camera.FieldOfView
        currentFov = savedFov
        targetFov = savedFov
        camera.CameraType = Enum.CameraType.Scriptable

        local look = camera.CFrame.LookVector
        pos = camera.CFrame.Position
        targetPos = pos
        yaw = math.deg(math.atan2(-look.X, -look.Z))
        pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        targetYaw = yaw
        targetPitch = pitch

        setFrozen(true)
    else
        rotating = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        camera.FieldOfView = savedFov
        camera.CameraType = savedCameraType or Enum.CameraType.Custom
        local hum = getHumanoid()
        if hum then
            camera.CameraSubject = hum
        end
        setFrozen(false)
    end

    refreshToggle()
end

-- ============ ANIMASI ============
-- Catatan: suara dimainkan di pemanggil (tombol), bukan di sini,
-- jadi tombol tetap bunyi walaupun animasi sedang jalan.
local function setMinimized(state)
    if animating or minimized == state then
        return
    end
    minimized = state
    animating = true
    panel.Active = true

    if minimized then
        content.Visible = false
        kBtn.Visible = true
        kBtn.TextTransparency = 1
        tween(panel, {Size = UDim2.fromOffset(BUBBLE, BUBBLE)}, 0.6, Enum.EasingStyle.Quint)
        tween(panelCorner, {CornerRadius = UDim.new(0.5, 0)}, 0.6, Enum.EasingStyle.Quint)
        tween(kBtn, {TextTransparency = 0}, 0.5)
    else
        kBtn.Visible = false
        content.Visible = true
        tween(panel, {Size = UDim2.fromOffset(PANEL_W, PANEL_H)}, 0.6, Enum.EasingStyle.Quint)
        tween(panelCorner, {CornerRadius = UDim.new(0, 16)}, 0.6, Enum.EasingStyle.Quint)
        fadeTexts(content, 1, 0)
        fadeTexts(content, 0, 0.4)
    end

    task.delay(0.6, function()
        animating = false
    end)
end

local function playIntro()
    animating = true
    kBtn.Visible = true
    kBtn.TextTransparency = 1
    content.Visible = false

    tween(panel, {BackgroundTransparency = 0}, 0.6)

    task.wait(0.9)
    playSound("intro")
    tween(kBtn, {TextTransparency = 0}, 0.4)
    tween(panel, {Size = UDim2.fromOffset(BUBBLE + 10, BUBBLE + 10)}, 0.2, Enum.EasingStyle.Back)
    task.wait(0.2)
    tween(panel, {Size = UDim2.fromOffset(BUBBLE, BUBBLE)}, 0.15)
    task.wait(0.35)

    playSound("expand")
    tween(kBtn, {TextTransparency = 1}, 0.25)
    tween(panel, {Size = UDim2.fromOffset(PANEL_W, PANEL_H)}, 0.9, Enum.EasingStyle.Quint)
    tween(panelCorner, {CornerRadius = UDim.new(0, 16)}, 0.9, Enum.EasingStyle.Quint)
    task.wait(0.5)

    kBtn.Visible = false
    content.Visible = true
    fadeTexts(content, 1, 0)
    fadeTexts(content, 0, 0.6)

    tween(glowInner, {Transparency = 0.1}, 0.6)
    tween(glowMid, {Transparency = 0.5}, 0.6)
    tween(glowOuter, {Transparency = 0.8}, 0.6)
    task.wait(0.6)

    TweenService:Create(
        glowOuter,
        TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Transparency = 0.92}
    ):Play()

    animating = false
end

-- ============ EVENTS ============
track.Activated:Connect(function()
    setEnabled(not enabled)
end)

minBtn.Activated:Connect(function()
    playSound("minimize")
    setMinimized(true)
end)

keyBtn.Activated:Connect(function()
    playSound("keybind")
    listening = true
    keyBtn.Text = "..."
    keyBtn.TextColor3 = WHITE
    tween(keyBtn, {BackgroundColor3 = ACCENT})
end)

-- Bulatan K: bisa di-drag. Kalau cuma diklik (geser < 6px) panel terbuka.
kBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        bubbleDragging = true
        bubbleMoved = false
        bubbleDragStart = input.Position
        bubbleStartPos = panel.Position
    end
end)

sliderHit.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingSlider = true
        playSound("slider")
        setSpeedFromX(input.Position.X)
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if listening then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode ~= Enum.KeyCode.Escape then
                keybind = input.KeyCode
            end
            playSound("keybind")
            listening = false
            keyBtn.Text = keybind.Name
            keyBtn.TextColor3 = ACCENT_LIGHT
            tween(keyBtn, {BackgroundColor3 = PANEL})
        end
        return
    end

    if gp then
        return
    end

    if input.KeyCode == keybind then
        setEnabled(not enabled)
    elseif enabled and input.UserInputType == Enum.UserInputType.MouseButton2 then
        rotating = true
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingSlider = false
        if bubbleDragging then
            bubbleDragging = false
            if not bubbleMoved and minimized then
                playSound("expand")
                setMinimized(false)
            end
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        rotating = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end)

UserInputService.InputChanged:Connect(function(input)
    local t = input.UserInputType

    if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
        if bubbleDragging and minimized then
            local delta = input.Position - bubbleDragStart
            if delta.Magnitude > 6 then
                bubbleMoved = true
            end
            panel.Position = UDim2.new(
                bubbleStartPos.X.Scale,
                bubbleStartPos.X.Offset + delta.X,
                bubbleStartPos.Y.Scale,
                bubbleStartPos.Y.Offset + delta.Y
            )
        end

        if draggingSlider then
            setSpeedFromX(input.Position.X)
        elseif enabled and rotating and t == Enum.UserInputType.MouseMovement then
            targetYaw = targetYaw - input.Delta.X * SENSITIVITY
            targetPitch = math.clamp(targetPitch - input.Delta.Y * SENSITIVITY, -89, 89)
        end
    elseif t == Enum.UserInputType.MouseWheel and enabled then
        targetFov = math.clamp(targetFov - input.Position.Z * ZOOM_STEP, FOV_MIN, FOV_MAX)
    end
end)

RunService.RenderStepped:Connect(function(dt)
    if not enabled then
        return
    end

    local alpha = 1 - math.exp(-SMOOTHNESS * dt)
    yaw = yaw + (targetYaw - yaw) * alpha
    pitch = pitch + (targetPitch - pitch) * alpha
    currentFov = currentFov + (targetFov - currentFov) * alpha
    camera.FieldOfView = currentFov

    local rotCF = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)

    local move = Vector3.new(0, 0, 0)
    local forward = rotCF.LookVector
    local right = rotCF.RightVector

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        move = move + forward
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        move = move - forward
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        move = move + right
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        move = move - right
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.E) then
        move = move + Vector3.new(0, 1, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
        move = move - Vector3.new(0, 1, 0)
    end

    if move.Magnitude > 0 then
        local speed = BASE_SPEED * speedMult
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            speed = speed * FAST_MULT
        end
        targetPos = targetPos + move.Unit * speed * dt
    end

    pos = pos + (targetPos - pos) * alpha
    camera.CFrame = CFrame.new(pos) * rotCF
end)

player.CharacterAdded:Connect(function()
    if enabled then
        enabled = false
        rotating = false
        refreshToggle()
    end
end)

-- ============ START ============
task.spawn(playIntro)
