--[[
    TargetLock.luau - Motor Universal de Auto-Aim / Silent Aim (Basado en Sacred AHK)
    - Validaciones Hardcoded: SafeZone Check & PvP Disabled Check automáticas.
    - PlayerHighlight: Resaltador en Rojo Puro (Pure Red).
    - Metamethods de Sacred AHK: __index, __namecall (Raycast, RegisterHit, ShootGunEvent) con protección checkcaller().
    - Hook de ReplicatedStorage.Mouse para soporte total de frutas y habilidades.
    - Soporte completo para Jugadores & NPCs/Mobs.
--]]

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Workspace = game:GetService("Workspace"),
    ReplicatedStorage = game:GetService("ReplicatedStorage")
}

local LocalPlayer = Services.Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local TargetLock = {
    Enabled = false,
    TargetPlayers = true,
    TargetNPCs = true,
    TargetMode = "NearestDistance", -- "NearestDistance", "NearestCursor", "Manual"
    TargetPart = "HumanoidRootPart", -- "HumanoidRootPart", "Head"
    PlayerHighlightEnabled = false,
    MaxRange = 3500,

    CurrentTarget = nil,    -- Player o Model NPC
    PredictMovement = true,
    PredictionLead = 0.12,

    HighlightInstance = nil,
    Hooked = false
}

--------------------------------------------------------------------------------
-- 1. VALIDACIONES HARDCODED (SAFEZONE & PVP DISABLED CHECK)
--------------------------------------------------------------------------------

-- SafeZone Check (Sacred AHK)
function TargetLock:IsInSafeZone(targetChar)
    if not targetChar then return false end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Head")
    if not hrp then return false end

    local ok, inZone = pcall(function()
        local wo = Services.Workspace:FindFirstChild("_WorldOrigin")
        if not wo then return false end

        local safeZones = wo:FindFirstChild("SafeZones")
        if safeZones then
            for _, zone in pairs(safeZones:GetChildren()) do
                local mesh = zone:FindFirstChild("Mesh") or zone:FindFirstChildOfClass("SpecialMesh")
                if mesh then
                    local realDiameter = zone.Size.X * (mesh.Scale and mesh.Scale.X or 1)
                    local radius = realDiameter / 2
                    if radius and radius > 0 then
                        local dist = (zone.Position - hrp.Position).Magnitude
                        if dist <= radius then return true end
                    end
                end
            end
        end

        local spawns = wo:FindFirstChild("PlayerSpawns")
        if spawns then
            for _, folder in pairs(spawns:GetChildren()) do
                for _, sp in pairs(folder:GetChildren()) do
                    local part = sp:FindFirstChild("Part") or sp
                    if part:IsA("BasePart") and (hrp.Position - part.Position).Magnitude <= 300 then
                        return true
                    end
                end
            end
        end
        return false
    end)
    return ok and inZone == true
end

-- PvP Disabled Check (Sacred AHK Multi-Tier con Acceso Seguro)
function TargetLock:IsPvPDisabled(targetPlayer)
    if not targetPlayer or not targetPlayer:IsA("Player") then return false end

    -- 1. Atributos de Red
    local okAttr, attrDisabled = pcall(function()
        return targetPlayer:GetAttribute("PvpDisabled") == true
    end)
    if okAttr and attrDisabled then return true end

    -- 2. Acceso a PlayerGui (Admin / Replicated Workaround)
    local okGui, guiDisabled = pcall(function()
        local pgui = targetPlayer:FindFirstChild("PlayerGui")
        if pgui then
            local main = pgui:FindFirstChild("Main")
            if main then
                local dis = main:FindFirstChild("PvpDisabled")
                if dis and dis.Visible then return true end

                local pvp = main:FindFirstChild("Pvp")
                if pvp then
                    local frame = pvp:FindFirstChild("Frame")
                    local btn = frame and (frame:FindFirstChild("PvpButton") or frame:FindFirstChildOfClass("TextButton"))
                    if btn and btn:IsA("TextButton") then
                        local txt = tostring(btn.Text or ""):upper()
                        if txt:find("OFF") then return true end
                        if txt:find("ON") then return false end
                    end
                end
            end
        end
        return false
    end)
    if okGui and guiDisabled then return true end

    -- 3. Overheads en Head
    local okHead, headDisabled = pcall(function()
        local char = targetPlayer.Character
        local head = char and char:FindFirstChild("Head")
        if head then
            for _, gui in ipairs(head:GetChildren()) do
                if gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") then
                    for _, desc in ipairs(gui:GetDescendants()) do
                        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                            local t = tostring(desc.Text or ""):upper()
                            if t:find("PVP DISABLED") or t:find("SAFE") or t:find("NON-PVP") then
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end)
    if okHead and headDisabled then return true end

    return false
