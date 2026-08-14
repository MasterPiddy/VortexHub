--[[
    TargetLock.luau - Motor de Auto-Aim / Silent Aim con Filtrado Estricto de NPCs y Orientación Exclusiva al Atacar
    - Multi-Tier PlayerGui Inspector: Lee de forma segura PlayerGui, Character Overheads y Atributos.
    - SafeZoneCheck y PvPDisabledCheck automáticos, seguros y libres de errores.
    - Filtrado Estricto de NPCs: Excluye al 100% NPCs de misiones, tiendas, barcos y diálogos; solo targetea enemigos reales.
    - Orientación Silenciosa: El personaje se mueve 100% natural y SOLO mira hacia el objetivo al atacar o castear habilidades.
    - PlayerHighlight: Resaltado Rojo Puro.
    - Metamethods seguros con checkcaller() y ReplicatedStorage.Mouse.
--]]

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Workspace = game:GetService("Workspace"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    UserInputService = game:GetService("UserInputService")
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

-- Estado de Ataque para Orientación Silenciosa (Solo mira al atacar/usar habilidad)
local isAttacking = false
local attackEndTime = 0

local function TriggerAttackSnap(duration)
    attackEndTime = tick() + (duration or 0.25)
end

-- Listener para clicks, taps móviles y teclas de habilidades
Services.UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isAttacking = true
        TriggerAttackSnap(0.20)
    end
    if input.KeyCode == Enum.KeyCode.Z or input.KeyCode == Enum.KeyCode.X 
        or input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.V 
        or input.KeyCode == Enum.KeyCode.F then
        isAttacking = true
        TriggerAttackSnap(0.35)
    end
end)

Services.UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isAttacking = false
    end
    if input.KeyCode == Enum.KeyCode.Z or input.KeyCode == Enum.KeyCode.X 
        or input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.V 
        or input.KeyCode == Enum.KeyCode.F then
        isAttacking = false
    end
end)

--------------------------------------------------------------------------------
-- 1. WORKAROUND ADMINISTRATIVO DE ACCESO A PLAYERGUI & DATOS DE JUGADORES
--------------------------------------------------------------------------------

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

local function IsPvPDisabled(targetPlayer)
    if not targetPlayer or not targetPlayer:IsA("Player") then return false end
    
    -- Tier 1: Comprobación de Atributos de Red
    local okAttr, attrDisabled = pcall(function()
        return targetPlayer:GetAttribute("PvpDisabled") == true
            or targetPlayer:GetAttribute("PVPDisabled") == true
            or targetPlayer:GetAttribute("SafeZone") == true
            or targetPlayer:GetAttribute("InSafeZone") == true
    end)
    if okAttr and attrDisabled then return true end

    -- Tier 2: Acceso Seguro a PlayerGui
    local okGui, guiDisabled = pcall(function()
        local pgui = TargetLock:GetPlayerGui(targetPlayer)
        if not pgui then return false end

        local main = pgui:FindFirstChild("Main") or pgui:FindFirstChild("MainGui")
        if main then
            local dis = main:FindFirstChild("PvpDisabled") or main:FindFirstChild("SafeZone")
            if dis and dis:IsA("GuiObject") and dis.Visible then
                return true
            end
            
            local pvp = main:FindFirstChild("Pvp")
            if pvp then
                local frame = pvp:FindFirstChild("Frame") or pvp
                local btn = frame:FindFirstChild("PvpButton") or frame:FindFirstChildOfClass("TextButton")
                if btn and btn:IsA("TextButton") then
                    local txt = tostring(btn.Text or ""):upper()
                    if txt:find("OFF") or txt:find("DESACTIVADO") or txt:find("DISABLED") then
                        return true
                    end
                end
            end
        end
        return false
    end)
    if okGui and guiDisabled then return true end

    -- Tier 3: Comprobación de Overheads / Billboards en el Personaje
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

