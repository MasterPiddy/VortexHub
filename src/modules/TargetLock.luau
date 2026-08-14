--[[
    TargetLock.luau - Motor Universal de Auto-Aim & Silent Aim
    - Filtrado Estricto de NPCs: Solo enemigos de combate (workspace.Enemies), excluye 100% tiendas y misiones.
    - Silent Aim Genuino: Libertad total de movimiento y cámara; el cuerpo NO se fuerza a mirar al objetivo.
    - Detección precisa de Jugadores (SafeZone corregida con radio real y ForceField check).
    - PlayerHighlight: Resaltado Rojo Puro.
    - Metamethods estables y seguros con hookmetamethod y checkcaller().
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player and player:GetMouse()

local TargetLock = {}

-- Configuración y Variables Globales
_G.G_SilentAimSkill = false
_G.G_SilentAimTargetPlayers = true
_G.G_SilentAimTargetMobs = true
_G.G_SilentAimPart = "HumanoidRootPart"
_G.G_PlayerHighlight = false
_G.G_AimbotSafeZoneCheck = true
_G.G_AimbotPvPCheck = true
_G.G_SilentAimTeamCheck = false
_G.G_SilentAimSelectedPlayer = ""

local maxRange = 3500
local currentSilentAimTarget = nil
local activeTargetHighlight = nil
local BlacklistedPlayers = {}

--------------------------------------------------------------------------------
-- 1. VALIDACIONES DE JUGADORES (ZONA SEGURA Y PVP CORREGIDOS)
--------------------------------------------------------------------------------

local function AX_ReadPvPState(target)
    if not target or not target:IsA("Player") then return true end
    local ok, isEnabled = pcall(function()
        local attr = target:GetAttribute("PvpDisabled")
        if attr == true then return false end
        return true
    end)
    if not ok then return true end
    return isEnabled
end

local function AX_InSafeZone(target)
    if not target or not target:IsA("Player") then return false end
    local ok, inZone = pcall(function()
        local char = target.Character
        if not char then return false end
        
        -- Si tiene ForceField de spawn activo, está protegido
        if char:FindFirstChildOfClass("ForceField") then return true end

        local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
        if not hrp then return false end
        local wo = Workspace:FindFirstChild("_WorldOrigin")
        if not wo then return false end

        -- 1. Zonas Seguras Reales (_WorldOrigin.SafeZones)
        local safeZones = wo:FindFirstChild("SafeZones")
        if safeZones then
            for _, zone in pairs(safeZones:GetChildren()) do
                local mesh = zone:FindFirstChild("Mesh") or zone:FindFirstChildOfClass("SpecialMesh")
                local scaleX = (mesh and mesh.Scale.X) or 1
                local radius = (zone.Size.X * scaleX) / 2
                if radius and radius > 0 then
                    local dist = (zone.Position - hrp.Position).Magnitude
                    if dist <= radius then return true end
                end
            end
        end

        -- 2. Spawns directos (Radio real de 40 studs)
        local spawns = wo:FindFirstChild("PlayerSpawns")
        if spawns then
            local folder = spawns:FindFirstChild(tostring(target.Team)) or spawns:FindFirstChild("Pirates") or spawns:FindFirstChild("Marines")
            if folder then
                for _, sp in pairs(folder:GetChildren()) do
                    local part = sp:FindFirstChild("Part") or (sp:IsA("BasePart") and sp)
                    if part and (hrp.Position - part.Position).Magnitude <= 40 then
                        return true
                    end
                end
            end
        end
        return false
    end)
    return ok and inZone
end

local function IsSilentAimAlly(p)
    local main = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Main")
    local frame = main and main:FindFirstChild("Allies")
        and main.Allies:FindFirstChild("Container")
        and main.Allies.Container:FindFirstChild("Allies")
        and main.Allies.Container.Allies:FindFirstChild("ScrollingFrame")
        and main.Allies.Container.Allies.ScrollingFrame:FindFirstChild("Frame")
    if not frame then return false end
    return frame:FindFirstChild(p.Name) ~= nil
end

local function IsSilentAimEnemy(p)
    if not p or p == player then return false end
    if IsSilentAimAlly(p) then return false end
    local myTeam, targetTeam = player.Team, p.Team
    if myTeam and targetTeam and myTeam.Name == "Marines" and targetTeam.Name == "Marines" then
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- 2. SELECCIÓN DE OBJETIVOS (JUGADORES Y ENEMIGOS DE COMBATE)
--------------------------------------------------------------------------------

local function GetClosestTargetToCenter()
    local myChar = player.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end

    local maxDist3D = maxRange or 3500

    -- 1. Objetivo Específico Seleccionado
    if _G.G_SilentAimSelectedPlayer and _G.G_SilentAimSelectedPlayer ~= "" and _G.G_SilentAimSelectedPlayer ~= "Nearest" and _G.G_SilentAimSelectedPlayer ~= "Más Cercano" then
        local targetP = Players:FindFirstChild(_G.G_SilentAimSelectedPlayer)
        if targetP and targetP ~= player and targetP.Character and not BlacklistedPlayers[targetP.Name] then
            if _G.G_AimbotPvPCheck and not AX_ReadPvPState(targetP) then return nil end
            if _G.G_AimbotSafeZoneCheck and AX_InSafeZone(targetP) then return nil end
            if not _G.G_SilentAimTeamCheck or IsSilentAimEnemy(targetP) then
                local hum = targetP.Character:FindFirstChildOfClass("Humanoid")
                local hrp = targetP.Character:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and hrp then
                    return targetP.Character:FindFirstChild(_G.G_SilentAimPart) or hrp
                end
            end
        end
        return nil
    end

    local closestPart = nil
    local shortest3DDist = maxDist3D

    local function checkTargetPart(character, isPlayer)
        if not character or character == myChar then return end

        if isPlayer then
            local p = Players:GetPlayerFromCharacter(character)
            if not p or p == player or BlacklistedPlayers[p.Name] then return end
            if _G.G_AimbotPvPCheck and not AX_ReadPvPState(p) then return end
            if _G.G_AimbotSafeZoneCheck and AX_InSafeZone(p) then return end
            if _G.G_SilentAimTeamCheck and not IsSilentAimEnemy(p) then return end
        end

        local hum = character:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local part = character:FindFirstChild(_G.G_SilentAimPart) or character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
        if not part then return end

        local worldDist = (part.Position - myHRP.Position).Magnitude
        if worldDist <= shortest3DDist then
            shortest3DDist = worldDist
            closestPart = part
        end
    end

    -- 2. Escaneo de Jugadores
    if _G.G_SilentAimTargetPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p.Character then
                checkTargetPart(p.Character, true)
            end
        end
    end

    -- 3. Escaneo de Mobs / NPCs de Combate Exclusivamente (workspace.Enemies)
    if _G.G_SilentAimTargetMobs then
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, enemy in ipairs(enemies:GetChildren()) do
                checkTargetPart(enemy, false)
            end
        end
    end

    return closestPart
end

local function IsCurrentToolAimbotAllowed()
    return true
end

local function IsCurrentSlotAimbotAllowed(explicitSkillKey)
    return true
end

--------------------------------------------------------------------------------
-- 3. PLAYER HIGHLIGHT (ROJO PURO)
--------------------------------------------------------------------------------

local function updateTargetHighlight(targetChar)
    if not targetChar or not targetChar:IsA("Model") then
        if activeTargetHighlight then
            pcall(function() activeTargetHighlight:Destroy() end)
            activeTargetHighlight = nil
        end
        return
    end

    if not activeTargetHighlight or activeTargetHighlight.Parent ~= targetChar then
        if activeTargetHighlight then pcall(function() activeTargetHighlight:Destroy() end) end
        activeTargetHighlight = Instance.new("Highlight")
        activeTargetHighlight.Name = "VortexPlayerHighlight"
        activeTargetHighlight.Adornee = targetChar
        activeTargetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        activeTargetHighlight.FillColor = Color3.fromRGB(255, 0, 0) -- Rojo Puro
        activeTargetHighlight.OutlineColor = Color3.fromRGB(255, 60, 60)
        activeTargetHighlight.FillTransparency = 0.35
        activeTargetHighlight.OutlineTransparency = 0
        activeTargetHighlight.Parent = targetChar
    end
end

--------------------------------------------------------------------------------
-- 4. BUCLE DE RENDERSTEPPED (OBJETIVO Y HIGHLIGHT - MOVIMIENTO 100% SILENCIOSO)
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
    pcall(function()
        if _G.G_SilentAimSkill then
            currentSilentAimTarget = GetClosestTargetToCenter()

            -- Silent Aim Genuino: NO se fuerza CFrame del personaje, permitiendo movimiento 100% natural

            if _G.G_PlayerHighlight and currentSilentAimTarget then
                local targetChar = currentSilentAimTarget.Parent
                if targetChar and targetChar:FindFirstChildOfClass("Humanoid") and targetChar.Humanoid.Health > 0 then
                    updateTargetHighlight(targetChar)
                else
                    updateTargetHighlight(nil)
                end
            else
                updateTargetHighlight(nil)
            end
        else
            currentSilentAimTarget = nil
            updateTargetHighlight(nil)
        end
    end)
end)

--------------------------------------------------------------------------------
-- 5. METAMETHODS & REPLICATEDSTORAGE.MOUSE (SILENT AIM SEGURO)
--------------------------------------------------------------------------------

-- Hook de ReplicatedStorage.Mouse
local MouseModuleInstance = ReplicatedStorage:FindFirstChild("Mouse")
local MouseModule = nil
if MouseModuleInstance then
    pcall(function() MouseModule = require(MouseModuleInstance) end)
end
if MouseModule and typeof(MouseModule) == "table" then
    pcall(function()
        local realStore = { Hit = rawget(MouseModule, "Hit"), Target = rawget(MouseModule, "Target") }
        local mmt = getrawmetatable(MouseModule)
        if mmt then setreadonly(mmt, false) else mmt = {}; setmetatable(MouseModule, mmt) end
        rawset(MouseModule, "Hit", nil); rawset(MouseModule, "Target", nil)
        mmt.__index = function(self, key)
            if key == "Hit" then
                if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then 
                    return CFrame.new(currentSilentAimTarget.Position) 
                end
                return realStore.Hit
            elseif key == "Target" then
                if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then 
                    return currentSilentAimTarget 
                end
                return realStore.Target
            end
        end
        mmt.__newindex = function(self, key, value)
            if key == "Hit" or key == "Target" then realStore[key] = value else rawset(self, key, value) end
        end
        setreadonly(mmt, true)
    end)
end

-- Global Metamethod Hooks
local oldIndex = nil
local oldNamecall = nil

if hookmetamethod then
    pcall(function()
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if not checkcaller() then
                if self == mouse and (key == "Hit" or key == "Target") then
                    if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then
                        if key == "Hit"    then return CFrame.new(currentSilentAimTarget.Position) end
                        if key == "Target" then return currentSilentAimTarget end
                    end
                end
            end
            return oldIndex(self, key)
        end))
    end)

    pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local args = {...}
            local ncm = getnamecallmethod and getnamecallmethod()
            local method = ncm and tostring(ncm):lower() or ""

            if not checkcaller() then
                if (method == "fireserver" or method == "invokeserver") then
                    local calledSkill = nil
                    for _, arg in ipairs(args) do
                        if typeof(arg) == "string" then
                            local sUpper = string.upper(arg)
                            if sUpper == "Z" or sUpper == "X" or sUpper == "C" or sUpper == "V" or sUpper == "F" then
                                calledSkill = sUpper
                                break
                            end
                        end
                    end

                    if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed(calledSkill) then
                        local activePos = currentSilentAimTarget.Position

                        if self.Name == "RE/RegisterHit" or self.Name == "RegisterHit" or self.Name:find("RegisterHit") then
                            local targetChar = currentSilentAimTarget.Parent
                            local targetHead = targetChar and (targetChar:FindFirstChild("Head") or targetChar:FindFirstChild("HumanoidRootPart")) or currentSilentAimTarget
                            if targetHead and targetChar then
                                args[1] = targetHead
                                args[2] = { { targetChar, targetHead } }
                                return oldNamecall(self, unpack(args))
                            end
                        end

                        if self.Name == "RE/ShootGunEvent" or self.Name == "ShootGunEvent" or self.Name:find("ShootGunEvent") then
                            args[1] = activePos
                            if currentSilentAimTarget.Parent then
                                args[2] = { currentSilentAimTarget.Parent }
                            end
                            return oldNamecall(self, unpack(args))
                        end

                        for i, arg in ipairs(args) do
                            if typeof(arg) == "Vector3" then 
                                args[i] = activePos
                            elseif typeof(arg) == "CFrame" then 
                                args[i] = CFrame.new(activePos)
                            end
                        end
                        return oldNamecall(self, unpack(args))
                    end
                end
            end

            return oldNamecall(self, ...)
        end))
    end)
