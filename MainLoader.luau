--[[
    VortexHub MainLoader.luau
    Formato ejecutable listo para utilizarse mediante:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/MainLoader.luau"))()
--]]

if getgenv and getgenv().VortexHubLoaded then
    warn("[VortexHub] El Hub ya está en ejecución.")
    return getgenv().VortexHub
end

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Lighting = game:GetService("Lighting"),
    HttpService = game:GetService("HttpService"),
    TweenService = game:GetService("TweenService"),
    UserInputService = game:GetService("UserInputService"),
    CoreGui = game:GetService("CoreGui")
}

local LocalPlayer = Services.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Mouse = LocalPlayer:GetMouse()

-- Entorno Global de VortexHub
local VortexHub = {
    Version = "1.0.0",
    Config = {},
    ActiveTarget = nil,
    TargetLockEnabled = false,
    PredictMovement = true,
    PredictionLead = 0.12,
    Commands = {},
    
    -- Player Tracker State
    TrackerEnabled = false,
    TrackedPlayer = nil,
    TrackedData = { Distance = 0, Position = Vector3.zero, Health = 100 },
    TrackerBillboard = nil,

    -- Official Logo Asset
    LogoAsset = "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/vortex_logo.png",

    -- UI State
    AccentColor = Color3.fromRGB(138, 43, 226), -- Purple por defecto
    ThemeElements = {},
    Themes = {
        Purple = Color3.fromRGB(138, 43, 226),
        Cyan = Color3.fromRGB(0, 240, 255),
        Crimson = Color3.fromRGB(255, 36, 0),
        Green = Color3.fromRGB(0, 255, 102),
        Amber = Color3.fromRGB(255, 179, 0)
    }
}

--------------------------------------------------------------------------------
-- 1. MÓDULO TARGET LOCK (Sin seguimiento de cámara)
--------------------------------------------------------------------------------
local function GetTargetPosition()
    if not VortexHub.TargetLockEnabled or not VortexHub.ActiveTarget or not VortexHub.ActiveTarget.Character then
        return nil
    end

    local char = VortexHub.ActiveTarget.Character
    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")

    if not root or not humanoid or humanoid.Health <= 0 then
        return nil
    end

    local targetPos = root.Position
    if VortexHub.PredictMovement and root:IsA("BasePart") then
        targetPos = targetPos + (root.AssemblyLinearVelocity * VortexHub.PredictionLead)
    end
    return targetPos
end

local function HookMouseAim()
    local gmt = getrawmetatable(game)
    if setreadonly then setreadonly(gmt, false) end
    local oldIndex = gmt.__index

    gmt.__index = newcclosure(function(selfInstance, key)
        if selfInstance == Mouse and (key == "Hit" or key == "hit") then
            local targetPos = GetTargetPosition()
            if targetPos then
                return CFrame.new(targetPos)
            end
        end
        return oldIndex(selfInstance, key)
    end)

    if setreadonly then setreadonly(gmt, true) end
end

--------------------------------------------------------------------------------
-- 2. MÓDULO PLAYER TRACKER (Rastreo de Distancia, Posición y ESP)
--------------------------------------------------------------------------------
local function ClearTrackerMarker()
    if VortexHub.TrackerBillboard then
        VortexHub.TrackerBillboard:Destroy()
        VortexHub.TrackerBillboard = nil
    end
end

local function CreateTrackerMarker(targetPlayer)
    ClearTrackerMarker()
    if not targetPlayer or not targetPlayer.Character then return end

    local head = targetPlayer.Character:FindFirstChild("Head") or targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not head then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "VortexTrackerTag"
    billboard.Adornee = head
    billboard.Size = UDim2.new(0, 170, 0, 42)
    billboard.StudsOffset = Vector3.new(0, 2.8, 0)
    billboard.AlwaysOnTop = true

    local label = Instance.new("TextLabel")
    label.Name = "TrackerText"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 0.4
    label.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    label.TextColor3 = Color3.fromRGB(0, 240, 255)
    label.TextSize = 13
    label.Font = Enum.Font.GothamBold
    label.RichText = true
    label.Text = targetPlayer.DisplayName
    label.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = VortexHub.AccentColor
    stroke.Parent = label
    table.insert(VortexHub.ThemeElements, stroke)

    billboard.Parent = head
    VortexHub.TrackerBillboard = billboard
end

