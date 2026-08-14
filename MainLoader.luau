--[[
    VortexHub MainLoader.luau - Monolítico Universal Optimizado
    - Orientación fluida del personaje en RenderStepped para conectar 100% de ataques melee, espadas y habilidades.
    - Metamethods de Mouse.Hit, ReplicatedStorage.Mouse, Raycasts y RegisterHit.
    - SafeZone Cache O(1) y PvP Check ultra ligero por atributos sin bloqueos de interfaz.
    - Transición instantánea y sin congelamientos al alternar filtros de Jugadores y NPCs.
    
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
-- 1. MOTOR DE AUTO-AIM & SILENT AIM
--------------------------------------------------------------------------------

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

-- Cacheo de SafeZones & Spawns para eliminar consultas repetitivas de Workspace
local SafeZoneCache = { Zones = {}, Spawns = {}, LastUpdate = 0 }

local function UpdateSafeZoneCache()
    local now = tick()
    if now - SafeZoneCache.LastUpdate < 5 then return end
    SafeZoneCache.LastUpdate = now

    local zones = {}
    local spawns = {}
    pcall(function()
        local wo = Services.Workspace:FindFirstChild("_WorldOrigin")
        if wo then
            local sz = wo:FindFirstChild("SafeZones")
            if sz then
                for _, zone in ipairs(sz:GetChildren()) do
                    local mesh = zone:FindFirstChild("Mesh") or zone:FindFirstChildOfClass("SpecialMesh")
                    local scale = mesh and mesh.Scale.X or 1
                    local radius = (zone.Size.X * scale) / 2
                    if radius > 0 then
                        table.insert(zones, { Pos = zone.Position, Radius = radius })
                    end
                end
            end
            local ps = wo:FindFirstChild("PlayerSpawns")
            if ps then
                for _, folder in ipairs(ps:GetChildren()) do
                    for _, sp in ipairs(folder:GetChildren()) do
                        local part = sp:FindFirstChild("Part") or (sp:IsA("BasePart") and sp)
                        if part then
                            table.insert(spawns, part.Position)
                        end
                    end
                end
            end
        end
    end)
    SafeZoneCache.Zones = zones
    SafeZoneCache.Spawns = spawns
end

local function AX_InSafeZone(target)
    if not target then return false end
    local char = target.Character or target
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"))
    if not hrp then return false end

    UpdateSafeZoneCache()
    local pos = hrp.Position

    for _, z in ipairs(SafeZoneCache.Zones) do
        if (pos - z.Pos).Magnitude <= z.Radius then
            return true
        end
    end
    for _, spPos in ipairs(SafeZoneCache.Spawns) do
        if (pos - spPos).Magnitude <= 350 then
            return true
        end
    end
    return false
end

-- PvP Check Ultrarrápido y Libre de Bloqueos
local function AX_ReadPvPState(target)
    if not target or not target:IsA("Player") then return true end
    local ok, disabled = pcall(function()
        return target:GetAttribute("PvpDisabled") == true
    end)
    if ok and disabled then return false end
    return true
end

local function IsSilentAimAlly(p)
    local main = LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("Main")
    local frame = main and main:FindFirstChild("Allies")
        and main.Allies:FindFirstChild("Container")
        and main.Allies.Container:FindFirstChild("Allies")
        and main.Allies.Container.Allies:FindFirstChild("ScrollingFrame")
        and main.Allies.Container.Allies.ScrollingFrame:FindFirstChild("Frame")
    if not frame then return false end
    return frame:FindFirstChild(p.Name) ~= nil
end

local function IsSilentAimEnemy(p)
    if not p or p == LocalPlayer then return false end
    if IsSilentAimAlly(p) then return false end
    local myTeam, targetTeam = LocalPlayer.Team, p.Team
    if myTeam and targetTeam and myTeam.Name == "Marines" and targetTeam.Name == "Marines" then
        return false
    end
    return true
end

local function GetClosestTargetToCenter()
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end

    local maxDist3D = maxRange or 3500

    -- 1. Objetivo Específico Seleccionado
    if _G.G_SilentAimSelectedPlayer and _G.G_SilentAimSelectedPlayer ~= "" and _G.G_SilentAimSelectedPlayer ~= "Nearest" and _G.G_SilentAimSelectedPlayer ~= "Más Cercano" then
        local targetP = Services.Players:FindFirstChild(_G.G_SilentAimSelectedPlayer)
        if targetP and targetP ~= LocalPlayer and targetP.Character and not BlacklistedPlayers[targetP.Name] then
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
            local p = Services.Players:GetPlayerFromCharacter(character)
            if not p or p == LocalPlayer or BlacklistedPlayers[p.Name] then return end
            if _G.G_AimbotPvPCheck and not AX_ReadPvPState(p) then return end
            if _G.G_AimbotSafeZoneCheck and AX_InSafeZone(p) then return end
            if _G.G_SilentAimTeamCheck and not IsSilentAimEnemy(p) then return end
        else
            if _G.G_AimbotSafeZoneCheck and AX_InSafeZone(character) then return end
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
        for _, p in ipairs(Services.Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                checkTargetPart(p.Character, true)
            end
        end
    end

    -- 3. Escaneo Focalizado de NPCs/Mobs
    if _G.G_SilentAimTargetMobs then
        local enemies = Services.Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, enemy in ipairs(enemies:GetChildren()) do
                checkTargetPart(enemy, false)
            end
        else
            for _, folderName in ipairs({"NPCs", "Mobs", "Live", "Characters"}) do
                local f = Services.Workspace:FindFirstChild(folderName)
                if f then
                    for _, enemy in ipairs(f:GetChildren()) do
                        checkTargetPart(enemy, false)
                    end
                end
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

-- Bucle Asíncrono Atenuado a 0.10s (Búsqueda continua y Highlight)
task.spawn(function()
    while true do
        task.wait(0.10)
        if _G.G_SilentAimSkill then
            pcall(function()
                currentSilentAimTarget = GetClosestTargetToCenter()

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
            end)
        else
            currentSilentAimTarget = nil
            updateTargetHighlight(nil)
        end
    end
end)

-- Orientación horizontal automática del personaje (Garantiza impacto de Melee, Espadas y Frutas)
Services.RunService.RenderStepped:Connect(function()
    if _G.G_SilentAimSkill and currentSilentAimTarget then
        local myChar = LocalPlayer and LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if myRoot and currentSilentAimTarget and currentSilentAimTarget.Parent then
            local targetPos = currentSilentAimTarget.Position
            local lookAt = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
            myRoot.CFrame = CFrame.new(myRoot.Position, lookAt)
        end
    end
end)

-- ReplicatedStorage.Mouse Metatable Hook
local MouseModuleInstance = Services.ReplicatedStorage:FindFirstChild("Mouse")
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
            if key == "Hit" or key == "hit" then
                if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then
                    return CFrame.new(currentSilentAimTarget.Position)
                end
                return realStore.Hit
            elseif key == "Target" or key == "target" then
                if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then
                    return currentSilentAimTarget
                end
                return realStore.Target
            end
        end
        mmt.__newindex = function(self, key, value)
            if key == "Hit" or key == "Target" or key == "hit" or key == "target" then 
                realStore[key] = value 
            else 
                rawset(self, key, value) 
            end
        end
        setreadonly(mmt, true)
    end)
end

-- Global Metamethod Hooks (hookmetamethod & getrawmetatable)
local oldIndex = nil
local oldNamecall = nil

if hookmetamethod then
    pcall(function()
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if not checkcaller() then
                if self == Mouse and (key == "Hit" or key == "hit" or key == "Target" or key == "target") then
                    if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then
                        if key == "Hit" or key == "hit" then return CFrame.new(currentSilentAimTarget.Position) end
                        if key == "Target" or key == "target" then return currentSilentAimTarget end
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

                        for i, arg in ipairs(args) do
                            if typeof(arg) == "Vector3" then 
                                args[i] = activePos
                            elseif typeof(arg) == "CFrame" then 
                                args[i] = CFrame.new(activePos)
                            end
                        end
                        return oldNamecall(self, unpack(args))
                    end
                elseif (method == "raycast" or method == "findpartonray" or method == "findpartonraywithignorelist" or method == "findpartonraywithwhitelist") then
                    if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then
                        if method == "raycast" then
                            return {
                                Instance = currentSilentAimTarget,
                                Position = currentSilentAimTarget.Position,
                                Hit = currentSilentAimTarget.Position,
                                Normal = Vector3.new(0, 1, 0),
                                Material = Enum.Material.SmoothPlastic
                            }
                        else
                            return currentSilentAimTarget, currentSilentAimTarget.Position, Vector3.new(0, 1, 0), Enum.Material.SmoothPlastic
                        end
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
                if not checkcaller() and self == Mouse and (key == "Hit" or key == "hit" or key == "Target" or key == "target") then
                    if _G.G_SilentAimSkill and currentSilentAimTarget and IsCurrentToolAimbotAllowed() and IsCurrentSlotAimbotAllowed() then
                        if key == "Hit" or key == "hit" then return CFrame.new(currentSilentAimTarget.Position) end
                        if key == "Target" or key == "target" then return currentSilentAimTarget end
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

--------------------------------------------------------------------------------
-- 2. MÓDULO PLAYER TRACKER (Etiqueta ESP Compacta)
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
-- 3. REGISTRO ESTRUCTURAL DE COMANDOS
--------------------------------------------------------------------------------

VortexHub.Commands["target_lock"] = function(args)
    if typeof(args) == "table" then
        if args.enabled ~= nil then
            _G.G_SilentAimSkill = args.enabled
            if not args.enabled then
                currentSilentAimTarget = nil
                updateTargetHighlight(nil)
            end
        end
        if args.targetPlayers ~= nil then
            _G.G_SilentAimTargetPlayers = args.targetPlayers
            currentSilentAimTarget = nil
            updateTargetHighlight(nil)
        end
        if args.targetNPCs ~= nil then
            _G.G_SilentAimTargetMobs = args.targetNPCs
            currentSilentAimTarget = nil
            updateTargetHighlight(nil)
        end
        if args.targetPart then _G.G_SilentAimPart = args.targetPart end
        if args.playerHighlight ~= nil then
            _G.G_PlayerHighlight = args.playerHighlight
            if not args.playerHighlight then updateTargetHighlight(nil) end
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

        if not found and currentSilentAimTarget then
            local p = Services.Players:GetPlayerFromCharacter(currentSilentAimTarget.Parent)
            if p and p ~= LocalPlayer then
                found = p
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
-- 4. INTERFAZ GRÁFICA MÓVIL (PESTAÑA COMBAT)
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
    aimToggle.BackgroundColor3 = _G.G_SilentAimSkill and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
    aimToggle.Text = _G.G_SilentAimSkill and "ON" or "OFF"
    aimToggle.Font = Enum.Font.GothamBold
    aimToggle.TextSize = 13
    aimToggle.TextColor3 = _G.G_SilentAimSkill and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    aimToggle.Parent = aimCard

    Instance.new("UICorner", aimToggle).CornerRadius = UDim.new(0, 14)

    aimToggle.MouseButton1Click:Connect(function()
        _G.G_SilentAimSkill = not _G.G_SilentAimSkill
        if not _G.G_SilentAimSkill then
            currentSilentAimTarget = nil
            updateTargetHighlight(nil)
        end
        aimToggle.BackgroundColor3 = _G.G_SilentAimSkill and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
        aimToggle.Text = _G.G_SilentAimSkill and "ON" or "OFF"
        aimToggle.TextColor3 = _G.G_SilentAimSkill and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
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
    playersToggle.BackgroundColor3 = _G.G_SilentAimTargetPlayers and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
    playersToggle.Text = "👥 Jugadores: " .. (_G.G_SilentAimTargetPlayers and "SI" or "NO")
    playersToggle.Font = Enum.Font.GothamMedium
    playersToggle.TextSize = 11.5
    playersToggle.TextColor3 = Color3.fromRGB(240, 200, 255)
    playersToggle.Parent = aimCard

    Instance.new("UICorner", playersToggle).CornerRadius = UDim.new(0, 6)

    playersToggle.MouseButton1Click:Connect(function()
        _G.G_SilentAimTargetPlayers = not _G.G_SilentAimTargetPlayers
        currentSilentAimTarget = nil
        updateTargetHighlight(nil)
        playersToggle.BackgroundColor3 = _G.G_SilentAimTargetPlayers and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
        playersToggle.Text = "👥 Jugadores: " .. (_G.G_SilentAimTargetPlayers and "SI" or "NO")
    end)

    local npcsToggle = Instance.new("TextButton")
    npcsToggle.Size = UDim2.new(0.44, 0, 0, 30)
    npcsToggle.Position = UDim2.new(0.51, 0, 0, 62)
    npcsToggle.BackgroundColor3 = _G.G_SilentAimTargetMobs and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
    npcsToggle.Text = "👾 NPCs/Mobs: " .. (_G.G_SilentAimTargetMobs and "SI" or "NO")
    npcsToggle.Font = Enum.Font.GothamMedium
    npcsToggle.TextSize = 11.5
    npcsToggle.TextColor3 = Color3.fromRGB(240, 200, 255)
    npcsToggle.Parent = aimCard

    Instance.new("UICorner", npcsToggle).CornerRadius = UDim.new(0, 6)

    npcsToggle.MouseButton1Click:Connect(function()
        _G.G_SilentAimTargetMobs = not _G.G_SilentAimTargetMobs
        currentSilentAimTarget = nil
        updateTargetHighlight(nil)
        npcsToggle.BackgroundColor3 = _G.G_SilentAimTargetMobs and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
        npcsToggle.Text = "👾 NPCs/Mobs: " .. (_G.G_SilentAimTargetMobs and "SI" or "NO")
    end)

    -- Selector de Parte a Impactar (HumanoidRootPart / Head)
    local partBtn = Instance.new("TextButton")
    partBtn.Size = UDim2.new(0.44, 0, 0, 30)
    partBtn.Position = UDim2.new(0, 12, 0, 100)
    partBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    partBtn.Text = "🎯 Parte: " .. (_G.G_SilentAimPart == "Head" and "Cabeza" or "Cuerpo")
    partBtn.Font = Enum.Font.GothamMedium
    partBtn.TextSize = 11
    partBtn.TextColor3 = Color3.fromRGB(0, 240, 255)
    partBtn.Parent = aimCard
    Instance.new("UICorner", partBtn).CornerRadius = UDim.new(0, 6)

    partBtn.MouseButton1Click:Connect(function()
        _G.G_SilentAimPart = (_G.G_SilentAimPart == "HumanoidRootPart") and "Head" or "HumanoidRootPart"
        currentSilentAimTarget = nil
        partBtn.Text = "🎯 Parte: " .. (_G.G_SilentAimPart == "Head" and "Cabeza" or "Cuerpo")
    end)

    -- Toggle PlayerHighlight (Rojo Puro)
    local highlightBtn = Instance.new("TextButton")
    highlightBtn.Size = UDim2.new(0.44, 0, 0, 30)
    highlightBtn.Position = UDim2.new(0.51, 0, 0, 100)
    highlightBtn.BackgroundColor3 = _G.G_PlayerHighlight and Color3.fromRGB(220, 30, 30) or Color3.fromRGB(15, 12, 28)
    highlightBtn.Text = "🔴 Highlight: " .. (_G.G_PlayerHighlight and "ON" or "OFF")
    highlightBtn.Font = Enum.Font.GothamMedium
    highlightBtn.TextSize = 11
    highlightBtn.TextColor3 = _G.G_PlayerHighlight and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    highlightBtn.Parent = aimCard
    Instance.new("UICorner", highlightBtn).CornerRadius = UDim.new(0, 6)

    highlightBtn.MouseButton1Click:Connect(function()
        _G.G_PlayerHighlight = not _G.G_PlayerHighlight
        if not _G.G_PlayerHighlight then updateTargetHighlight(nil) end
        highlightBtn.BackgroundColor3 = _G.G_PlayerHighlight and Color3.fromRGB(220, 30, 30) or Color3.fromRGB(15, 12, 28)
        highlightBtn.Text = "🔴 Highlight: " .. (_G.G_PlayerHighlight and "ON" or "OFF")
        highlightBtn.TextColor3 = _G.G_PlayerHighlight and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
    end)

    -- Selector de Objetivo Específico
    local targetSelectBtn = Instance.new("TextButton")
    targetSelectBtn.Size = UDim2.new(0.95, -24, 0, 32)
    targetSelectBtn.Position = UDim2.new(0, 12, 0, 140)
    targetSelectBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    targetSelectBtn.Text = "🎯 Objetivo: " .. (_G.G_SilentAimSelectedPlayer ~= "" and _G.G_SilentAimSelectedPlayer or "Más Cercano")
    targetSelectBtn.Font = Enum.Font.GothamMedium
    targetSelectBtn.TextSize = 11.5
    targetSelectBtn.TextColor3 = Color3.fromRGB(0, 240, 255)
    targetSelectBtn.Parent = aimCard
    Instance.new("UICorner", targetSelectBtn).CornerRadius = UDim.new(0, 6)

    targetSelectBtn.MouseButton1Click:Connect(function()
        local plist = {"Más Cercano"}
        for _, p in pairs(Services.Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(plist, p.Name) end
        end
        local currIdx = table.find(plist, _G.G_SilentAimSelectedPlayer) or 1
        local nextIdx = (currIdx % #plist) + 1
        _G.G_SilentAimSelectedPlayer = (plist[nextIdx] == "Más Cercano") and "" or plist[nextIdx]
        currentSilentAimTarget = nil
        targetSelectBtn.Text = "🎯 Objetivo: " .. plist[nextIdx]
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
-- 5. INICIALIZACIÓN
--------------------------------------------------------------------------------

VortexHub:BuildUI()

if getgenv then
    getgenv().VortexHubLoaded = true
    getgenv().VortexHub = VortexHub
end

print("[VortexHub] Motor de Auto-Aim Cargado y Listo.")
return VortexHub