-- Validación Estricta de Enemigos de Combate (Excluye 100% misiones, tiendas y diálogos)
local function IsValidCombatNPC(model)
    if not model or not model:IsA("Model") then return false end
    if Services.Players:GetPlayerFromCharacter(model) then return false end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
    if not hum or not root or hum.Health <= 0 then return false end

    -- Excluir si está en zona segura
    if IsInSafeZone(model) then return false end

    -- Palabras clave de NPCs de misión, tienda y utilidades a excluir
    local blacklistKeywords = {
        "quest", "dealer", "shop", "seller", "giver", "spawn", "boat", "fruit", "sword",
        "gun", "ship", "talk", "dialogue", "manager", "bartender", "alchemist", "teacher",
        "trainer", "mentor", "scientist", "recruiter", "elite hunter", "nerd", "tort",
        "citizen", "customer", "butler", "arowe", "blank", "enchants", "cousin", "blacksmith"
    }

    local nameLower = model.Name:lower()
    for _, kw in ipairs(blacklistKeywords) do
        if nameLower:find(kw) then return false end
    end

    -- Comprobar si tiene diálogos interactivos o carteles de misiones/tiendas
    local head = model:FindFirstChild("Head")
    if head then
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("BillboardGui") or child:IsA("SurfaceGui") or child:IsA("Dialog") then
                local txt = ""
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                        txt = txt .. " " .. tostring(desc.Text or ""):lower()
                    end
                end
                for _, kw in ipairs(blacklistKeywords) do
                    if txt:find(kw) then return false end
                end
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- 2. BÚSQUEDA Y SELECCIÓN DE OBJETIVOS CON FILTROS ACTIVOS
--------------------------------------------------------------------------------

function TargetLock:GetValidTargets()
    local targets = {}
    local myChar = LocalPlayer.Character

    -- 1. Jugadores (Con filtro SafeZone & PvP Multi-Tier)
    if self.TargetPlayers then
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                if not IsPvPDisabled(p) and not IsInSafeZone(p.Character) then
                    local root = p.Character:FindFirstChild("HumanoidRootPart")
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if root and hum and hum.Health > 0 then
                        table.insert(targets, { Instance = p, Character = p.Character, Root = root, IsPlayer = true })
                    end
                end
            end
        end
    end

    -- 2. NPCs / Mobs de Combate (Excluye dadores de misiones y tiendas)
    if self.TargetNPCs then
        local checked = {}

        -- Prioridad 1: Carpeta nativa Enemies
        local enemiesFolder = Services.Workspace:FindFirstChild("Enemies")
        if enemiesFolder then
            for _, obj in ipairs(enemiesFolder:GetChildren()) do
                if obj:IsA("Model") and obj ~= myChar and not checked[obj] then
                    checked[obj] = true
                    if IsValidCombatNPC(obj) then
                        local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj.PrimaryPart
                        table.insert(targets, { Instance = obj, Character = obj, Root = root, IsPlayer = false })
                    end
                end
            end
        end

        -- Prioridad 2: Otras carpetas de entidades vivas
        for _, folderName in ipairs({"Mobs", "Live", "Characters"}) do
            local f = Services.Workspace:FindFirstChild(folderName)
            if f and f ~= enemiesFolder then
                for _, obj in ipairs(f:GetChildren()) do
                    if obj:IsA("Model") and obj ~= myChar and not checked[obj] then
                        checked[obj] = true
                        if IsValidCombatNPC(obj) then
                            local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj.PrimaryPart
                            table.insert(targets, { Instance = obj, Character = obj, Root = root, IsPlayer = false })
                        end
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
    while task.wait(0.12) do
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
            TargetLock.CurrentTarget = nil
            if TargetLock.HighlightInstance then
                pcall(function() TargetLock.HighlightInstance:Destroy() end)
                TargetLock.HighlightInstance = nil
            end
        end
    end
end)

