--[[
    TargetLock.luau - Módulo de Auto-Aim / Target Lock sin seguimiento de cámara
    Parte del proyecto VortexHub
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local TargetLock = {
    Enabled = false,
    CurrentTarget = nil,
    PredictMovement = true,
    PredictionLead = 0.12,
    Hooked = false
}

-- Buscar jugador objetivo por Nombre o DisplayName
function TargetLock:SetTarget(playerName)
    if not playerName or playerName == "" then
        self.CurrentTarget = nil
        self.Enabled = false
        return nil
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and (player.Name:lower() == playerName:lower() or player.DisplayName:lower() == playerName:lower()) then
            self.CurrentTarget = player
            self.Enabled = true
            return player
        end
    end

    self.CurrentTarget = nil
    self.Enabled = false
    return nil
end

-- Obtener la posición calculada del objetivo (con predicción de movimiento)
function TargetLock:GetTargetPosition()
    if not self.Enabled or not self.CurrentTarget or not self.CurrentTarget.Character then
        return nil
    end

    local targetChar = self.CurrentTarget.Character
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
        return nil
    end

    local targetPos = targetRoot.Position

    if self.PredictMovement and targetRoot:IsA("BasePart") then
        local velocity = targetRoot.AssemblyLinearVelocity
        targetPos = targetPos + (velocity * self.PredictionLead)
    end

    return targetPos
end

-- Hook para interceptar la propiedad Hit del Mouse (Auto-Aim transparente)
function TargetLock:HookMouse()
    if self.Hooked then return end

    local gmt = getrawmetatable(game)
    setreadonly(gmt, false)
    local oldIndex = gmt.__index

    gmt.__index = newcclosure(function(selfInstance, key)
        if selfInstance == Mouse and (key == "Hit" or key == "hit") then
            local targetPos = TargetLock:GetTargetPosition()
            if targetPos then
                return CFrame.new(targetPos)
            end
        end
        return oldIndex(selfInstance, key)
    end)

    setreadonly(gmt, true)
    self.Hooked = true
end

return TargetLock
