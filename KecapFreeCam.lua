-- ==========================================
-- FREECAM v7 by kecap
-- P = on/off (bisa diganti di GUI)
-- WASD = gerak, E/Q = naik/turun, Shift = cepat
-- Klik kanan tahan = putar kamera
-- Scroll = zoom, slider = atur speed (default 1.0x)
-- ==========================================

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
if not