end

--------------------------------------------------------------------------------
-- 2. SELECCIÓN DE OBJETIVOS (SACRED AHK ENGINE)
--------------------------------------------------------------------------------

function TargetLock:GetTargetCharacter(target)
    target = target or self.CurrentTarget
    if not target then return nil end
    if typeof(target) == "Instance" then
        if target:IsA("Player") then
            return target.Character
        elseif target:IsA("Model") then
            return target
        end
    end
    return nil
end

function TargetLock:GetTargetAimPart(target, preferredPart)
    local char = self:GetTargetCharacter(target)
    if not char then return nil end
    preferredPart = preferredPart or self.TargetPart or "HumanoidRootPart"

    return char:FindFirstChild(preferredPart)
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
        or char:FindFirstChild("Torso")
        or char.PrimaryPart
end

function TargetLock:GetClosestTargetToCenter()
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end

    local maxDist3D = self.MaxRange or 3500
    local closestEntity = nil
    local shortest3DDist = maxDist3D

    local function checkEntity(entity, isPlayer)
        if not entity or entity == myChar then return end
        if isPlayer then
            local p = Services.Players:GetPlayerFromCharacter(entity)
            if not p or p == LocalPlayer then return end
            if self:IsPvPDisabled(p) then return end
            if self:IsInSafeZone(entity) then return end
        else
            if self:IsInSafeZone(entity) then return end
        end

        local hum = entity:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local part = entity:FindFirstChild(self.TargetPart) or entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Head")
        if not part then return end

        local dist = (part.Position - myHRP.Position).Magnitude
        if dist <= shortest3DDist then
            shortest3DDist = dist
            closestEntity = isPlayer and Services.Players:GetPlayerFromCharacter(entity) or entity
        end
    end

    if self.TargetPlayers then
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                checkEntity(p.Character, true)
            end
        end
    end

    if self.TargetNPCs then
        local searchFolders = { Services.Workspace }
        for _, folderName in ipairs({"Enemies", "NPCs", "Mobs", "Live", "Characters"}) do
            local f = Services.Workspace:FindFirstChild(folderName)
            if f then table.insert(searchFolders, f) end
        end

        local checked = {}
        for _, folder in ipairs(searchFolders) do
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj ~= myChar and not checked[obj] and not Services.Players:GetPlayerFromCharacter(obj) then
                    checked[obj] = true
                    checkEntity(obj, false)
                end
            end
        end
    end

    return closestEntity
end

function TargetLock:GetNearestTargetByCursor()
    local camera = Services.Workspace.CurrentCamera
    if not camera then return nil end

    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local myChar = LocalPlayer.Character
    local closestEntity = nil
    local shortestDistance = math.huge

    local function checkEntityCursor(entity, isPlayer)
        if not entity or entity == myChar then return end
        if isPlayer then
            local p = Services.Players:GetPlayerFromCharacter(entity)
            if not p or p == LocalPlayer then return end
            if self:IsPvPDisabled(p) then return end
            if self:IsInSafeZone(entity) then return end
        else
            if self:IsInSafeZone(entity) then return end
        end

        local hum = entity:FindFirstChildOfClass("Humanoid")
        local root = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Head")
        if not hum or hum.Health <= 0 or not root then return end

        local screenPos, onScreen = camera:WorldToViewportPoint(root.Position)
        if onScreen then
            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            if dist < shortestDistance then
                shortestDistance = dist
                closestEntity = isPlayer and Services.Players:GetPlayerFromCharacter(entity) or entity
            end
        end
    end

    if self.TargetPlayers then
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                checkEntityCursor(p.Character, true)
            end
        end
    end

    if self.TargetNPCs then
        local searchFolders = { Services.Workspace }
        for _, folderName in ipairs({"Enemies", "NPCs", "Mobs", "Live", "Characters"}) do
            local f = Services.Workspace:FindFirstChild(folderName)
            if f then table.insert(searchFolders, f) end
        end

        local checked = {}
        for _, folder in ipairs(searchFolders) do
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj ~= myChar and not checked[obj] and not Services.Players:GetPlayerFromCharacter(obj) then
                    checked[obj] = true
                    checkEntityCursor(obj, false)
                end
            end
        end
    end

    return closestEntity
