--[[
    TargetLock.luau - Motor Completo de Auto-Aim / Silent Aim para VortexHub
    - Validaciones Hardcoded: SafeZone Check & PvP Disabled Check automáticas y no editables.
    - PlayerHighlight: Resaltador en Rojo Puro para el objetivo actual.
    - Metamethod Hooks: Mouse.Hit, ReplicatedStorage.Mouse, RegisterHit, ShootGunEvent, Raycasts & FireServer.
    - Soporte para Jugadores & NPCs/Mobs.
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
    
    CurrentTarget = nil,    -- Player o Model NPC
    PredictMovement = true,
    PredictionLead = 0.12,
    
    HighlightInstance = nil,
    Hooked = false
}

--------------------------------------------------------------------------------
-- 1. VALIDACIONES HARDCODED (SAFEZONE & PVP DISABLED CHECK AUTOMÁTICAS)
--------------------------------------------------------------------------------

-- Verificar si el personaje está dentro de Zona Segura o Spawn
local function IsInSafeZone(targetChar)
    if not targetChar then return false end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local wo = Services.Workspace:FindFirstChild("_WorldOrigin")
    if not wo then return false end

    -- SafeZones
    local safeZones = wo:FindFirstChild("SafeZones")
    if safeZones then
        for _, zone in pairs(safeZones:GetChildren()) do
            local mesh = zone:FindFirstChild("Mesh")
            if mesh and mesh:IsA("SpecialMesh") then
                local realDiameter = zone.Size.X * mesh.Scale.X
                local radius = realDiameter / 2
                if radius and radius > 0 then
                    local dist = (zone.Position - hrp.Position).Magnitude
                    if dist <= radius then return true end
                end
            end
        end
    end

    -- Player Spawns
    local spawns = wo:FindFirstChild("PlayerSpawns")
    if spawns then
        for _, folder in pairs(spawns:GetChildren()) do
            for _, sp in pairs(folder:GetChildren()) do
                local part = sp:FindFirstChild("Part") or sp
                if part:IsA("BasePart") and (hrp.Position - part.Position).Magnitude <= 400 then
                    return true
                end
            end
        end
    end
    return false
end

-- Verificar si el jugador tiene el modo PvP desactivado
local function IsPvPDisabled(targetPlayer)
    if not targetPlayer or not targetPlayer:IsA("Player") then return false end
    local ok, disabled = pcall(function()
        local attr = targetPlayer:GetAttribute("PvpDisabled")
        if attr ~= nil then return attr == true end
        local pgui = targetPlayer:FindFirstChild("PlayerGui")
        local main = pgui and pgui:FindFirstChild("Main")
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
                end
            end
        end
        return false
    end)
    return ok and disabled
end

-- Verificar si un modelo es NPC/Mob válido
local function IsValidNPC(model)
    if not model or not model:IsA("Model") then return false end
    if Services.Players:GetPlayerFromCharacter(model) then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
    return (hum and root and hum.Health > 0)
end

--------------------------------------------------------------------------------
-- 2. BÚSQUEDA Y SELECCIÓN DE OBJETIVOS CON FILTROS ACTIVOS
--------------------------------------------------------------------------------

function TargetLock:GetValidTargets()
    local targets = {}
    local myChar = LocalPlayer.Character

    -- 1. Jugadores (Con filtro SafeZone & PvP)
    if self.TargetPlayers then
        for _, player in ipairs(Services.Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                if not IsPvPDisabled(player) and not IsInSafeZone(player.Character) then
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    local hum = player.Character:FindFirstChildOfClass("Humanoid")
                    if root and hum and hum.Health > 0 then
                        table.insert(targets, { Instance = player, Character = player.Character, Root = root, IsPlayer = true })
                    end
                end
            end
        end
    end

    -- 2. NPCs / Mobs (Búsqueda optimizada en carpetas comunes)
    if self.TargetNPCs then
        local searchFolders = { Services.Workspace }
        for _, folderName in ipairs({"Enemies", "NPCs", "Mobs", "Live", "Characters"}) do
            local f = Services.Workspace:FindFirstChild(folderName)
            if f then table.insert(searchFolders, f) end
        end

        local checked = {}
        for _, folder in ipairs(searchFolders) do
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj ~= myChar and not checked[obj] then
                    checked[obj] = true
                    if IsValidNPC(obj) and not IsInSafeZone(obj) then
                        local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj.PrimaryPart
                        table.insert(targets, { Instance = obj, Character = obj, Root = root, IsPlayer = false })
                    end
                end
            end
        end
    end

    return targets
end

function TargetLock:GetNearestTargetByDistance()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local targets = self:GetValidTargets()
    local closest = nil
    local shortestDistance = math.huge

    for _, t in ipairs(targets) do
        local dist = (t.Root.Position - myRoot.Position).Magnitude
        if dist < shortestDistance then
            shortestDistance = dist
            closest = t.Instance
        end
    end

    return closest
end

function TargetLock:GetNearestTargetByCursor()
    local camera = Services.Workspace.CurrentCamera
    if not camera then return nil end

    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local targets = self:GetValidTargets()
    local closest = nil
    local shortestDistance = math.huge

    for _, t in ipairs(targets) do
        local screenPos, onScreen = camera:WorldToViewportPoint(t.Root.Position)
        if onScreen then
            local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            if dist < shortestDistance then
                shortestDistance = dist
                closest = t.Instance
            end
        end
    end

    return closest
end

local function GetTargetCharacter(target)
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

local function GetTargetAimPart(target, preferredPart)
    local char = GetTargetCharacter(target)
    if not char then return nil end
    preferredPart = preferredPart or "HumanoidRootPart"

    return char:FindFirstChild(preferredPart) 
        or char:FindFirstChild("HumanoidRootPart") 
        or char:FindFirstChild("Head") 
        or char:FindFirstChild("Torso") 
        or char.PrimaryPart
end

function TargetLock:GetTargetPosition()
    if not self.Enabled or not self.CurrentTarget then return nil end

    local targetPart = GetTargetAimPart(self.CurrentTarget, self.TargetPart)
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

    local targetChar = GetTargetCharacter(self.CurrentTarget)
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
-- 4. BUCLES DE ACTUALIZACIÓN Y HOOKS METATABLARES
--------------------------------------------------------------------------------

task.spawn(function()
    while task.wait(0.15) do
        if TargetLock.Enabled then
            pcall(function()
                if TargetLock.TargetMode == "NearestDistance" then
                    TargetLock.CurrentTarget = TargetLock:GetNearestTargetByDistance()
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

-- Orientación horizontal ligera del personaje
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

    -- 1. Hook de ReplicatedStorage.Mouse (Skills de Blox Fruits)
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
                            local tPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)
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

    -- 2. Hook global de Mouse y Namecall
    pcall(function()
        local gmt = getrawmetatable(game)
        if setreadonly then setreadonly(gmt, false) end
        local oldIndex = gmt.__index
        local oldNamecall = gmt.__namecall

        gmt.__index = newcclosure(function(selfInstance, key)
            if selfInstance == Mouse then
                if key == "Hit" or key == "hit" then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        local targetPos = TargetLock:GetTargetPosition()
                        if targetPos then return CFrame.new(targetPos) end
                    end
                elseif key == "Target" or key == "target" then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        local targetPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)
                        if targetPart then return targetPart end
                    end
                end
            end
            return oldIndex(selfInstance, key)
        end)

        gmt.__namecall = newcclosure(function(selfInstance, ...)
            local method = getnamecallmethod()
            local args = {...}

            if TargetLock.Enabled and TargetLock.CurrentTarget then
                local targetPos = TargetLock:GetTargetPosition()
                local targetChar = GetTargetCharacter(TargetLock.CurrentTarget)
                local targetPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)

                if targetPos and targetChar and targetPart then
                    -- Raycasts de habilidades
                    if method == "Raycast" or method == "raycast" or method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" then
                        local origin = args[1]
                        if typeof(origin) == "Vector3" then
                            args[2] = (targetPos - origin).Unit * 1000
                            return oldNamecall(selfInstance, unpack(args))
                        end
                    end

                    -- Remotes de impacto (RegisterHit)
                    if selfInstance.Name == "RE/RegisterHit" or selfInstance.Name == "RegisterHit" or tostring(selfInstance.Name):find("RegisterHit") then
                        args[1] = targetPart
                        args[2] = { { targetChar, targetPart } }
                        return oldNamecall(selfInstance, unpack(args))
                    end

                    -- FireServer genérico con CFrame o Vector3
                    if method == "FireServer" or method == "fireServer" then
                        for i, arg in ipairs(args) do
                            if typeof(arg) == "CFrame" then
                                args[i] = CFrame.new(arg.Position, targetPos)
                            elseif typeof(arg) == "Vector3" and arg.Magnitude < 2 then
                                local myChar = LocalPlayer.Character
                                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                                if myRoot then
                                    args[i] = (targetPos - myRoot.Position).Unit
                                end
                            end
                        end
                        return oldNamecall(selfInstance, unpack(args))
                    end
                end
            end

            return oldNamecall(selfInstance, ...)
        end)

        if setreadonly then setreadonly(gmt, true) end
    end)

    self.Hooked = true
end

return TargetLock
