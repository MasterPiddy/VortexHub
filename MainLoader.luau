--[[
    VortexHub MainLoader.luau - Monolítico Universal
    - Multi-Tier PlayerGui Inspector seguro con lectura tolerante a fallos.
    - SafeZoneCheck y PvPDisabledCheck automáticos, seguros y libres de errores.
    - Filtrado Estricto de NPCs: Excluye 100% dadores de misiones, tiendas y diálogos.
    - Orientación Silenciosa: Movimiento 100% natural; el cuerpo solo gira hacia el objetivo al atacar o castear habilidades.
    - PlayerHighlight: Resaltado Rojo Puro.
    - Hooks seguros con checkcaller() y ReplicatedStorage.Mouse.
    
    Ejecutable mediante:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/MainLoader.luau"))()
--]]

print("[VortexHub] Cargando script...")

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Lighting = game:GetService("Lighting"),
    HttpService = game:GetService("HttpService"),
    TweenService = game:GetService("TweenService"),
    UserInputService = game:GetService("UserInputService"),
    CoreGui = game:GetService("CoreGui"),
    Workspace = game:GetService("Workspace"),
    ReplicatedStorage = game:GetService("ReplicatedStorage")
}

local LocalPlayer = Services.Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Limpieza exhaustiva de cualquier UI previa en todos los contenedores
local function CleanOldUI()
    local targetContainers = {}

    if gethui then
        pcall(function() table.insert(targetContainers, gethui()) end)
    end
    pcall(function() table.insert(targetContainers, Services.CoreGui) end)
    if LocalPlayer:FindFirstChild("PlayerGui") then
        table.insert(targetContainers, LocalPlayer.PlayerGui)
    end

    for _, container in ipairs(targetContainers) do
        if container and typeof(container) == "Instance" then
            for _, child in ipairs(container:GetChildren()) do
                if child.Name == "VortexHubScreenGui" or child.Name == "VortexLogoButton" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end

CleanOldUI()

-- Entorno Global de VortexHub
local VortexHub = {
    Version = "1.0.0",
    Config = {},
    
    -- Target Lock State
    TargetLockEnabled = false,
    TargetPlayers = true,
    TargetNPCs = true,
    TargetMode = "NearestDistance", -- "NearestDistance", "NearestCursor", "Manual"
    TargetPart = "HumanoidRootPart", -- "HumanoidRootPart", "Head"
    PlayerHighlightEnabled = false,
    CurrentTarget = nil,
    PredictMovement = true,
    PredictionLead = 0.12,
    HighlightInstance = nil,
    Hooked = false,

    -- Player Tracker State
    TrackerEnabled = false,
    TrackedPlayer = nil,
    TrackedData = { Distance = 0, Position = Vector3.zero, Health = 100 },
    TrackerBillboard = nil,

    -- Logo oficial Orbital V
    LogoAsset = "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/vortex_logo.png",

    -- UI State
    AccentColor = Color3.fromRGB(138, 43, 226),
    ThemeElements = {},
    Themes = {
        Purple = Color3.fromRGB(138, 43, 226),
        Cyan = Color3.fromRGB(0, 240, 255),
        Crimson = Color3.fromRGB(255, 36, 0),
        Green = Color3.fromRGB(0, 255, 102),
        Amber = Color3.fromRGB(255, 179, 0)
    },
    
    Commands = {}
}

--------------------------------------------------------------------------------
-- 1. ESTADO DE ATAQUE PARA ORIENTACIÓN SILENCIOSA
--------------------------------------------------------------------------------

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
-- 2. WORKAROUND ADMINISTRATIVO DE ACCESO A PLAYERGUI & DATOS DE JUGADORES
--------------------------------------------------------------------------------

function VortexHub:GetPlayerGui(targetPlayer)
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
        local pgui = VortexHub:GetPlayerGui(targetPlayer)
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