-- Orientación horizontal SILENCIOSA: El personaje SOLO mira al objetivo cuando está atacando o usando habilidades
Services.RunService.RenderStepped:Connect(function()
    local attacking = isAttacking or (tick() < attackEndTime)
    if TargetLock.Enabled and TargetLock.CurrentTarget and attacking then
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
                
                mmt.__index = function(tbl, key)
                    if key == "Hit" or key == "hit" then
                        if TargetLock.Enabled and TargetLock.CurrentTarget then
                            local tPos = TargetLock:GetTargetPosition()
                            if tPos then return CFrame.new(tPos) end
                        end
                        return realStore.Hit
                    elseif key == "Target" or key == "target" then
                        if TargetLock.Enabled and TargetLock.CurrentTarget then
                            local tPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)
                            if tPart then return tPart end
                        end
                        return realStore.Target
                    end
                    return rawget(tbl, key)
                end

                mmt.__newindex = function(tbl, key, value)
                    if key == "Hit" or key == "Target" or key == "hit" or key == "target" then
                        realStore[key] = value
                    else
                        rawset(tbl, key, value)
                    end
                end
                setreadonly(mmt, true)
            end
        end
    end)

    -- 2. Hook Global con hookmetamethod y getrawmetatable
    pcall(function()
        if hookmetamethod then
            local oldIndex = nil
            oldIndex = hookmetamethod(game, "__index", newcclosure(function(selfInstance, key)
                if not checkcaller() and selfInstance == Mouse and (key == "Hit" or key == "hit" or key == "Target" or key == "target") then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        local tPos = TargetLock:GetTargetPosition()
                        if tPos then
                            if key == "Hit" or key == "hit" then return CFrame.new(tPos) end
                            if key == "Target" or key == "target" then
                                local tPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)
                                if tPart then return tPart end
                            end
                        end
                    end
                end
                return oldIndex(selfInstance, key)
            end))

            local oldNamecall = nil
            oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(selfInstance, ...)
                local args = {...}
                local ncm = getnamecallmethod and getnamecallmethod()
                local method = ncm and tostring(ncm):lower() or ""

                if not checkcaller() then
                    if TargetLock.Enabled and TargetLock.CurrentTarget then
                        local tPos = TargetLock:GetTargetPosition()
                        local targetChar = GetTargetCharacter(TargetLock.CurrentTarget)
                        local targetPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)

                        if (method == "fireserver" or method == "invokeserver") and tPos then
                            -- Activar snap de ataque momentáneo al disparar cualquier remote de combate
                            TriggerAttackSnap(0.25)

                            if selfInstance.Name == "RE/RegisterHit" or selfInstance.Name == "RegisterHit" or selfInstance.Name:find("RegisterHit") then
                                if targetPart and targetChar then
                                    args[1] = targetPart
                                    args[2] = { { targetChar, targetPart } }
                                    return oldNamecall(selfInstance, unpack(args))
                                end
                            end

                            if selfInstance.Name == "RE/ShootGunEvent" or selfInstance.Name == "ShootGunEvent" or selfInstance.Name:find("ShootGunEvent") then
                                args[1] = tPos
                                if targetChar then
                                    args[2] = { targetChar }
                                end
                                return oldNamecall(selfInstance, unpack(args))
                            end
                        elseif (method == "raycast" or method == "findpartonray" or method == "findpartonraywithignorelist" or method == "findpartonraywithwhitelist") and tPos then
                            TriggerAttackSnap(0.20)
                            if method == "raycast" then
                                return {
                                    Instance = targetPart,
                                    Position = tPos,
                                    Hit = tPos,
                                    Normal = Vector3.new(0, 1, 0),
                                    Material = Enum.Material.SmoothPlastic
                                }
                            else
                                return targetPart, tPos, Vector3.new(0, 1, 0), Enum.Material.SmoothPlastic
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
                            if key == "Target" or key == "target" then
                                local tPart = GetTargetAimPart(TargetLock.CurrentTarget, TargetLock.TargetPart)
                                if tPart then return tPart end
                            end
                        end
                    end
                end
                return oldIndex(selfInstance, key)
            end)
            if setreadonly then setreadonly(gmt, true) end
        end
    end)
end

-- Activar hooks
TargetLock:HookAll()

return TargetLock