end

function TargetLock:GetTargetPosition()
    if not self.Enabled or not self.CurrentTarget then return nil end

    local targetPart = self:GetTargetAimPart(self.CurrentTarget, self.TargetPart)
    if not targetPart then return nil end

    local targetPos = targetPart.Position
    if self.PredictMovement and targetPart:IsA("BasePart") then
        targetPos = targetPos + (targetPart.AssemblyLinearVelocity * self.PredictionLead)
    end
    return targetPos
end

--------------------------------------------------------------------------------
-- 3. PLAYER HIGHLIGHT (ROJO PURO)
--------------------------------------------------------------------------------

function TargetLock:UpdatePlayerHighlight()
    if not self.PlayerHighlightEnabled or not self.Enabled or not self.CurrentTarget then
        if self.HighlightInstance then
            pcall(function() self.HighlightInstance:Destroy() end)
            self.HighlightInstance = nil
        end
        return
    end

    local targetChar = self:GetTargetCharacter(self.CurrentTarget)
    if not targetChar then
        if self.HighlightInstance then
            pcall(function() self.HighlightInstance:Destroy() end)
            self.HighlightInstance = nil
        end
        return
    end

    if not self.HighlightInstance or self.HighlightInstance.Parent ~= targetChar then
        if self.HighlightInstance then pcall(function() self.HighlightInstance:Destroy() end) end

        local hl = Instance.new("Highlight")
        hl.Name = "VortexPlayerHighlight"
        hl.Adornee = targetChar
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor = Color3.fromRGB(255, 0, 0) -- Rojo Puro
        hl.OutlineColor = Color3.fromRGB(255, 60, 60)
        hl.FillTransparency = 0.35
        hl.OutlineTransparency = 0
        hl.Parent = targetChar
        self.HighlightInstance = hl
    end
end

--------------------------------------------------------------------------------
-- 4. BUCLES DE ACTUALIZACIÓN & METAMETHOD HOOKS DE SACRED AHK
--------------------------------------------------------------------------------

-- Actualización periódica atenuada de objetivo
task.spawn(function()
    while task.wait(0.15) do
        if TargetLock.Enabled then
            pcall(function()
                if TargetLock.TargetMode == "NearestDistance" then
                    TargetLock.CurrentTarget = TargetLock:GetClosestTargetToCenter()
                elseif TargetLock.TargetMode == "NearestCursor" then
                    TargetLock.CurrentTarget = TargetLock:GetNearestTargetByCursor()
                end
                TargetLock:UpdatePlayerHighlight()
            end)
        else
            if TargetLock.HighlightInstance then
                pcall(function() TargetLock.HighlightInstance:Destroy() end)
                TargetLock.HighlightInstance = nil
            end
        end
    end
end)

-- Orientación horizontal del personaje
Services.RunService.RenderStepped:Connect(function()
    if TargetLock.Enabled and TargetLock.CurrentTarget then
        local targetPos = TargetLock:GetTargetPosition()
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

        if targetPos and myRoot then
            local lookAt = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
            myRoot.CFrame = CFrame.new(myRoot.Position, lookAt)
        end
    end
end)