local function IsInSafeZone(targetChar)
    if not targetChar then return false end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Head")
    if not hrp then return false end

    local ok, inZone = pcall(function()
        local wo = Services.Workspace:FindFirstChild("_WorldOrigin")
        if not wo then return false end

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

    if IsInSafeZone(model) then return false end

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
-- 3. MOTOR DE TARGET LOCK (AUTO-AIM)
--------------------------------------------------------------------------------

function VortexHub:GetValidTargets()
    local targets = {}
    local myChar = LocalPlayer.Character

    -- 1. Jugadores
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

    -- 2. NPCs / Mobs de Combate (Filtrado estricto)
    if self.TargetNPCs then
        local checked = {}

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

function VortexHub:GetNearestTargetByDistance()
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

function VortexHub:GetNearestTargetByCursor()
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

function VortexHub:GetTargetPosition()
    if not self.TargetLockEnabled or not self.CurrentTarget then return nil end

    local targetPart = GetTargetAimPart(self.CurrentTarget, self.TargetPart)
    if not targetPart then return nil end

    local targetPos = targetPart.Position
    if self.PredictMovement and targetPart:IsA("BasePart") then
        targetPos = targetPos + (targetPart.AssemblyLinearVelocity * self.PredictionLead)
    end
    return targetPos
end

function VortexHub:UpdatePlayerHighlight()
    if not self.PlayerHighlightEnabled or not self.TargetLockEnabled or not self.CurrentTarget then
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

-- Bucle Asíncrono de Detección de Objetivos
task.spawn(function()
    while task.wait(0.12) do
        if VortexHub.TargetLockEnabled then
            pcall(function()
                if VortexHub.TargetMode == "NearestDistance" then
                    VortexHub.CurrentTarget = VortexHub:GetNearestTargetByDistance()
                elseif VortexHub.TargetMode == "NearestCursor" then
                    VortexHub.CurrentTarget = VortexHub:GetNearestTargetByCursor()
                end
                VortexHub:UpdatePlayerHighlight()
            end)
        else
            VortexHub.CurrentTarget = nil
            if VortexHub.HighlightInstance then
                pcall(function() VortexHub.HighlightInstance:Destroy() end)
                VortexHub.HighlightInstance = nil
            end
        end
    end
end)

-- Orientación horizontal SILENCIOSA: El personaje SOLO gira hacia el objetivo cuando ataca o usa habilidades
Services.RunService.RenderStepped:Connect(function()
    local attacking = isAttacking or (tick() < attackEndTime)
    if VortexHub.TargetLockEnabled and VortexHub.CurrentTarget and attacking then
        local targetPos = VortexHub:GetTargetPosition()
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

        if targetPos and myRoot then
            local lookAt = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
            myRoot.CFrame = CFrame.new(myRoot.Position, lookAt)
        end
    end
end)

function VortexHub:HookCombatRedirection()
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
                        if VortexHub.TargetLockEnabled and VortexHub.CurrentTarget then
                            local tPos = VortexHub:GetTargetPosition()
                            if tPos then return CFrame.new(tPos) end
                        end
                        return realStore.Hit
                    elseif key == "Target" or key == "target" then
                        if VortexHub.TargetLockEnabled and VortexHub.CurrentTarget then
                            local tPart = GetTargetAimPart(VortexHub.CurrentTarget, VortexHub.TargetPart)
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
                    if VortexHub.TargetLockEnabled and VortexHub.CurrentTarget then
                        local tPos = VortexHub:GetTargetPosition()
                        if tPos then
                            if key == "Hit" or key == "hit" then return CFrame.new(tPos) end
                            if key == "Target" or key == "target" then
                                local tPart = GetTargetAimPart(VortexHub.CurrentTarget, VortexHub.TargetPart)
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
                    if VortexHub.TargetLockEnabled and VortexHub.CurrentTarget then
                        local tPos = VortexHub:GetTargetPosition()
                        local targetChar = GetTargetCharacter(VortexHub.CurrentTarget)
                        local targetPart = GetTargetAimPart(VortexHub.CurrentTarget, VortexHub.TargetPart)

                        if (method == "fireserver" or method == "invokeserver") and tPos then
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
                    if VortexHub.TargetLockEnabled and VortexHub.CurrentTarget then
                        local tPos = VortexHub:GetTargetPosition()
                        if tPos then
                            if key == "Hit" or key == "hit" then return CFrame.new(tPos) end
                            if key == "Target" or key == "target" then
                                local tPart = GetTargetAimPart(VortexHub.CurrentTarget, VortexHub.TargetPart)
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

VortexHub:HookCombatRedirection()

--------------------------------------------------------------------------------
-- 4. MÓDULO PLAYER TRACKER (Etiqueta ESP Compacta)
--------------------------------------------------------------------------------
local function ClearTrackerMarker()
    if VortexHub.TrackerBillboard then
        pcall(function() VortexHub.TrackerBillboard:Destroy() end)
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
    billboard.Size = UDim2.new(0, 135, 0, 24)
    billboard.StudsOffset = Vector3.new(0, 2.2, 0)
    billboard.AlwaysOnTop = true

    local frame = Instance.new("Frame")
    frame.Name = "TrackerFrame"
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    frame.BackgroundTransparency = 0.2
    frame.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = frame

    local frameStroke = Instance.new("UIStroke")
    frameStroke.Thickness = 1
    frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    frameStroke.Color = VortexHub.AccentColor
    frameStroke.Parent = frame
    table.insert(VortexHub.ThemeElements, frameStroke)

    local label = Instance.new("TextLabel")
    label.Name = "TrackerText"
    label.Size = UDim2.new(1, -6, 1, 0)
    label.Position = UDim2.new(0, 3, 0, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.6
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextSize = 11
    label.Font = Enum.Font.GothamBold
    label.RichText = true
    label.Text = targetPlayer.DisplayName
    label.Parent = frame

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

    if VortexHub.TrackerBillboard and VortexHub.TrackerBillboard:FindFirstChild("TrackerFrame") then
        local label = VortexHub.TrackerBillboard.TrackerFrame:FindFirstChild("TrackerText")
        if label then
            label.Text = string.format("🎯 <b>%s</b> • <font color='#00FF66'>%dm</font> • %d%%",
                VortexHub.TrackedPlayer.DisplayName, distanceMeters, health)
        end
    end
end

Services.RunService.Heartbeat:Connect(function()
    if VortexHub.TrackerEnabled then
        UpdatePlayerTracker()
    end
end)

--------------------------------------------------------------------------------
-- 5. REGISTRO ESTRUCTURAL DE COMANDOS
--------------------------------------------------------------------------------

VortexHub.Commands["target_lock"] = function(args)
    if typeof(args) == "table" then
        if args.enabled ~= nil then
            VortexHub.TargetLockEnabled = args.enabled
            if not args.enabled then
                VortexHub.CurrentTarget = nil
                VortexHub:UpdatePlayerHighlight()
            end
        end
        if args.targetPlayers ~= nil then
            VortexHub.TargetPlayers = args.targetPlayers
        end
        if args.targetNPCs ~= nil then
            VortexHub.TargetNPCs = args.targetNPCs
        end
        if args.targetMode then VortexHub.TargetMode = args.targetMode end
        if args.targetPart then VortexHub.TargetPart = args.targetPart end
        if args.playerHighlight ~= nil then
            VortexHub.PlayerHighlightEnabled = args.playerHighlight
            VortexHub:UpdatePlayerHighlight()
        end
    end
end

VortexHub.Commands["player_tracker"] = function(args)
    if typeof(args) == "table" then
        if args.enabled ~= nil then
            VortexHub.TrackerEnabled = args.enabled
        end

        if not VortexHub.TrackerEnabled then
            VortexHub.TrackedPlayer = nil
            ClearTrackerMarker()
            return
        end

        local found = nil
        if args.targetPlayer and args.targetPlayer ~= "" then
            for _, p in ipairs(Services.Players:GetPlayers()) do
                if p ~= LocalPlayer and (p.Name:lower() == args.targetPlayer:lower() or p.DisplayName:lower() == args.targetPlayer:lower()) then
                    found = p
                    break
                end
            end
        end

        if not found and VortexHub.CurrentTarget then
            if typeof(VortexHub.CurrentTarget) == "Instance" and VortexHub.CurrentTarget:IsA("Player") then
                found = VortexHub.CurrentTarget
            end
        end

        VortexHub.TrackedPlayer = found
        if found then
            CreateTrackerMarker(found)
        else
            ClearTrackerMarker()
        end
    end
end

function VortexHub:RunCommand(commandId, payload)
    local commandFunc = self.Commands[commandId]
    if commandFunc then
        pcall(function() commandFunc(payload) end)
    end
end

--------------------------------------------------------------------------------
-- 6. INTERFAZ GRÁFICA MÓVIL (PESTAÑA COMBAT)
--------------------------------------------------------------------------------

function VortexHub:SetAccentColor(color)
    self.AccentColor = color
    for _, item in ipairs(self.ThemeElements) do
        if item and item.Parent then
            if item:IsA("UIStroke") then
                item.Color = color
            elseif item:IsA("TextLabel") or item:IsA("TextButton") then
                if item:GetAttribute("IsThemeAccent") then
                    item.TextColor3 = color
                end
            end
        end
    end
end

local function MakeDraggable(guiObject, handleObject)
    handleObject = handleObject or guiObject
    local dragging = false
    local dragInput, dragStart, startPos

    handleObject.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    guiObject.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    Services.UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            guiObject.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

function VortexHub:RenderCombatCategory(contentArea)
    if not contentArea then return end
    contentArea:ClearAllChildren()

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = self.AccentColor
    scroll.Parent = contentArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 12)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.Parent = scroll

    -- 1. TARJETA CONTROL AUTO-AIM
    local aimCard = Instance.new("Frame")
    aimCard.Size = UDim2.new(0.95, 0, 0, 195)
    aimCard.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    aimCard.Parent = scroll

    local aimCorner = Instance.new("UICorner")
    aimCorner.CornerRadius = UDim.new(0, 10)
    aimCorner.Parent = aimCard

    local aimTitle = Instance.new("TextLabel")
    aimTitle.Size = UDim2.new(0.6, 0, 0, 30)
    aimTitle.Position = UDim2.new(0, 12, 0, 8)
    aimTitle.BackgroundTransparency = 1
    aimTitle.Text = "⚔️ <b>AUTO-AIM (TARGET LOCK)</b>"
    aimTitle.RichText = true
    aimTitle.Font = Enum.Font.GothamBold
    aimTitle.TextSize = 14
    aimTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    aimTitle.TextXAlignment = Enum.TextXAlignment.Left
    aimTitle.Parent = aimCard

    local aimToggle = Instance.new("TextButton")
    aimToggle.Size = UDim2.new(0, 70, 0, 28)
    aimToggle.Position = UDim2.new(1, -82, 0, 8)
    aimToggle.BackgroundColor3 = self.TargetLockEnabled and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
    aimToggle.Text = self.TargetLockEnabled and "ON" or "OFF"
    aimToggle.Font = Enum.Font.GothamBold
    aimToggle.TextSize = 13
    aimToggle.TextColor3 = self.TargetLockEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    aimToggle.Parent = aimCard

    Instance.new("UICorner", aimToggle).CornerRadius = UDim.new(0, 14)

    aimToggle.MouseButton1Click:Connect(function()
        local newState = not self.TargetLockEnabled
        self:RunCommand("target_lock", { enabled = newState })
        
        aimToggle.BackgroundColor3 = self.TargetLockEnabled and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
        aimToggle.Text = self.TargetLockEnabled and "ON" or "OFF"
        aimToggle.TextColor3 = self.TargetLockEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    end)

    -- Filtro de Objetivos (Jugadores / NPCs)
    local filterLabel = Instance.new("TextLabel")
    filterLabel.Size = UDim2.new(1, -24, 0, 20)
    filterLabel.Position = UDim2.new(0, 12, 0, 40)
    filterLabel.BackgroundTransparency = 1
    filterLabel.Text = "Tipo de Objetivo:"
    filterLabel.Font = Enum.Font.GothamMedium
    filterLabel.TextSize = 11.5
    filterLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    filterLabel.TextXAlignment = Enum.TextXAlignment.Left
    filterLabel.Parent = aimCard

    local playersToggle = Instance.new("TextButton")
    playersToggle.Size = UDim2.new(0.44, 0, 0, 30)
    playersToggle.Position = UDim2.new(0, 12, 0, 62)
    playersToggle.BackgroundColor3 = self.TargetPlayers and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
    playersToggle.Text = "👥 Jugadores: " .. (self.TargetPlayers and "SI" or "NO")
    playersToggle.Font = Enum.Font.GothamMedium
    playersToggle.TextSize = 11.5
    playersToggle.TextColor3 = Color3.fromRGB(240, 200, 255)
    playersToggle.Parent = aimCard

    Instance.new("UICorner", playersToggle).CornerRadius = UDim.new(0, 6)

    playersToggle.MouseButton1Click:Connect(function()
        local newState = not self.TargetPlayers
        self:RunCommand("target_lock", { targetPlayers = newState })
        playersToggle.BackgroundColor3 = self.TargetPlayers and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
        playersToggle.Text = "👥 Jugadores: " .. (self.TargetPlayers and "SI" or "NO")
    end)

    local npcsToggle = Instance.new("TextButton")
    npcsToggle.Size = UDim2.new(0.44, 0, 0, 30)
    npcsToggle.Position = UDim2.new(0.51, 0, 0, 62)
    npcsToggle.BackgroundColor3 = self.TargetNPCs and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
    npcsToggle.Text = "👾 NPCs/Mobs: " .. (self.TargetNPCs and "SI" or "NO")
    npcsToggle.Font = Enum.Font.GothamMedium
    npcsToggle.TextSize = 11.5
    npcsToggle.TextColor3 = Color3.fromRGB(240, 200, 255)
    npcsToggle.Parent = aimCard

    Instance.new("UICorner", npcsToggle).CornerRadius = UDim.new(0, 6)

    npcsToggle.MouseButton1Click:Connect(function()
        local newState = not self.TargetNPCs
        self:RunCommand("target_lock", { targetNPCs = newState })
        npcsToggle.BackgroundColor3 = self.TargetNPCs and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
        npcsToggle.Text = "👾 NPCs/Mobs: " .. (self.TargetNPCs and "SI" or "NO")
    end)

    -- Selector de Parte a Impactar (HumanoidRootPart / Head)
    local partBtn = Instance.new("TextButton")
    partBtn.Size = UDim2.new(0.44, 0, 0, 30)
    partBtn.Position = UDim2.new(0, 12, 0, 100)
    partBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    partBtn.Text = "🎯 Parte: " .. (self.TargetPart == "Head" and "Cabeza" or "Cuerpo")
    partBtn.Font = Enum.Font.GothamMedium
    partBtn.TextSize = 11
    partBtn.TextColor3 = Color3.fromRGB(0, 240, 255)
    partBtn.Parent = aimCard
    Instance.new("UICorner", partBtn).CornerRadius = UDim.new(0, 6)

    partBtn.MouseButton1Click:Connect(function()
        local newPart = (self.TargetPart == "HumanoidRootPart") and "Head" or "HumanoidRootPart"
        self:RunCommand("target_lock", { targetPart = newPart })
        partBtn.Text = "🎯 Parte: " .. (self.TargetPart == "Head" and "Cabeza" or "Cuerpo")
    end)

    -- Toggle PlayerHighlight (Rojo Puro)
    local highlightBtn = Instance.new("TextButton")
    highlightBtn.Size = UDim2.new(0.44, 0, 0, 30)
    highlightBtn.Position = UDim2.new(0.51, 0, 0, 100)
    highlightBtn.BackgroundColor3 = self.PlayerHighlightEnabled and Color3.fromRGB(220, 30, 30) or Color3.fromRGB(15, 12, 28)
    highlightBtn.Text = "🔴 Highlight: " .. (self.PlayerHighlightEnabled and "ON" or "OFF")
    highlightBtn.Font = Enum.Font.GothamMedium
    highlightBtn.TextSize = 11
    highlightBtn.TextColor3 = self.PlayerHighlightEnabled and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    highlightBtn.Parent = aimCard
    Instance.new("UICorner", highlightBtn).CornerRadius = UDim.new(0, 6)

    highlightBtn.MouseButton1Click:Connect(function()
        local newHighlight = not self.PlayerHighlightEnabled
        self:RunCommand("target_lock", { playerHighlight = newHighlight })
        highlightBtn.BackgroundColor3 = self.PlayerHighlightEnabled and Color3.fromRGB(220, 30, 30) or Color3.fromRGB(15, 12, 28)
        highlightBtn.Text = "🔴 Highlight: " .. (self.PlayerHighlightEnabled and "ON" or "OFF")
        highlightBtn.TextColor3 = self.PlayerHighlightEnabled and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    end)

    -- Selector de Modo de Fijación
    local modeBtn = Instance.new("TextButton")
    modeBtn.Size = UDim2.new(0.95, -24, 0, 32)
    modeBtn.Position = UDim2.new(0, 12, 0, 140)
    modeBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    modeBtn.Text = "🎯 Modo: " .. (self.TargetMode == "NearestDistance" and "Distancia Más Cercana" or "Más Cercano al Cursor")
    modeBtn.Font = Enum.Font.GothamMedium
    modeBtn.TextSize = 11.5
    modeBtn.TextColor3 = Color3.fromRGB(0, 240, 255)
    modeBtn.Parent = aimCard
    Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)

    modeBtn.MouseButton1Click:Connect(function()
        local newMode = (self.TargetMode == "NearestDistance") and "NearestCursor" or "NearestDistance"
        self:RunCommand("target_lock", { targetMode = newMode })
        modeBtn.Text = "🎯 Modo: " .. (self.TargetMode == "NearestDistance" and "Distancia Más Cercana" or "Más Cercano al Cursor")
    end)

    -- 2. TARJETA RASTREADOR DE JUGADOR (PLAYER TRACKER)
    local trackerCard = Instance.new("Frame")
    trackerCard.Size = UDim2.new(0.95, 0, 0, 125)
    trackerCard.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    trackerCard.Parent = scroll

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 10)
    trackCorner.Parent = trackerCard

    local trackTitle = Instance.new("TextLabel")
    trackTitle.Size = UDim2.new(0, 200, 0, 30)
    trackTitle.Position = UDim2.new(0, 12, 0, 8)
    trackTitle.BackgroundTransparency = 1
    trackTitle.Text = "📡 <b>RASTREADOR ESP (JUGADORES)</b>"
    trackTitle.RichText = true
    trackTitle.Font = Enum.Font.GothamBold
    trackTitle.TextSize = 13
    trackTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    trackTitle.TextXAlignment = Enum.TextXAlignment.Left
    trackTitle.Parent = trackerCard

    local trackToggle = Instance.new("TextButton")
    trackToggle.Size = UDim2.new(0, 70, 0, 28)
    trackToggle.Position = UDim2.new(1, -82, 0, 8)
    trackToggle.BackgroundColor3 = self.TrackerEnabled and Color3.fromRGB(0, 240, 255) or Color3.fromRGB(45, 38, 80)
    trackToggle.Text = self.TrackerEnabled and "ON" or "OFF"
    trackToggle.Font = Enum.Font.GothamBold
    trackToggle.TextSize = 13
    trackToggle.TextColor3 = self.TrackerEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    trackToggle.Parent = trackerCard

    Instance.new("UICorner", trackToggle).CornerRadius = UDim.new(0, 14)

    local metricsText = Instance.new("TextLabel")
    metricsText.Size = UDim2.new(0.95, 0, 0, 75)
    metricsText.Position = UDim2.new(0, 12, 0, 44)
    metricsText.BackgroundTransparency = 1
    metricsText.Text = "Distancia: <b>-- m</b> (-- studs)<br/>Posición X, Y, Z: <b>(0, 0, 0)</b><br/>Salud Objetivo: <b>-- %</b>"
    metricsText.RichText = true
    metricsText.Font = Enum.Font.Gotham
    metricsText.TextSize = 12
    metricsText.TextColor3 = Color3.fromRGB(200, 200, 200)
    metricsText.TextXAlignment = Enum.TextXAlignment.Left
    metricsText.Parent = trackerCard

    trackToggle.MouseButton1Click:Connect(function()
        local newState = not self.TrackerEnabled
        self:RunCommand("player_tracker", { enabled = newState })
        
        trackToggle.BackgroundColor3 = self.TrackerEnabled and Color3.fromRGB(0, 240, 255) or Color3.fromRGB(45, 38, 80)
        trackToggle.Text = self.TrackerEnabled and "ON" or "OFF"
        trackToggle.TextColor3 = self.TrackerEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    end)

    Services.RunService.Heartbeat:Connect(function()
        if self.TrackerEnabled and self.TrackedData and metricsText and metricsText.Parent then
            local data = self.TrackedData
            metricsText.Text = string.format(
                "Distancia: <font color='#00FF66'><b>%d m</b> (%d studs)</font><br/>Posición X, Y, Z: <b>(%d, %d, %d)</b><br/>Salud Objetivo: <font color='#FF2400'><b>%d%%</b></font>",
                data.Meters or 0, data.Studs or 0,
                math.floor(data.Position.X or 0), math.floor(data.Position.Y or 0), math.floor(data.Position.Z or 0),
                data.Health or 100
            )
        end
    end)
