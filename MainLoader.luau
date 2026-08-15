--[[
    VortexHub MainLoader.luau - Monolítico Universal Optimizado
    - Filtrado Estricto de NPCs: Solo enemigos de combate (workspace.Enemies), excluye 100% tiendas y misiones.
    - Silent Aim Genuino: Libertad total de movimiento y cámara; el cuerpo NO se fuerza a mirar al objetivo.
    - Detección precisa de Jugadores (SafeZone corregida con radio real y ForceField check).
    - PlayerHighlight: Resaltado Rojo Puro.
    - Metamethods estables y seguros con hookmetamethod y checkcaller().
    - Cero crasheos y cero bloqueos de pantalla.
    
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

    -- UI State (Crimson Flagship Theme)
    AccentColor = Color3.fromRGB(255, 36, 56),
    ThemeElements = {},
    Themes = {
        Crimson = Color3.fromRGB(255, 36, 56),
        Cyan = Color3.fromRGB(0, 240, 255),
        Purple = Color3.fromRGB(168, 85, 247),
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
        local wo = Services.Workspace:FindFirstChild("_WorldOrigin")
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

    -- 3. Escaneo de Mobs / NPCs de Combate Exclusivamente (workspace.Enemies)
    if _G.G_SilentAimTargetMobs then
        local enemies = Services.Workspace:FindFirstChild("Enemies")
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

-- Bucle de RenderStepped con Silent Aim Genuino (Libertad total de movimiento)
Services.RunService.RenderStepped:Connect(function()
    pcall(function()
        if _G.G_SilentAimSkill then
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
        else
            currentSilentAimTarget = nil
            updateTargetHighlight(nil)
        end
    end)
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
                if self == Mouse and (key == "Hit" or key == "Target") then
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
                if not checkcaller() and self == Mouse and (key == "Hit" or key == "Target") then
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

local CyberAssetCache = {}
local function GetCyberAsset(fileName, url)
    if CyberAssetCache[fileName] then return CyberAssetCache[fileName] end
    local assetId = url
    pcall(function()
        if writefile and getcustomasset then
            if not isfile or not isfile(fileName) then
                local content = game:HttpGet(url)
                writefile(fileName, content)
            end
            if isfile and isfile(fileName) then
                assetId = getcustomasset(fileName)
            end
        end
    end)
    CyberAssetCache[fileName] = assetId
    return assetId
end

function VortexHub:SetAccentColor(color)
    self.AccentColor = color
    local hexColor = string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
    
    for _, item in ipairs(self.ThemeElements) do
        if item and item.Parent then
            if item:IsA("UIStroke") then
                item.Color = color
            elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
                if item:GetAttribute("IsThemeAccent") then
                    item.ImageColor3 = color
                end
            elseif item:IsA("TextLabel") or item:IsA("TextButton") then
                if item:GetAttribute("IsThemeAccent") then
                    item.TextColor3 = color
                end
                if item:GetAttribute("IsHeaderTitle") then
                    item.Text = "— <font color='#FFFFFF'><b>VORTEX</b></font><font color='" .. hexColor .. "'><b>HUB</b></font> —"
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

    local btnAsset = GetCyberAsset("cyber_button_v2.png", "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/cyber_button.png")

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = self.AccentColor
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = contentArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 10)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 6)
    padding.PaddingRight = UDim.new(0, 6)
    padding.Parent = scroll

    -- 1. TARJETA PRINCIPAL AUTO-AIM (TARGET LOCK)
    local aimCard = Instance.new("Frame")
    aimCard.Size = UDim2.new(1, 0, 0, 80)
    aimCard.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
    aimCard.BackgroundTransparency = 0.2
    aimCard.Parent = scroll

    local aimCorner = Instance.new("UICorner")
    aimCorner.CornerRadius = UDim.new(0, 8)
    aimCorner.Parent = aimCard

    local aimStroke = Instance.new("UIStroke")
    aimStroke.Thickness = 1.2
    aimStroke.Color = Color3.fromRGB(48, 25, 38)
    aimStroke.Parent = aimCard

    local aimTitle = Instance.new("TextLabel")
    aimTitle.Size = UDim2.new(0.65, 0, 0, 24)
    aimTitle.Position = UDim2.new(0, 12, 0, 14)
    aimTitle.BackgroundTransparency = 1
    aimTitle.Text = "⚔️ <b>AUTO-AIM (TARGET LOCK)</b>"
    aimTitle.RichText = true
    aimTitle.Font = Enum.Font.GothamBold
    aimTitle.TextSize = 14
    aimTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    aimTitle.TextXAlignment = Enum.TextXAlignment.Left
    aimTitle.Parent = aimCard

    local aimSub = Instance.new("TextLabel")
    aimSub.Size = UDim2.new(0.65, 0, 0, 18)
    aimSub.Position = UDim2.new(0, 12, 0, 42)
    aimSub.BackgroundTransparency = 1
    aimSub.Text = "Silent Aim & Metamethod Redirection"
    aimSub.Font = Enum.Font.GothamMedium
    aimSub.TextSize = 11
    aimSub.TextColor3 = Color3.fromRGB(150, 155, 170)
    aimSub.TextXAlignment = Enum.TextXAlignment.Left
    aimSub.Parent = aimCard

    -- Botón Chamfered Sci-Fi ON/OFF
    local aimToggle = Instance.new("ImageButton")
    aimToggle.Size = UDim2.new(0, 80, 0, 34)
    aimToggle.Position = UDim2.new(1, -92, 0.5, -17)
    aimToggle.BackgroundTransparency = 1
    aimToggle.Image = btnAsset
    aimToggle.ScaleType = Enum.ScaleType.Slice
    aimToggle.SliceCenter = Rect.new(28, 28, 100, 36)
    aimToggle.ImageColor3 = _G.G_SilentAimSkill and self.AccentColor or Color3.fromRGB(75, 80, 95)
    aimToggle:SetAttribute("IsThemeAccent", _G.G_SilentAimSkill)
    aimToggle.Parent = aimCard
    table.insert(self.ThemeElements, aimToggle)

    local aimToggleLabel = Instance.new("TextLabel")
    aimToggleLabel.Size = UDim2.new(1, 0, 1, 0)
    aimToggleLabel.BackgroundTransparency = 1
    aimToggleLabel.Text = _G.G_SilentAimSkill and "ON" or "OFF"
    aimToggleLabel.Font = Enum.Font.GothamBold
    aimToggleLabel.TextSize = 13
    aimToggleLabel.TextColor3 = _G.G_SilentAimSkill and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 185, 195)
    aimToggleLabel.Parent = aimToggle

    aimToggle.MouseButton1Click:Connect(function()
        _G.G_SilentAimSkill = not _G.G_SilentAimSkill
        if not _G.G_SilentAimSkill then
            currentSilentAimTarget = nil
            updateTargetHighlight(nil)
        end
        aimToggle.ImageColor3 = _G.G_SilentAimSkill and self.AccentColor or Color3.fromRGB(75, 80, 95)
        aimToggle:SetAttribute("IsThemeAccent", _G.G_SilentAimSkill)
        aimToggleLabel.Text = _G.G_SilentAimSkill and "ON" or "OFF"
        aimToggleLabel.TextColor3 = _G.G_SilentAimSkill and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 185, 195)
    end)

    -- 2. TARJETA FILTROS DE COMBATE (CHAMFERED BUTTONS)
    local filterCard = Instance.new("Frame")
    filterCard.Size = UDim2.new(1, 0, 0, 126)
    filterCard.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
    filterCard.BackgroundTransparency = 0.2
    filterCard.Parent = scroll

    local filterCorner = Instance.new("UICorner")
    filterCorner.CornerRadius = UDim.new(0, 8)
    filterCorner.Parent = filterCard

    local filterStroke = Instance.new("UIStroke")
    filterStroke.Thickness = 1.2
    filterStroke.Color = Color3.fromRGB(48, 25, 38)
    filterStroke.Parent = filterCard

    local filterTitle = Instance.new("TextLabel")
    filterTitle.Size = UDim2.new(1, -24, 0, 22)
    filterTitle.Position = UDim2.new(0, 12, 0, 10)
    filterTitle.BackgroundTransparency = 1
    filterTitle.Text = "🎯 <b>FILTROS DE COMBATE</b>"
    filterTitle.RichText = true
    filterTitle.Font = Enum.Font.GothamBold
    filterTitle.TextSize = 13
    filterTitle.TextColor3 = Color3.fromRGB(240, 200, 255)
    filterTitle.TextXAlignment = Enum.TextXAlignment.Left
    filterTitle.Parent = filterCard

    -- Players Toggle Button (Chamfered)
    local playersToggle = Instance.new("ImageButton")
    playersToggle.Size = UDim2.new(0.48, -4, 0, 34)
    playersToggle.Position = UDim2.new(0, 10, 0, 38)
    playersToggle.BackgroundTransparency = 1
    playersToggle.Image = btnAsset
    playersToggle.ScaleType = Enum.ScaleType.Slice
    playersToggle.SliceCenter = Rect.new(28, 28, 100, 36)
    playersToggle.ImageColor3 = _G.G_SilentAimTargetPlayers and self.AccentColor or Color3.fromRGB(75, 80, 95)
    playersToggle:SetAttribute("IsThemeAccent", _G.G_SilentAimTargetPlayers)
    playersToggle.Parent = filterCard
    table.insert(self.ThemeElements, playersToggle)

    local playersLabel = Instance.new("TextLabel")
    playersLabel.Size = UDim2.new(1, 0, 1, 0)
    playersLabel.BackgroundTransparency = 1
    playersLabel.Text = "👥 Jugadores: " .. (_G.G_SilentAimTargetPlayers and "SI" or "NO")
    playersLabel.Font = Enum.Font.GothamMedium
    playersLabel.TextSize = 11.5
    playersLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    playersLabel.Parent = playersToggle

    playersToggle.MouseButton1Click:Connect(function()
        _G.G_SilentAimTargetPlayers = not _G.G_SilentAimTargetPlayers
        currentSilentAimTarget = nil
        updateTargetHighlight(nil)
        playersToggle.ImageColor3 = _G.G_SilentAimTargetPlayers and self.AccentColor or Color3.fromRGB(75, 80, 95)
        playersToggle:SetAttribute("IsThemeAccent", _G.G_SilentAimTargetPlayers)
        playersLabel.Text = "👥 Jugadores: " .. (_G.G_SilentAimTargetPlayers and "SI" or "NO")
    end)

    -- NPCs Toggle Button (Chamfered)
    local npcsToggle = Instance.new("ImageButton")
    npcsToggle.Size = UDim2.new(0.48, -4, 0, 34)
    npcsToggle.Position = UDim2.new(0.52, 0, 0, 38)
    npcsToggle.BackgroundTransparency = 1
    npcsToggle.Image = btnAsset
    npcsToggle.ScaleType = Enum.ScaleType.Slice
    npcsToggle.SliceCenter = Rect.new(28, 28, 100, 36)
    npcsToggle.ImageColor3 = _G.G_SilentAimTargetMobs and self.AccentColor or Color3.fromRGB(75, 80, 95)
    npcsToggle:SetAttribute("IsThemeAccent", _G.G_SilentAimTargetMobs)
    npcsToggle.Parent = filterCard
    table.insert(self.ThemeElements, npcsToggle)

    local npcsLabel = Instance.new("TextLabel")
    npcsLabel.Size = UDim2.new(1, 0, 1, 0)
    npcsLabel.BackgroundTransparency = 1
    npcsLabel.Text = "👾 NPCs/Mobs: " .. (_G.G_SilentAimTargetMobs and "SI" or "NO")
    npcsLabel.Font = Enum.Font.GothamMedium
    npcsLabel.TextSize = 11.5
    npcsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    npcsLabel.Parent = npcsToggle

    npcsToggle.MouseButton1Click:Connect(function()
        _G.G_SilentAimTargetMobs = not _G.G_SilentAimTargetMobs
        currentSilentAimTarget = nil
        updateTargetHighlight(nil)
        npcsToggle.ImageColor3 = _G.G_SilentAimTargetMobs and self.AccentColor or Color3.fromRGB(75, 80, 95)
        npcsToggle:SetAttribute("IsThemeAccent", _G.G_SilentAimTargetMobs)
        npcsLabel.Text = "👾 NPCs/Mobs: " .. (_G.G_SilentAimTargetMobs and "SI" or "NO")
    end)

    -- Part Toggle Button (Chamfered)
    local partBtn = Instance.new("ImageButton")
    partBtn.Size = UDim2.new(0.48, -4, 0, 34)
    partBtn.Position = UDim2.new(0, 10, 0, 80)
    partBtn.BackgroundTransparency = 1
    partBtn.Image = btnAsset
    partBtn.ScaleType = Enum.ScaleType.Slice
    partBtn.SliceCenter = Rect.new(28, 28, 100, 36)
    partBtn.ImageColor3 = Color3.fromRGB(0, 200, 230)
    partBtn.Parent = filterCard

    local partLabel = Instance.new("TextLabel")
    partLabel.Size = UDim2.new(1, 0, 1, 0)
    partLabel.BackgroundTransparency = 1
    partLabel.Text = "🎯 Parte: " .. (_G.G_SilentAimPart == "Head" and "Cabeza" or "Cuerpo")
    partLabel.Font = Enum.Font.GothamMedium
    partLabel.TextSize = 11.5
    partLabel.TextColor3 = Color3.fromRGB(0, 240, 255)
    partLabel.Parent = partBtn

    partBtn.MouseButton1Click:Connect(function()
        _G.G_SilentAimPart = (_G.G_SilentAimPart == "HumanoidRootPart") and "Head" or "HumanoidRootPart"
        currentSilentAimTarget = nil
        partLabel.Text = "🎯 Parte: " .. (_G.G_SilentAimPart == "Head" and "Cabeza" or "Cuerpo")
    end)

    -- Highlight Toggle Button (Chamfered)
    local highlightBtn = Instance.new("ImageButton")
    highlightBtn.Size = UDim2.new(0.48, -4, 0, 34)
    highlightBtn.Position = UDim2.new(0.52, 0, 0, 80)
    highlightBtn.BackgroundTransparency = 1
    highlightBtn.Image = btnAsset
    highlightBtn.ScaleType = Enum.ScaleType.Slice
    highlightBtn.SliceCenter = Rect.new(28, 28, 100, 36)
    highlightBtn.ImageColor3 = _G.G_PlayerHighlight and self.AccentColor or Color3.fromRGB(75, 80, 95)
    highlightBtn:SetAttribute("IsThemeAccent", _G.G_PlayerHighlight)
    highlightBtn.Parent = filterCard
    table.insert(self.ThemeElements, highlightBtn)

    local highlightLabel = Instance.new("TextLabel")
    highlightLabel.Size = UDim2.new(1, 0, 1, 0)
    highlightLabel.BackgroundTransparency = 1
    highlightLabel.Text = "🔴 Highlight: " .. (_G.G_PlayerHighlight and "ON" or "OFF")
    highlightLabel.Font = Enum.Font.GothamMedium
    highlightLabel.TextSize = 11.5
    highlightLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    highlightLabel.Parent = highlightBtn

    highlightBtn.MouseButton1Click:Connect(function()
        _G.G_PlayerHighlight = not _G.G_PlayerHighlight
        if not _G.G_PlayerHighlight then updateTargetHighlight(nil) end
        highlightBtn.ImageColor3 = _G.G_PlayerHighlight and self.AccentColor or Color3.fromRGB(75, 80, 95)
        highlightBtn:SetAttribute("IsThemeAccent", _G.G_PlayerHighlight)
        highlightLabel.Text = "🔴 Highlight: " .. (_G.G_PlayerHighlight and "ON" or "OFF")
    end)

    -- 3. TARJETA SELECTOR DE OBJETIVO (CHAMFERED FULL WIDTH)
    local targetCard = Instance.new("Frame")
    targetCard.Size = UDim2.new(1, 0, 0, 84)
    targetCard.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
    targetCard.BackgroundTransparency = 0.2
    targetCard.Parent = scroll

    local targetCorner = Instance.new("UICorner")
    targetCorner.CornerRadius = UDim.new(0, 8)
    targetCorner.Parent = targetCard

    local targetStroke = Instance.new("UIStroke")
    targetStroke.Thickness = 1.2
    targetStroke.Color = Color3.fromRGB(48, 25, 38)
    targetStroke.Parent = targetCard

    local targetTitle = Instance.new("TextLabel")
    targetTitle.Size = UDim2.new(1, -24, 0, 22)
    targetTitle.Position = UDim2.new(0, 12, 0, 10)
    targetTitle.BackgroundTransparency = 1
    targetTitle.Text = "🎯 <b>OBJETIVO ESPECÍFICO</b>"
    targetTitle.RichText = true
    targetTitle.Font = Enum.Font.GothamBold
    targetTitle.TextSize = 13
    targetTitle.TextColor3 = Color3.fromRGB(240, 200, 255)
    targetTitle.TextXAlignment = Enum.TextXAlignment.Left
    targetTitle.Parent = targetCard

    local targetSelectBtn = Instance.new("ImageButton")
    targetSelectBtn.Size = UDim2.new(1, -20, 0, 36)
    targetSelectBtn.Position = UDim2.new(0, 10, 0, 38)
    targetSelectBtn.BackgroundTransparency = 1
    targetSelectBtn.Image = btnAsset
    targetSelectBtn.ScaleType = Enum.ScaleType.Slice
    targetSelectBtn.SliceCenter = Rect.new(28, 28, 100, 36)
    targetSelectBtn.ImageColor3 = Color3.fromRGB(60, 65, 80)
    targetSelectBtn.Parent = targetCard

    local targetSelectLabel = Instance.new("TextLabel")
    targetSelectLabel.Size = UDim2.new(1, 0, 1, 0)
    targetSelectLabel.BackgroundTransparency = 1
    targetSelectLabel.Text = "🎯 Objetivo: " .. (_G.G_SilentAimSelectedPlayer ~= "" and _G.G_SilentAimSelectedPlayer or "Más Cercano")
    targetSelectLabel.Font = Enum.Font.GothamMedium
    targetSelectLabel.TextSize = 12.5
    targetSelectLabel.TextColor3 = Color3.fromRGB(0, 240, 255)
    targetSelectLabel.Parent = targetSelectBtn

    targetSelectBtn.MouseButton1Click:Connect(function()
        local plist = {"Más Cercano"}
        for _, p in pairs(Services.Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(plist, p.Name) end
        end
        local currIdx = table.find(plist, _G.G_SilentAimSelectedPlayer) or 1
        local nextIdx = (currIdx % #plist) + 1
        _G.G_SilentAimSelectedPlayer = (plist[nextIdx] == "Más Cercano") and "" or plist[nextIdx]
        currentSilentAimTarget = nil
        targetSelectLabel.Text = "🎯 Objetivo: " .. plist[nextIdx]
    end)
end

function VortexHub:RenderAppearanceCategory(contentArea)
    if not contentArea then return end
    contentArea:ClearAllChildren()

    local btnAsset = GetCyberAsset("cyber_button_v2.png", "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/cyber_button.png")

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = self.AccentColor
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = contentArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 10)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 6)
    padding.PaddingRight = UDim.new(0, 6)
    padding.Parent = scroll

    -- 1. TARJETA TEMAS DE COLOR
    local themeCard = Instance.new("Frame")
    themeCard.Size = UDim2.new(1, 0, 0, 230)
    themeCard.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
    themeCard.BackgroundTransparency = 0.2
    themeCard.Parent = scroll

    local themeCorner = Instance.new("UICorner")
    themeCorner.CornerRadius = UDim.new(0, 8)
    themeCorner.Parent = themeCard

    local themeStroke = Instance.new("UIStroke")
    themeStroke.Thickness = 1.2
    themeStroke.Color = Color3.fromRGB(48, 25, 38)
    themeStroke.Parent = themeCard

    local themeTitle = Instance.new("TextLabel")
    themeTitle.Size = UDim2.new(1, -24, 0, 22)
    themeTitle.Position = UDim2.new(0, 12, 0, 10)
    themeTitle.BackgroundTransparency = 1
    themeTitle.Text = "🎨 <b>NEON THEME ACCENT</b>"
    themeTitle.RichText = true
    themeTitle.Font = Enum.Font.GothamBold
    themeTitle.TextSize = 13.5
    themeTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    themeTitle.TextXAlignment = Enum.TextXAlignment.Left
    themeTitle.Parent = themeCard

    local themeSub = Instance.new("TextLabel")
    themeSub.Size = UDim2.new(1, -24, 0, 18)
    themeSub.Position = UDim2.new(0, 12, 0, 32)
    themeSub.BackgroundTransparency = 1
    themeSub.Text = "Elige el color de acento del hub"
    themeSub.Font = Enum.Font.GothamMedium
    themeSub.TextSize = 11
    themeSub.TextColor3 = Color3.fromRGB(150, 155, 170)
    themeSub.TextXAlignment = Enum.TextXAlignment.Left
    themeSub.Parent = themeCard

    local themeList = {
        { name = "Crimson Flagship", color = self.Themes.Crimson, icon = "🔴" },
        { name = "Cyan Cyberpunk", color = self.Themes.Cyan, icon = "🔵" },
        { name = "Emerald Matrix", color = self.Themes.Emerald, icon = "🟢" },
        { name = "Neon Amethyst", color = self.Themes.Purple, icon = "🟣" },
        { name = "Solar Amber", color = self.Themes.Amber, icon = "🟡" },
    }

    local yPos = 54
    for _, t in ipairs(themeList) do
        local tBtn = Instance.new("ImageButton")
        tBtn.Size = UDim2.new(1, -20, 0, 30)
        tBtn.Position = UDim2.new(0, 10, 0, yPos)
        tBtn.BackgroundTransparency = 1
        tBtn.Image = btnAsset
        tBtn.ScaleType = Enum.ScaleType.Slice
        tBtn.SliceCenter = Rect.new(28, 28, 100, 36)
        tBtn.ImageColor3 = t.color
        tBtn.Parent = themeCard

        local tLabel = Instance.new("TextLabel")
        tLabel.Size = UDim2.new(1, 0, 1, 0)
        tLabel.BackgroundTransparency = 1
        tLabel.Text = t.icon .. "  " .. t.name
        tLabel.Font = Enum.Font.GothamBold
        tLabel.TextSize = 12
        tLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        tLabel.Parent = tBtn

        tBtn.MouseButton1Click:Connect(function()
            self:SetAccentColor(t.color)
        end)

        yPos = yPos + 34
    end

    -- 2. TARJETA VISIBILIDAD BOTÓN FLOTANTE
    local btnCard = Instance.new("Frame")
    btnCard.Size = UDim2.new(1, 0, 0, 84)
    btnCard.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
    btnCard.BackgroundTransparency = 0.2
    btnCard.Parent = scroll

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btnCard

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Thickness = 1.2
    btnStroke.Color = Color3.fromRGB(48, 25, 38)
    btnStroke.Parent = btnCard

    local btnTitle = Instance.new("TextLabel")
    btnTitle.Size = UDim2.new(1, -24, 0, 22)
    btnTitle.Position = UDim2.new(0, 12, 0, 10)
    btnTitle.BackgroundTransparency = 1
    btnTitle.Text = "🔘 <b>BOTÓN FLOTANTE VORTEX</b>"
    btnTitle.RichText = true
    btnTitle.Font = Enum.Font.GothamBold
    btnTitle.TextSize = 13
    btnTitle.TextColor3 = Color3.fromRGB(240, 200, 255)
    btnTitle.TextXAlignment = Enum.TextXAlignment.Left
    btnTitle.Parent = btnCard

    local toggleVisBtn = Instance.new("ImageButton")
    toggleVisBtn.Size = UDim2.new(1, -20, 0, 36)
    toggleVisBtn.Position = UDim2.new(0, 10, 0, 38)
    toggleVisBtn.BackgroundTransparency = 1
    toggleVisBtn.Image = btnAsset
    toggleVisBtn.ScaleType = Enum.ScaleType.Slice
    toggleVisBtn.SliceCenter = Rect.new(28, 28, 100, 36)
    toggleVisBtn.ImageColor3 = (self.ToggleButton and self.ToggleButton.Visible) and self.AccentColor or Color3.fromRGB(80, 85, 100)
    toggleVisBtn:SetAttribute("IsThemeAccent", (self.ToggleButton and self.ToggleButton.Visible))
    toggleVisBtn.Parent = btnCard
    table.insert(self.ThemeElements, toggleVisBtn)

    local toggleVisLabel = Instance.new("TextLabel")
    toggleVisLabel.Size = UDim2.new(1, 0, 1, 0)
    toggleVisLabel.BackgroundTransparency = 1
    toggleVisLabel.Text = (self.ToggleButton and self.ToggleButton.Visible) and "🔘 Botón Flotante: VISIBLE" or "🚫 Botón Flotante: OCULTO"
    toggleVisLabel.Font = Enum.Font.GothamMedium
    toggleVisLabel.TextSize = 12.5
    toggleVisLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleVisLabel.Parent = toggleVisBtn

    toggleVisBtn.MouseButton1Click:Connect(function()
        if self.ToggleButton then
            self.ToggleButton.Visible = not self.ToggleButton.Visible
            toggleVisBtn.ImageColor3 = self.ToggleButton.Visible and self.AccentColor or Color3.fromRGB(80, 85, 100)
            toggleVisBtn:SetAttribute("IsThemeAccent", self.ToggleButton.Visible)
            toggleVisLabel.Text = self.ToggleButton.Visible and "🔘 Botón Flotante: VISIBLE" or "🚫 Botón Flotante: OCULTO"
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

    local logoUrl = "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/vortex_logo.png"
    local logoAssetId = GetCyberAsset("vortex_logo_v3.png", logoUrl)

    local tabActiveAsset = GetCyberAsset("cyber_tab_active_v2.png", "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/cyber_tab_active.png")
    local btnAsset = GetCyberAsset("cyber_button_v2.png", "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/cyber_button.png")

    -- Draggable Floating Button
    local toggleBtn = Instance.new("ImageButton")
    toggleBtn.Name = "VortexLogoButton"
    toggleBtn.Size = UDim2.new(0, 51, 0, 51)
    toggleBtn.Position = UDim2.new(0, 20, 0.25, 0)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    toggleBtn.BackgroundTransparency = 0.1
    toggleBtn.AutoButtonColor = true
    toggleBtn.ClipsDescendants = true
    toggleBtn.Parent = screen
    self.ToggleButton = toggleBtn

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(1, 0)
    btnCorner.Parent = toggleBtn

    local logoImg = Instance.new("ImageLabel")
    logoImg.Name = "LogoImage"
    logoImg.Size = UDim2.new(1, 0, 1, 0)
    logoImg.Position = UDim2.new(0.5, 0, 0.5, 0)
    logoImg.AnchorPoint = Vector2.new(0.5, 0.5)
    logoImg.BackgroundTransparency = 1
    logoImg.Image = logoAssetId or logoUrl
    logoImg.ScaleType = Enum.ScaleType.Fit
    logoImg.Parent = toggleBtn

    local imgCorner = Instance.new("UICorner")
    imgCorner.CornerRadius = UDim.new(1, 0)
    imgCorner.Parent = logoImg

    local fallbackIcon = Instance.new("TextLabel")
    fallbackIcon.Name = "FallbackIcon"
    fallbackIcon.Size = UDim2.new(1, 0, 1, 0)
    fallbackIcon.BackgroundTransparency = 1
    fallbackIcon.Text = "🌀"
    fallbackIcon.TextSize = 24
    fallbackIcon.TextColor3 = Color3.fromRGB(240, 200, 255)
    fallbackIcon.Visible = (logoAssetId == nil and logoImg.Image == "")
    fallbackIcon.Parent = toggleBtn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Thickness = 2.2
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

    -- Main Hub Window (20% narrower width: 0.64, 10% taller height: 0.96)
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "VortexMainFrame"
    mainFrame.Size = UDim2.new(0.64, 0, 0.96, 0)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 16, 22)
    mainFrame.BackgroundTransparency = 0.05
    mainFrame.Visible = true
    mainFrame.Parent = screen

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Thickness = 2
    mainStroke.Color = self.AccentColor
    mainStroke.Parent = mainFrame
    table.insert(self.ThemeElements, mainStroke)

    toggleBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)

    -- Header Bar
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 42)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
    header.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header

    -- Título Centrado VORTEXHUB
    local titleContainer = Instance.new("Frame")
    titleContainer.Size = UDim2.new(0, 220, 0, 34)
    titleContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
    titleContainer.AnchorPoint = Vector2.new(0.5, 0.5)
    titleContainer.BackgroundTransparency = 1
    titleContainer.Parent = header

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, 0, 1, 0)
    titleText.Position = UDim2.new(0, 0, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.RichText = true
    titleText.Text = "— <font color='#FFFFFF'><b>VORTEX</b></font><font color='#FF2438'><b>HUB</b></font> —"
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 16.5
    titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleText.TextXAlignment = Enum.TextXAlignment.Center
    titleText:SetAttribute("IsHeaderTitle", true)
    titleText.Parent = titleContainer
    table.insert(self.ThemeElements, titleText)

    -- Hide / Minimize Button (Disappear floating button + close GUI, background features keep running)
    local hideBtn = Instance.new("ImageButton")
    hideBtn.Size = UDim2.new(0, 26, 0, 26)
    hideBtn.Position = UDim2.new(1, -66, 0.5, -13)
    hideBtn.BackgroundTransparency = 1
    hideBtn.Image = btnAsset
    hideBtn.ScaleType = Enum.ScaleType.Slice
    hideBtn.SliceCenter = Rect.new(28, 28, 100, 36)
    hideBtn.ImageColor3 = Color3.fromRGB(75, 80, 100)
    hideBtn.Parent = header

    local hideLabel = Instance.new("TextLabel")
    hideLabel.Size = UDim2.new(1, 0, 1, 0)
    hideLabel.BackgroundTransparency = 1
    hideLabel.Text = "—"
    hideLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
    hideLabel.Font = Enum.Font.GothamBold
    hideLabel.TextSize = 14
    hideLabel.Parent = hideBtn

    hideBtn.MouseButton1Click:Connect(function()
        toggleBtn.Visible = false
        mainFrame.Visible = false
    end)

    -- Close Button (Chamfered Red X)
    local closeBtn = Instance.new("ImageButton")
    closeBtn.Size = UDim2.new(0, 26, 0, 26)
    closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Image = btnAsset
    closeBtn.ScaleType = Enum.ScaleType.Slice
    closeBtn.SliceCenter = Rect.new(28, 28, 100, 36)
    closeBtn.ImageColor3 = Color3.fromRGB(255, 45, 45)
    closeBtn.Parent = header

    local closeLabel = Instance.new("TextLabel")
    closeLabel.Size = UDim2.new(1, 0, 1, 0)
    closeLabel.BackgroundTransparency = 1
    closeLabel.Text = "X"
    closeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeLabel.Font = Enum.Font.GothamBold
    closeLabel.TextSize = 12.5
    closeLabel.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
    end)

    -- Body Container (Below Header)
    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 1, -42)
    body.Position = UDim2.new(0, 0, 0, 42)
    body.BackgroundTransparency = 1
    body.Parent = mainFrame

    -- Left Sidebar (Tabs Container)
    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0.27, 0, 1, -14)
    sidebar.Position = UDim2.new(0, 7, 0, 7)
    sidebar.BackgroundColor3 = Color3.fromRGB(18, 19, 26)
    sidebar.Parent = body

    local sidebarCorner = Instance.new("UICorner")
    sidebarCorner.CornerRadius = UDim.new(0, 8)
    sidebarCorner.Parent = sidebar

    local sidebarStroke = Instance.new("UIStroke")
    sidebarStroke.Thickness = 1
    sidebarStroke.Color = Color3.fromRGB(36, 38, 50)
    sidebarStroke.Parent = sidebar

    local sideLayout = Instance.new("UIListLayout")
    sideLayout.Padding = UDim.new(0, 8)
    sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sideLayout.Parent = sidebar

    local sidePad = Instance.new("UIPadding")
    sidePad.PaddingTop = UDim.new(0, 10)
    sidePad.Parent = sidebar

    -- Right Content Sub-Window (Recessed Cyber Plate)
    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(0.70, 0, 1, -14)
    contentArea.Position = UDim2.new(0.285, 0, 0, 7)
    contentArea.BackgroundColor3 = Color3.fromRGB(12, 13, 18)
    contentArea.ClipsDescendants = true
    contentArea.Parent = body

    local contentCorner = Instance.new("UICorner")
    contentCorner.CornerRadius = UDim.new(0, 8)
    contentCorner.Parent = contentArea

    local contentStroke = Instance.new("UIStroke")
    contentStroke.Thickness = 1.6
    contentStroke.Color = self.AccentColor
    contentStroke.Parent = contentArea
    table.insert(self.ThemeElements, contentStroke)

    -- Tab 1: Combat Button
    local combatTabBtn = Instance.new("ImageButton")
    combatTabBtn.Size = UDim2.new(0.96, 6, 0, 42)
    combatTabBtn.BackgroundTransparency = 1
    combatTabBtn.Image = tabActiveAsset
    combatTabBtn.ScaleType = Enum.ScaleType.Slice
    combatTabBtn.SliceCenter = Rect.new(26, 24, 132, 40)
    combatTabBtn.ImageColor3 = self.AccentColor
    combatTabBtn:SetAttribute("IsThemeAccent", true)
    combatTabBtn.ZIndex = 5
    combatTabBtn.Parent = sidebar
    table.insert(self.ThemeElements, combatTabBtn)

    local combatTabLabel = Instance.new("TextLabel")
    combatTabLabel.Size = UDim2.new(1, -16, 1, 0)
    combatTabLabel.Position = UDim2.new(0, 8, 0, 0)
    combatTabLabel.BackgroundTransparency = 1
    combatTabLabel.Text = "⚔️  COMBAT"
    combatTabLabel.Font = Enum.Font.GothamBold
    combatTabLabel.TextSize = 12
    combatTabLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    combatTabLabel.TextXAlignment = Enum.TextXAlignment.Left
    combatTabLabel.ZIndex = 6
    combatTabLabel.Parent = combatTabBtn

    -- Tab 2: Appearance Button
    local appearanceTabBtn = Instance.new("ImageButton")
    appearanceTabBtn.Size = UDim2.new(0.96, 6, 0, 42)
    appearanceTabBtn.BackgroundTransparency = 0.3
    appearanceTabBtn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
    appearanceTabBtn.Image = ""
    appearanceTabBtn.ScaleType = Enum.ScaleType.Slice
    appearanceTabBtn.SliceCenter = Rect.new(26, 24, 132, 40)
    appearanceTabBtn.ImageColor3 = self.AccentColor
    appearanceTabBtn:SetAttribute("IsThemeAccent", false)
    appearanceTabBtn.ZIndex = 2
    appearanceTabBtn.Parent = sidebar
    Instance.new("UICorner", appearanceTabBtn).CornerRadius = UDim.new(0, 8)

    local appearanceTabLabel = Instance.new("TextLabel")
    appearanceTabLabel.Size = UDim2.new(1, -16, 1, 0)
    appearanceTabLabel.Position = UDim2.new(0, 8, 0, 0)
    appearanceTabLabel.BackgroundTransparency = 1
    appearanceTabLabel.Text = "🎨  APPEAR"
    appearanceTabLabel.Font = Enum.Font.GothamBold
    appearanceTabLabel.TextSize = 11.5
    appearanceTabLabel.TextColor3 = Color3.fromRGB(150, 155, 170)
    appearanceTabLabel.TextXAlignment = Enum.TextXAlignment.Left
    appearanceTabLabel.ZIndex = 6
    appearanceTabLabel.Parent = appearanceTabBtn

    local currentTab = "Combat"
    local function SwitchTab(tabName)
        currentTab = tabName
        if tabName == "Combat" then
            combatTabBtn.Image = tabActiveAsset
            combatTabBtn.BackgroundTransparency = 1
            combatTabBtn.ImageColor3 = self.AccentColor
            combatTabBtn:SetAttribute("IsThemeAccent", true)
            combatTabBtn.ZIndex = 5
            combatTabLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

            appearanceTabBtn.Image = ""
            appearanceTabBtn.BackgroundTransparency = 0.3
            appearanceTabBtn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
            appearanceTabBtn:SetAttribute("IsThemeAccent", false)
            appearanceTabBtn.ZIndex = 2
            appearanceTabLabel.TextColor3 = Color3.fromRGB(150, 155, 170)

            self:RenderCombatCategory(contentArea)
        else
            appearanceTabBtn.Image = tabActiveAsset
            appearanceTabBtn.BackgroundTransparency = 1
            appearanceTabBtn.ImageColor3 = self.AccentColor
            appearanceTabBtn:SetAttribute("IsThemeAccent", true)
            appearanceTabBtn.ZIndex = 5
            appearanceTabLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

            combatTabBtn.Image = ""
            combatTabBtn.BackgroundTransparency = 0.3
            combatTabBtn.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
            combatTabBtn:SetAttribute("IsThemeAccent", false)
            combatTabBtn.ZIndex = 2
            combatTabLabel.TextColor3 = Color3.fromRGB(150, 155, 170)

            self:RenderAppearanceCategory(contentArea)
        end
    end

    combatTabBtn.MouseButton1Click:Connect(function()
        SwitchTab("Combat")
    end)

    appearanceTabBtn.MouseButton1Click:Connect(function()
        SwitchTab("Appearance")
    end)

    -- Keyboard shortcut (RightShift / RightControl) to bring back UI if hidden
    Services.UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
            toggleBtn.Visible = true
            mainFrame.Visible = not mainFrame.Visible
        end
    end)

    MakeDraggable(mainFrame, header)
    self:RenderCombatCategory(contentArea)
    print("[VortexHub] UI Cybernetica con Pestaña Appearance Montada.")
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
