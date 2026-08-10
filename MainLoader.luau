--[[
    VortexHub MainLoader.luau - Motor Universal con Auto-Aim para Jugadores & NPCs
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
    Workspace = game:GetService("Workspace")
}

local LocalPlayer = Services.Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local function CleanOldUI()
    local oldGuis = {
        LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("VortexHubScreenGui"),
        pcall(function() return Services.CoreGui:FindFirstChild("VortexHubScreenGui") end) and Services.CoreGui:FindFirstChild("VortexHubScreenGui")
    }
    for _, gui in ipairs(oldGuis) do
        if gui and typeof(gui) == "Instance" then
            pcall(function() gui:Destroy() end)
        end
    end
end

CleanOldUI()

-- Entorno Global de VortexHub
local VortexHub = {
    Version = "1.0.0",
    Config = {},
    
    -- Target Lock State & Filters
    TargetLockEnabled = false,
    TargetPlayers = true,
    TargetNPCs = true,
    TargetMode = "NearestDistance", -- "NearestDistance", "NearestCursor", "Manual"
    ActiveTarget = nil,
    PredictMovement = true,
    PredictionLead = 0.12,
    
    Commands = {},
    
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
    }
}

--------------------------------------------------------------------------------
-- 1. MOTOR UNIVERSAL TARGET LOCK (JUGADORES & NPCS + HOOKS DE ATAQUES)
--------------------------------------------------------------------------------

local function IsValidNPC(model)
    if not model or not model:IsA("Model") then return false end
    if Services.Players:GetPlayerFromCharacter(model) then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
    return (hum and root and hum.Health > 0)
end