end

function VortexHub:BuildUI()
    local parentGui = nil
    if gethui then
        pcall(function() parentGui = gethui() end)
    end
    if not parentGui then
        pcall(function() parentGui = Services.CoreGui end)
    end
    if not parentGui then
        parentGui = LocalPlayer:WaitForChild("PlayerGui")
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = "VortexHubScreenGui"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 9999
    screen.Parent = parentGui

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "VortexLogoButton"
    toggleBtn.Size = UDim2.new(0, 60, 0, 60)
    toggleBtn.Position = UDim2.new(0, 20, 0.25, 0)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    toggleBtn.BackgroundTransparency = 0.1
    toggleBtn.Text = "🌀"
    toggleBtn.TextSize = 28
    toggleBtn.TextColor3 = Color3.fromRGB(240, 200, 255)
    toggleBtn.Parent = screen

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(1, 0)
    btnCorner.Parent = toggleBtn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Thickness = 2.5
    btnStroke.Color = Color3.fromRGB(255, 255, 255)
    btnStroke.Parent = toggleBtn

    local strokeGradient = Instance.new("UIGradient")
    strokeGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 240, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(168, 85, 247)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 36, 0))
    })
    strokeGradient.Rotation = 45
    strokeGradient.Parent = btnStroke

    MakeDraggable(toggleBtn)

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "VortexMainFrame"
    mainFrame.Size = UDim2.new(0.75, 0, 0.78, 0)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.Visible = true
    mainFrame.Parent = screen

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 14)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Thickness = 2.5
    mainStroke.Color = self.AccentColor
    mainStroke.Parent = mainFrame
    table.insert(self.ThemeElements, mainStroke)

    toggleBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 45)
    header.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    header.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 14)
    headerCorner.Parent = header

    local titleContainer = Instance.new("Frame")
    titleContainer.Size = UDim2.new(0, 210, 0, 32)
    titleContainer.Position = UDim2.new(0, 10, 0.5, -16)
    titleContainer.BackgroundColor3 = Color3.fromRGB(30, 24, 56)
    titleContainer.Parent = header

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = titleContainer

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -16, 1, 0)
    titleText.Position = UDim2.new(0, 12, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "🌀 <b>VORTEXHUB</b>"
    titleText.RichText = true
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 16
    titleText.TextColor3 = Color3.fromRGB(240, 200, 255)
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleContainer

    local themeContainer = Instance.new("Frame")
    themeContainer.Size = UDim2.new(0, 160, 0, 30)
    themeContainer.Position = UDim2.new(1, -210, 0.5, -15)
    themeContainer.BackgroundTransparency = 1
    themeContainer.Parent = header

    local themeLayout = Instance.new("UIListLayout")
    themeLayout.FillDirection = Enum.FillDirection.Horizontal
    themeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    themeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    themeLayout.Padding = UDim.new(0, 6)
    themeLayout.Parent = themeContainer

    for themeName, color in pairs(self.Themes) do
        local dot = Instance.new("TextButton")
        dot.Size = UDim2.new(0, 18, 0, 18)
        dot.BackgroundColor3 = color
        dot.Text = ""
        dot.Parent = themeContainer
        
        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot

        dot.MouseButton1Click:Connect(function()
            self:SetAccentColor(color)
        end)
    end

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -38, 0.5, -15)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    closeBtn.TextSize = 18
    closeBtn.Parent = header
    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
    end)

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0.25, 0, 1, -45)
    sidebar.Position = UDim2.new(0, 0, 0, 45)
    sidebar.BackgroundColor3 = Color3.fromRGB(18, 14, 34)
    sidebar.Parent = mainFrame

    local sideLayout = Instance.new("UIListLayout")
    sideLayout.Padding = UDim.new(0, 8)
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sideLayout.Parent = sidebar

    local sidePad = Instance.new("UIPadding")
    sidePad.PaddingTop = UDim.new(0, 12)
    sidePad.Parent = sidebar

    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(0.75, 0, 1, -45)
    contentArea.Position = UDim2.new(0.25, 0, 0, 45)
    contentArea.BackgroundTransparency = 1
    contentArea.Parent = mainFrame

    local combatTabBtn = Instance.new("TextButton")
    combatTabBtn.Size = UDim2.new(0.88, 0, 0, 42)
    combatTabBtn.BackgroundColor3 = Color3.fromRGB(35, 28, 65)
    combatTabBtn.Text = "🎯 Combat"
    combatTabBtn.Font = Enum.Font.GothamBold
    combatTabBtn.TextSize = 14
    combatTabBtn.TextColor3 = Color3.fromRGB(240, 200, 255)
    combatTabBtn.Parent = sidebar

    local tabCorner = Instance.new("UICorner")
    tabCorner.CornerRadius = UDim.new(0, 8)
    tabCorner.Parent = combatTabBtn

    combatTabBtn.MouseButton1Click:Connect(function()
        self:RenderCombatCategory(contentArea)
    end)

    MakeDraggable(mainFrame, header)
    self:RenderCombatCategory(contentArea)
    print("[VortexHub] UI montada.")
end

--------------------------------------------------------------------------------
-- 7. INICIALIZACIÓN
--------------------------------------------------------------------------------

VortexHub:BuildUI()

if getgenv then
    getgenv().VortexHubLoaded = true
    getgenv().VortexHub = VortexHub
end

print("[VortexHub] Motor de Auto-Aim Cargado y Listo.")
return VortexHub