local function UpdatePlayerTracker()
    if not VortexHub.TrackerEnabled or not VortexHub.TrackedPlayer or not VortexHub.TrackedPlayer.Character then
        ClearTrackerMarker()
        return
    end

    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local targetChar = VortexHub.TrackedPlayer.Character
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not myRoot then return end

    local rawDistance = (targetRoot.Position - myRoot.Position).Magnitude
    local distanceMeters = math.floor(rawDistance * 0.28)
    local targetPos = targetRoot.Position
    local health = targetHumanoid and math.floor((targetHumanoid.Health / targetHumanoid.MaxHealth) * 100) or 0

    VortexHub.TrackedData = {
        Studs = math.floor(rawDistance),
        Meters = distanceMeters,
        Position = targetPos,
        Health = health
    }

    if VortexHub.TrackerBillboard and VortexHub.TrackerBillboard:FindFirstChild("TrackerText") then
        VortexHub.TrackerBillboard.TrackerText.Text = string.format(
            "🎯 <b>%s</b><br/><font color='#00FF66'>%dm (%dsts)</font> | HP: %d%%",
            VortexHub.TrackedPlayer.DisplayName, distanceMeters, math.floor(rawDistance), health
        )
    end
end

Services.RunService.Heartbeat:Connect(function()
    if VortexHub.TrackerEnabled then
        UpdatePlayerTracker()
    end
end)

--------------------------------------------------------------------------------
-- 3. REGISTRO ESTRUCTURAL DE COMANDOS
--------------------------------------------------------------------------------

VortexHub.Commands["target_lock"] = function(args)
    if typeof(args) == "table" then
        if args.enabled ~= nil then VortexHub.TargetLockEnabled = args.enabled end
        if args.predictionLead then VortexHub.PredictionLead = tonumber(args.predictionLead) or 0.12 end
        if args.targetPlayer and args.targetPlayer ~= "" then
            local found = nil
            for _, player in ipairs(Services.Players:GetPlayers()) do
                if player ~= LocalPlayer and (player.Name:lower() == args.targetPlayer:lower() or player.DisplayName:lower() == args.targetPlayer:lower()) then
                    found = player
                    break
                end
            end
            VortexHub.ActiveTarget = found
            if found then
                print("[VortexHub] Objetivo fijado:", found.Name)
            else
                warn("[VortexHub] Jugador no encontrado:", args.targetPlayer)
            end
        else
            VortexHub.ActiveTarget = nil
        end
    end
end

VortexHub.Commands["player_tracker"] = function(args)
    if typeof(args) == "table" then
        if args.enabled ~= nil then VortexHub.TrackerEnabled = args.enabled end
        if args.targetPlayer and args.targetPlayer ~= "" then
            local found = nil
            for _, player in ipairs(Services.Players:GetPlayers()) do
                if player ~= LocalPlayer and (player.Name:lower() == args.targetPlayer:lower() or player.DisplayName:lower() == args.targetPlayer:lower()) then
                    found = player
                    break
                end
            end
            VortexHub.TrackedPlayer = found
            if found and args.enabled ~= false then
                VortexHub.TrackerEnabled = true
                CreateTrackerMarker(found)
                print("[VortexHub] Rastreo activado para:", found.Name)
            end
        else
            VortexHub.TrackedPlayer = nil
            VortexHub.TrackerEnabled = false
            ClearTrackerMarker()
        end
    end
end

VortexHub.Commands["set_walkspeed"] = function(speed)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = tonumber(speed) or 16
    end
end

VortexHub.Commands["toggle_noclip"] = function(enabled)
    _G.VortexNoclip = enabled
    if enabled and not VortexHub.NoclipConnection then
        VortexHub.NoclipConnection = Services.RunService.Stepped:Connect(function()
            if _G.VortexNoclip and LocalPlayer.Character then
                for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
    elseif not enabled and VortexHub.NoclipConnection then
        VortexHub.NoclipConnection:Disconnect()
        VortexHub.NoclipConnection = nil
    end
end

VortexHub.Commands["set_gravity"] = function(gravity)
    workspace.Gravity = tonumber(gravity) or 196.2
end

VortexHub.Commands["time_of_day"] = function(timeStr)
    local times = { ["Mañana"] = "06:00:00", ["Mediodía"] = "12:00:00", ["Noche"] = "00:00:00" }
    Services.Lighting.TimeOfDay = times[timeStr] or timeStr or "12:00:00"
end

function VortexHub:RunCommand(commandId, payload)
    local commandFunc = self.Commands[commandId]
    if commandFunc then
        local success, err = pcall(function()
            commandFunc(payload)
        end)
        if not success then
            warn("[VortexHub] Error al ejecutar comando (" .. tostring(commandId) .. "):", err)
        end
    else
        warn("[VortexHub] Comando no registrado:", commandId)
    end
end

--------------------------------------------------------------------------------
-- 4. INTEGRACIÓN DE LA INTERFAZ VORTEXUI
--------------------------------------------------------------------------------

local VortexUI = require(script.Parent.src.ui.VortexUI or script.Parent.VortexUI)
HookMouseAim()
VortexUI:Build(VortexHub)

if getgenv then
    getgenv().VortexHubLoaded = true
    getgenv().VortexHub = VortexHub
end

print("[VortexHub] Ejecutado exitosamente con UI interactiva en la pestaña Combat.")
return VortexHub