local function GetValidTargets()
    local targets = {}
    local myChar = LocalPlayer.Character

    if VortexHub.TargetPlayers then
        for _, player in ipairs(Services.Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                local hum = player.Character:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.Health > 0 then
                    table.insert(targets, { Instance = player, Character = player.Character, Root = root, IsPlayer = true })
                end
            end
        end
    end

    if VortexHub.TargetNPCs then
        for _, obj in ipairs(Services.Workspace:GetDescendants()) do
            if obj ~= myChar and IsValidNPC(obj) then
                local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj.PrimaryPart
                table.insert(targets, { Instance = obj, Character = obj, Root = root, IsPlayer = false })
            end
        end
    end

    return targets
end

local function GetNearestTargetByDistance()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local targets = GetValidTargets()
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

local function GetNearestTargetByCursor()
    local camera = Services.Workspace.CurrentCamera
    if not camera then return nil end

    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local targets = GetValidTargets()
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

local function GetTargetRootPart(target)
    if not target then return nil end
    if typeof(target) == "Instance" then
        if target:IsA("Player") and target.Character then
            return target.Character:FindFirstChild("HumanoidRootPart")
        elseif target:IsA("Model") then
            return target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso") or target.PrimaryPart
        end
    end
    return nil
end

local function GetTargetPosition()
    if not VortexHub.TargetLockEnabled then return nil end

    if VortexHub.TargetMode == "NearestDistance" then
        VortexHub.ActiveTarget = GetNearestTargetByDistance()
    elseif VortexHub.TargetMode == "NearestCursor" then
        VortexHub.ActiveTarget = GetNearestTargetByCursor()
    end

    local targetRoot = GetTargetRootPart(VortexHub.ActiveTarget)
    if not targetRoot then return nil end

    local targetPos = targetRoot.Position
    if VortexHub.PredictMovement and targetRoot:IsA("BasePart") then
        targetPos = targetPos + (targetRoot.AssemblyLinearVelocity * VortexHub.PredictionLead)
    end
    return targetPos
end

-- Orientar automáticamente el personaje hacia el objetivo para asegurar ataques meelee/habilidades
Services.RunService.RenderStepped:Connect(function()
    if VortexHub.TargetLockEnabled then
        local targetPos = GetTargetPosition()
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

        if targetPos and myRoot then
            local lookAt = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
            myRoot.CFrame = CFrame.new(myRoot.Position, lookAt)
        end
    end
end)

local function HookCombatRedirection()
    pcall(function()
        local gmt = getrawmetatable(game)
        if setreadonly then setreadonly(gmt, false) end
        local oldIndex = gmt.__index
        local oldNamecall = gmt.__namecall

        gmt.__index = newcclosure(function(selfInstance, key)
            if selfInstance == Mouse then
                if key == "Hit" or key == "hit" then
                    local targetPos = GetTargetPosition()
                    if targetPos then
                        return CFrame.new(targetPos)
                    end
                elseif key == "Target" or key == "target" then
                    local targetRoot = GetTargetRootPart(VortexHub.ActiveTarget)
                    if targetRoot then
                        return targetRoot
                    end
                end
            end
            return oldIndex(selfInstance, key)
        end)

        gmt.__namecall = newcclosure(function(selfInstance, ...)
            local method = getnamecallmethod()
            local args = {...}

            if VortexHub.TargetLockEnabled then
                local targetPos = GetTargetPosition()
                if targetPos then
                    if method == "Raycast" or method == "raycast" or method == "FindPartOnRay" then
                        local origin = args[1]
                        if typeof(origin) == "Vector3" then
                            args[2] = (targetPos - origin).Unit * 1000
                            return oldNamecall(selfInstance, unpack(args))
                        end
                    end

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
end

--------------------------------------------------------------------------------
-- 2. MÓDULO PLAYER TRACKER (Etiqueta Compacta Legible)
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
        if args.enabled ~= nil then VortexHub.TargetLockEnabled = args.enabled end
        if args.targetPlayers ~= nil then VortexHub.TargetPlayers = args.targetPlayers end
        if args.targetNPCs ~= nil then VortexHub.TargetNPCs = args.targetNPCs end
        if args.targetMode then VortexHub.TargetMode = args.targetMode end
        if args.predictionLead then VortexHub.PredictionLead = tonumber(args.predictionLead) or 0.12 end
    end
end

VortexHub.Commands["player_tracker"] = function(args)
    if typeof(args) == "table" then
        if args.enabled ~= nil then VortexHub.TrackerEnabled = args.enabled end
        if args.targetPlayer and args.targetPlayer ~= "" then
            local found = nil
            for _, player in ipairs(Services.Players:GetPlayers()) do
                if player ~= LocalPlayer and (player.Name:lower() == args.targetPlayer:lower() or player.DisplayName:lower() == args.targetPlayer:lower()) then
                    found = player
                    break
                end
            end
            VortexHub.TrackedPlayer = found
            if found and args.enabled ~= false then
                VortexHub.TrackerEnabled = true
                CreateTrackerMarker(found)
            end
        else
            VortexHub.TrackedPlayer = nil
            VortexHub.TrackerEnabled = false
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
-- 4. INTERFAZ GRÁFICA MÓVIL (PANEL COMBAT COMPLETO CON FILTROS Y MODOS)
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
    aimCard.Size = UDim2.new(0.95, 0, 0, 155)
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

    local aimToggleCorner = Instance.new("UICorner")
    aimToggleCorner.CornerRadius = UDim.new(0, 14)
    aimToggleCorner.Parent = aimToggle

    aimToggle.MouseButton1Click:Connect(function()
        self.TargetLockEnabled = not self.TargetLockEnabled
        aimToggle.BackgroundColor3 = self.TargetLockEnabled and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
        aimToggle.Text = self.TargetLockEnabled and "ON" or "OFF"
        aimToggle.TextColor3 = self.TargetLockEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    end)

    -- Filtros de Tipo de Objetivo (Jugadores / NPCs)
    local filterLabel = Instance.new("TextLabel")
    filterLabel.Size = UDim2.new(1, -24, 0, 20)
    filterLabel.Position = UDim2.new(0, 12, 0, 42)
    filterLabel.BackgroundTransparency = 1
    filterLabel.Text = "Tipo de Objetivo Aceptado:"
    filterLabel.Font = Enum.Font.GothamMedium
    filterLabel.TextSize = 12
    filterLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    filterLabel.TextXAlignment = Enum.TextXAlignment.Left
    filterLabel.Parent = aimCard

    -- Switch Jugadores
    local playersToggle = Instance.new("TextButton")
    playersToggle.Size = UDim2.new(0.44, 0, 0, 32)
    playersToggle.Position = UDim2.new(0, 12, 0, 66)
    playersToggle.BackgroundColor3 = self.TargetPlayers and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
    playersToggle.Text = "👥 Jugadores: " .. (self.TargetPlayers and "SI" or "NO")
    playersToggle.Font = Enum.Font.GothamMedium
    playersToggle.TextSize = 12
    playersToggle.TextColor3 = Color3.fromRGB(240, 200, 255)
    playersToggle.Parent = aimCard

    local pCorner = Instance.new("UICorner")
    pCorner.CornerRadius = UDim.new(0, 6)
    pCorner.Parent = playersToggle

    playersToggle.MouseButton1Click:Connect(function()
        self.TargetPlayers = not self.TargetPlayers
        playersToggle.BackgroundColor3 = self.TargetPlayers and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
        playersToggle.Text = "👥 Jugadores: " .. (self.TargetPlayers and "SI" or "NO")
    end)

    -- Switch NPCs / Mobs
    local npcsToggle = Instance.new("TextButton")
    npcsToggle.Size = UDim2.new(0.44, 0, 0, 32)
    npcsToggle.Position = UDim2.new(0.51, 0, 0, 66)
    npcsToggle.BackgroundColor3 = self.TargetNPCs and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
    npcsToggle.Text = "👾 NPCs / Mobs: " .. (self.TargetNPCs and "SI" or "NO")
    npcsToggle.Font = Enum.Font.GothamMedium
    npcsToggle.TextSize = 12
    npcsToggle.TextColor3 = Color3.fromRGB(240, 200, 255)
    npcsToggle.Parent = aimCard

    local npcCorner = Instance.new("UICorner")
    npcCorner.CornerRadius = UDim.new(0, 6)
    npcCorner.Parent = npcsToggle

    npcsToggle.MouseButton1Click:Connect(function()
        self.TargetNPCs = not self.TargetNPCs
        npcsToggle.BackgroundColor3 = self.TargetNPCs and Color3.fromRGB(138, 43, 226) or Color3.fromRGB(30, 24, 56)
        npcsToggle.Text = "👾 NPCs / Mobs: " .. (self.TargetNPCs and "SI" or "NO")
    end)

    -- Selector de Modo de Fijado (Más cercano / Cursor)
    local modeBtn = Instance.new("TextButton")
    modeBtn.Size = UDim2.new(0.95, -24, 0, 32)
    modeBtn.Position = UDim2.new(0, 12, 0, 108)
    modeBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    modeBtn.Text = "Modo: " .. (self.TargetMode == "NearestDistance" and "⚡ Objetivo Más Cercano (3D)" or "🎯 Cercano al Cursor")
    modeBtn.Font = Enum.Font.GothamMedium
    modeBtn.TextSize = 12
    modeBtn.TextColor3 = Color3.fromRGB(0, 240, 255)
    modeBtn.Parent = aimCard

    local mCorner = Instance.new("UICorner")
    mCorner.CornerRadius = UDim.new(0, 6)
    mCorner.Parent = modeBtn

    modeBtn.MouseButton1Click:Connect(function()
        if self.TargetMode == "NearestDistance" then
            self.TargetMode = "NearestCursor"
            modeBtn.Text = "Modo: 🎯 Cercano al Cursor"
        else
            self.TargetMode = "NearestDistance"
            modeBtn.Text = "Modo: ⚡ Objetivo Más Cercano (3D)"
        end
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

    local trackToggleCorner = Instance.new("UICorner")
    trackToggleCorner.CornerRadius = UDim.new(0, 14)
    trackToggleCorner.Parent = trackToggle

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
        local targetName = self.TrackedPlayer and self.TrackedPlayer.Name or (self.ActiveTarget and typeof(self.ActiveTarget) == "Instance" and self.ActiveTarget:IsA("Player") and self.ActiveTarget.Name or "")
        self:RunCommand("player_tracker", { enabled = newState, targetPlayer = targetName })
        
        trackToggle.BackgroundColor3 = newState and Color3.fromRGB(0, 240, 255) or Color3.fromRGB(45, 38, 80)
        trackToggle.Text = newState and "ON" or "OFF"
        trackToggle.TextColor3 = newState and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
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
    print("[VortexHub] UI construida e impresa en pantalla exitosamente.")
end

--------------------------------------------------------------------------------
-- 5. INICIALIZACIÓN DE MOTOR Y HOOKS DE REDIRECCIÓN DE ATAQUES
--------------------------------------------------------------------------------

HookCombatRedirection()
VortexHub:BuildUI()

if getgenv then
    getgenv().VortexHubLoaded = true
    getgenv().VortexHub = VortexHub
end

print("[VortexHub] Proceso de carga finalizado con Motor Universal de Ataques.")
return VortexHub
