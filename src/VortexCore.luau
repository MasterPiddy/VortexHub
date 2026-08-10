--[[
    VortexCore.luau - Controlador Principal de VortexHub
    Gestiona el JSON Config, los módulos de comandos y el despacho de acciones.
--]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local TargetLock = require(script.Parent.modules.TargetLock)

local VortexCore = {
    Config = {},
    Modules = {
        TargetLock = TargetLock
    }
}

-- Cargar y validar configuración JSON
function VortexCore:Init(jsonString)
    local success, parsed = pcall(function()
        return HttpService:JSONDecode(jsonString)
    end)

    if success then
        self.Config = parsed
        -- Inicializar hooks necesarios
        TargetLock:HookMouse()
        print("[VortexHub] Core inicializado exitosamente.")
        return true
    end

    warn("[VortexHub] Error al decodificar vortex_commands.json:", parsed)
    return false
end

-- Despachador universal de comandos
function VortexCore:ExecuteCommand(commandId, payload)
    local localPlayer = Players.LocalPlayer
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")

    if commandId == "target_lock" then
        if payload.enabled ~= nil then
            TargetLock.Enabled = payload.enabled
        end
        if payload.targetPlayer then
            TargetLock:SetTarget(payload.targetPlayer)
        end
        if payload.predictionLead then
            TargetLock.PredictionLead = payload.predictionLead
        end

    elseif commandId == "set_walkspeed" and humanoid then
        humanoid.WalkSpeed = tonumber(payload) or 16

    elseif commandId == "toggle_noclip" then
        _G.VortexNoclip = payload

    elseif commandId == "set_gravity" then
        workspace.Gravity = tonumber(payload) or 196.2

    elseif commandId == "time_of_day" then
        local times = { ["Mañana"] = "06:00:00", ["Mediodía"] = "12:00:00", ["Noche"] = "00:00:00" }
        Lighting.TimeOfDay = times[payload] or "12:00:00"
    end
end

return VortexCore