function TargetLock:HookAll()
    if self.Hooked then return end
    self.Hooked = true

    -- 1. Hook de ReplicatedStorage.Mouse (Sacred AHK Pattern)
    pcall(function()
        local MouseModuleInstance = Services.ReplicatedStorage:FindFirstChild("Mouse")
        if MouseModuleInstance then
            local MouseModule = require(MouseModuleInstance)
            if MouseModule and typeof(MouseModule) == "table" then
                local realStore = { Hit = rawget(MouseModule, "Hit"), Target = rawget(MouseModule, "Target") }
                local mmt = getrawmetatable(MouseModule)
                if mmt then setreadonly(mmt, false) else mmt = {}; setmetatable(MouseModule, mmt) end
                rawset(MouseModule, "Hit", nil); rawset(MouseModule, "Target", nil)

                mmt.__index = function(selfTable, key)
                    if key == "Hit" then
                        if TargetLock.Enabled and TargetLock.CurrentTarget then
                            local tPos = TargetLock:GetTargetPosition()
                            if tPos then return CFrame.new(tPos) end
                        end
                        return realStore.Hit
                    elseif key == "Target" then
                        if TargetLock.Enabled and TargetLock.CurrentTarget then
                            local tPart = TargetLock:GetTargetAimPart()
                            if tPart then return tPart end
                        end
                        return realStore.Target
                    end
                end
                mmt.__newindex = function(selfTable, key, value)
                    if key == "Hit" or key == "Target" then realStore[key] = value else rawset(selfTable, key, value) end
                end
                setreadonly(mmt, true)
            end
        end
    end)

    -- 2. Hook de Metamétodos Globales (__index y __namecall con checkcaller)
    pcall(function()
        if hookmetamethod then
            local oldIndex = nil
            local oldNamecall = nil

            oldIndex = hookmetamethod(game, "__index", newcclosure(function(selfInstance, key)
                if not checkcaller() and selfInstance == Mouse and (key == "Hit" or key == "hit" or key == "Target" or key == "target") then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        local tPos = TargetLock:GetTargetPosition()
                        if tPos then
                            if key == "Hit" or key == "hit" then return CFrame.new(tPos) end
                            if key == "Target" or key == "target" then return TargetLock:GetTargetAimPart() end
                        end
                    end
                end
                return oldIndex(selfInstance, key)
            end))

            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(selfInstance, ...)
                local args = {...}
                local ncm = getnamecallmethod and getnamecallmethod()
                local method = ncm and tostring(ncm):lower() or ""

                if not checkcaller() and TargetLock.Enabled and TargetLock.CurrentTarget then
                    local activePos = TargetLock:GetTargetPosition()
                    local targetChar = TargetLock:GetTargetCharacter()
                    local targetPart = TargetLock:GetTargetAimPart()

                    if activePos and targetPart then
                        if (method == "fireserver" or method == "invokeserver") then
                            if selfInstance.Name == "RE/RegisterHit" or selfInstance.Name == "RegisterHit" or tostring(selfInstance.Name):find("RegisterHit") then
                                local targetHead = targetChar and (targetChar:FindFirstChild("Head") or targetChar:FindFirstChild("HumanoidRootPart")) or targetPart
                                if targetHead and targetChar then
                                    args[1] = targetHead
                                    args[2] = { { targetChar, targetHead } }
                                    return oldNamecall(selfInstance, unpack(args))
                                end
                            end

                            if selfInstance.Name == "RE/ShootGunEvent" or selfInstance.Name == "ShootGunEvent" or tostring(selfInstance.Name):find("ShootGunEvent") then
                                args[1] = activePos
                                if targetChar then
                                    args[2] = { targetChar }
                                end
                                return oldNamecall(selfInstance, unpack(args))
                            end
                        elseif (method == "raycast" or method == "findpartonray" or method == "findpartonraywithignorelist" or method == "findpartonraywithwhitelist") then
                            if method == "raycast" then
                                return {
                                    Instance = targetPart,
                                    Position = activePos,
                                    Hit = activePos,
                                    Normal = Vector3.new(0, 1, 0),
                                    Material = Enum.Material.SmoothPlastic
                                }
                            else
                                return targetPart, activePos, Vector3.new(0, 1, 0), Enum.Material.SmoothPlastic
                            end
                        end
                    end
                end

                return oldNamecall(selfInstance, ...)
            end))
        else
            local gmt = getrawmetatable(game)
            if setreadonly then setreadonly(gmt, false) end
            local oldIndex = gmt.__index

            gmt.__index = newcclosure(function(selfInstance, key)
                if not checkcaller() and selfInstance == Mouse and (key == "Hit" or key == "hit" or key == "Target" or key == "target") then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        local tPos = TargetLock:GetTargetPosition()
                        if tPos then
                            if key == "Hit" or key == "hit" then return CFrame.new(tPos) end
                            if key == "Target" or key == "target" then return TargetLock:GetTargetAimPart() end
                        end
                    end
                end
                return oldIndex(selfInstance, key)
            end)

            if setreadonly then setreadonly(gmt, true) end
        end
    end)
end

return TargetLock
