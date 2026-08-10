--[[
    VortexHub MainLoader.luau
    Formato ejecutable listo para utilizarse mediante:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/TuUsuario/VortexHub/main/MainLoader.lua"))()
--]]

if getgenv and getgenv().VortexHubLoaded then
    warn("[VortexHub] El Hub ya está en ejecución.")
    return getgenv().VortexHub
end

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Lighting = game:GetService("Lighting"),
    HttpService = game:GetService("HttpService")
}

local LocalPlayer = Services.Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Entorno Global de VortexHub
local VortexHub = {
    Version = "1.0.0",
    Config = {},
    ActiveTarget = nil,
    TargetLockEnabled = false,
    PredictMovement = true,
    PredictionLead = 0.12,
    Commands = {}
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
-- 2. REGISTRO ESTRUCTURAL DE COMANDOS
--------------------------------------------------------------------------------

-- Comando: Target Lock
VortexHub.Commands["target_lock"] = function(args)
    -- args = { targetPlayer = "Nombre", enabled = true/false, predictionLead = 0.12 }
    if args.enabled ~= nil then
        VortexHub.TargetLockEnabled = args.enabled
    end

    if args.predictionLead then
        VortexHub.PredictionLead = tonumber(args.predictionLead) or 0.12
    end

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

-- Comando: Velocidad de Caminata
VortexHub.Commands["set_walkspeed"] = function(speed)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = tonumber(speed) or 16
    end
end

-- Comando: Modo Noclip
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

-- Comando: Gravedad
VortexHub.Commands["set_gravity"] = function(gravity)
    workspace.Gravity = tonumber(gravity) or 196.2
end

-- Comando: Hora del Día
VortexHub.Commands["time_of_day"] = function(timeStr)
    local times = { ["Mañana"] = "06:00:00", ["Mediodía"] = "12:00:00", ["Noche"] = "00:00:00" }
    Services.Lighting.TimeOfDay = times[timeStr] or timeStr or "12:00:00"
end

--------------------------------------------------------------------------------
-- 3. EJECUTADOR Y API PÚBLICA
--------------------------------------------------------------------------------

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

-- Inicialización
HookMouseAim()

if getgenv then
    getgenv().VortexHubLoaded = true
    getgenv().VortexHub = VortexHub
end

print("[VortexHub] Cargado correctamente.")
return VortexHub
