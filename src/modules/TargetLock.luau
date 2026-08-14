--[[
    TargetLock.luau - Motor de Auto-Aim con Workaround Administrativo de Acceso a PlayerGui
    - Multi-Tier PlayerGui Inspector: Lee de forma segura PlayerGui (si está disponible/admin), Character Overheads y Atributos.
    - SafeZoneCheck y PvPDisabledCheck automáticos, seguros y libres de errores.
    - PlayerHighlight: Resaltado Rojo Puro.
    - Metamethods seguros con checkcaller() y compatibilidad con hookmetamethod.
    - ReplicatedStorage.Mouse hook y orientación de personaje para impacto 100%.
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
-- 1. WORKAROUND ADMINISTRATIVO DE ACCESO A PLAYERGUI & DATOS DE JUGADORES
--------------------------------------------------------------------------------

-- Intenta obtener el PlayerGui de cualquier jugador de forma segura y tolerante a fallos
function TargetLock:GetPlayerGui(targetPlayer)
    if not targetPlayer or not targetPlayer:IsA("Player") then return nil end
    if targetPlayer == LocalPlayer then
        return LocalPlayer:FindFirstChild("PlayerGui")
    end

    local pgui = nil
    pcall(function()
        pgui = targetPlayer:FindFirstChild("PlayerGui")
    end)
    return pgui
end

-- Determina el estado PvP inspeccionando PlayerGui, Overheads y Atributos de red
local function IsPvPDisabled(targetPlayer)
    if not targetPlayer or not targetPlayer:IsA("Player") then return false end
    
    -- Tier 1: Comprobación de Atributos de Red
    local okAttr, attrDisabled = pcall(function()
        return targetPlayer:GetAttribute("PvpDisabled") == true
    end)
    if okAttr and attrDisabled then return true end

    -- Tier 2: Acceso Seguro a PlayerGui (Admin Workaround)
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

    -- Tier 3: Comprobación de Overheads / Billboards en el Personaje (Head)
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

-- Verificar si el personaje está dentro de Zona Segura o Spawn
local function IsInSafeZone(targetChar)
    if not targetChar then return false end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Head")
    if not hrp then return false end

    local ok, inZone = pcall(function()
        local wo = Services.Workspace:FindFirstChild("_WorldOrigin")
        if not wo then return false end

        -- SafeZones
        local safeZones = wo:FindFirstChild("SafeZones")
        if safeZones then
            for _, zone in ipairs(safeZones:GetChildren()) do
                local mesh = zone:FindFirstChildOfClass("SpecialMesh")
                local diameter = zone.Size.X * (mesh and mesh.Scale.X or 1)
                local radius = diameter / 2
                if radius > 0 and (zone.Position - hrp.Position).Magnitude <= radius then
                    return true
                end
            end
        end

        -- Player Spawns
        local spawns = wo:FindFirstChild("PlayerSpawns")
        if spawns then
            for _, folder in ipairs(spawns:GetChildren()) do
                for _, sp in ipairs(folder:GetChildren()) do
                    if sp:IsA("BasePart") and (hrp.Position - sp.Position).Magnitude <= 300 then
                        return true
                    end
                end
            end
        end
        return false
    end)

    return ok and inZone == true
end

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

    -- 1. Jugadores (Con filtro SafeZone & PvP Multi-Tier)
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

    -- 2. NPCs / Mobs (Búsqueda acotada y optimizada)
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
-- 4. BUCLES DE ACTUALIZACIÓN Y HOOKS METATABLARES SEGUROS
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

-- Orientación horizontal del personaje para dirigir ataques Melee, Espadas y Frutas
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

    -- 1. Hook del Módulo ReplicatedStorage.Mouse
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

    -- 2. Hook global seguro de Mouse.__index con checkcaller()
    pcall(function()
        if hookmetamethod then
            local oldIndex = nil
            oldIndex = hookmetamethod(game, "__index", newcclosure(function(selfInstance, key)
                if not checkcaller() and selfInstance == Mouse and (key == "Hit" or key == "hit" or key == "Target" or key == "target") then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        if key == "Hit" or key == "hit" then
                            local targetPos = TargetLock:GetTargetPosition()
                            if targetPos then return CFrame.new(targetPos) end
                        elseif key == "Target" or key == "target" then
                            local targetPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)
                            if targetPart then return targetPart end
                        end
                    end
                end
                return oldIndex(selfInstance, key)
            end))
        else
            local gmt = getrawmetatable(game)
            if setreadonly then setreadonly(gmt, false) end
            local oldIndex = gmt.__index

            gmt.__index = newcclosure(function(selfInstance, key)
                if not checkcaller() and selfInstance == Mouse and (key == "Hit" or key == "hit" or key == "Target" or key == "target") then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        if key == "Hit" or key == "hit" then
                            local targetPos = TargetLock:GetTargetPosition()
                            if targetPos then return CFrame.new(targetPos) end
                        elseif key == "Target" or key == "target" then
                            local targetPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)
                            if targetPart then return targetPart end
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