else
    pcall(function()
        local mt = getrawmetatable and getrawmetatable(game)
        if mt then
            oldIndex = mt.__index
            oldNamecall = mt.__namecall
            if setreadonly then pcall(setreadonly, mt, false) end

            mt.__index = newcclosure(function(self, key)
                if not checkcaller() and self == mouse and (key == "Hit" or key == "Target") then
                    if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then
                        if key == "Hit"    then return CFrame.new(currentSilentAimTarget.Position) end
                        if key == "Target" then return currentSilentAimTarget end
                    end
                end
                return oldIndex(self, key)
            end)

            mt.__namecall = newcclosure(function(self, ...)
                local args = {...}
                local ncm = getnamecallmethod and getnamecallmethod()
                local method = ncm and tostring(ncm):lower() or ""

                if not checkcaller() and (method == "fireserver" or method == "invokeserver") then
                    local calledSkill = nil
                    for _, arg in ipairs(args) do
                        if typeof(arg) == "string" then
                            local sUpper = string.upper(arg)
                            if sUpper == "Z" or sUpper == "X" or sUpper == "C" or sUpper == "V" or sUpper == "F" then
                                calledSkill = sUpper
                                break
                            end
                        end
                    end

                    if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed(calledSkill) then
                        local activePos = currentSilentAimTarget.Position

                        if self.Name == "RE/RegisterHit" or self.Name == "RegisterHit" or self.Name:find("RegisterHit") then
                            local targetChar = currentSilentAimTarget.Parent
                            local targetHead = targetChar and (targetChar:FindFirstChild("Head") or targetChar:FindFirstChild("HumanoidRootPart")) or currentSilentAimTarget
                            if targetHead and targetChar then
                                args[1] = targetHead
                                args[2] = { { targetChar, targetHead } }
                                return oldNamecall(self, unpack(args))
                            end
                        end

                        if self.Name == "RE/ShootGunEvent" or self.Name == "ShootGunEvent" or self.Name:find("ShootGunEvent") then
                            args[1] = activePos
                            if currentSilentAimTarget.Parent then
                                args[2] = { currentSilentAimTarget.Parent }
                            end
                            return oldNamecall(self, unpack(args))
                        end

                        for i, arg in ipairs(args) do
                            if typeof(arg) == "Vector3" then 
                                args[i] = activePos
                            elseif typeof(arg) == "CFrame" then 
                                args[i] = CFrame.new(activePos)
                            end
                        end
                        return oldNamecall(self, unpack(args))
                    end
                end

                return oldNamecall(self, ...)
            end)
            if setreadonly then pcall(setreadonly, mt, true) end
        end
    end)
end

return TargetLock
