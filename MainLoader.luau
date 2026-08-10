--[[
    VortexHub MainLoader.luau - Monolítico Standalone
    Ejecutable mediante:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/MainLoader.luau"))()
--]]

if getgenv and getgenv().VortexHubLoaded and getgenv().VortexHub then
    warn("[VortexHub] El Hub ya está en ejecución.")
    return getgenv().VortexHub
end

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Lighting = game:GetService("Lighting"),
    HttpService = game:GetService("HttpService"),
    TweenService = game:GetService("TweenService"),
    UserInputService = game:GetService("UserInputService"),
    CoreGui = game:GetService("CoreGui")
}

local LocalPlayer = Services.Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Entorno Global de VortexHub
local VortexHub = {
    Version = "1.0.0",
    Config = {},
    ActiveTarget = nil,
    TargetLockEnabled = false,
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
    AccentColor = Color3.fromRGB(138, 43, 226), -- Purple por defecto
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
-- 1. MÓDULO TARGET LOCK (Sin seguimiento de cámara)
--------------------------------------------------------------------------------
local function GetTargetPosition()
    if not VortexHub.TargetLockEnabled or not VortexHub.ActiveTarget or not VortexHub.ActiveTarget.Character then
        return nil
    end

    local char = VortexHub.ActiveTarget.Character
    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")

    if not root or not humanoid or humanoid.Health <= 0 then
        return nil
    end

    local targetPos = root.Position
    if VortexHub.PredictMovement and root:IsA("BasePart") then
        targetPos = targetPos + (root.AssemblyLinearVelocity * VortexHub.PredictionLead)
    end
    return targetPos
end

local function HookMouseAim()
    local success, err = pcall(function()
        local gmt = getrawmetatable(game)
        if setreadonly then setreadonly(gmt, false) end
        local oldIndex = gmt.__index

        gmt.__index = newcclosure(function(selfInstance, key)
            if selfInstance == Mouse and (key == "Hit" or key == "hit") then
                local targetPos = GetTargetPosition()
                if targetPos then
                    return CFrame.new(targetPos)
                end
            end
            return oldIndex(selfInstance, key)
        end)

        if setreadonly then setreadonly(gmt, true) end
    end)
    if not success then
        warn("[VortexHub] Warning al aplicar HookMouseAim:", err)
    end
end

--------------------------------------------------------------------------------
-- 2. MÓDULO PLAYER TRACKER (Rastreo de Distancia, Posición y ESP)
--------------------------------------------------------------------------------
local function ClearTrackerMarker()
    if VortexHub.TrackerBillboard then
        VortexHub.TrackerBillboard:Destroy()
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
    billboard.Size = UDim2.new(0, 170, 0, 42)
    billboard.StudsOffset = Vector3.new(0, 2.8, 0)
    billboard.AlwaysOnTop = true

    local label = Instance.new("TextLabel")
    label.Name = "TrackerText"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 0.4
    label.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    label.TextColor3 = Color3.fromRGB(0, 240, 255)
    label.TextSize = 13
    label.Font = Enum.Font.GothamBold
    label.RichText = true
    label.Text = targetPlayer.DisplayName
    label.Parent = billboard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = VortexHub.AccentColor
    stroke.Parent = label
    table.insert(VortexHub.ThemeElements, stroke)

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

    if VortexHub.TrackerBillboard and VortexHub.TrackerBillboard:FindFirstChild("TrackerText") then
        VortexHub.TrackerBillboard.TrackerText.Text = string.format(
            "🎯 <b>%s</b><br/><font color='#00FF66'>%dm (%dsts)</font> | HP: %d%%",
            VortexHub.TrackedPlayer.DisplayName, distanceMeters, math.floor(rawDistance), health
        )
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
        if args.predictionLead then VortexHub.PredictionLead = tonumber(args.predictionLead) or 0.12 end
        if args.targetPlayer and args.targetPlayer ~= "" then
            local found = nil
            for _, player in ipairs(Services.Players:GetPlayers()) do
                if player ~= LocalPlayer and (player.Name:lower() == args.targetPlayer:lower() or player.DisplayName:lower() == args.targetPlayer:lower()) then
                    found = player
                    break
                end
            end
            VortexHub.ActiveTarget = found
            if found then
                print("[VortexHub] Objetivo fijado:", found.Name)
            end
        else
            VortexHub.ActiveTarget = nil
        end
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

VortexHub.Commands["set_walkspeed"] = function(speed)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = tonumber(speed) or 16
    end
end

VortexHub.Commands["toggle_noclip"] = function(enabled)
    _G.VortexNoclip = enabled
    if enabled and not VortexHub.NoclipConnection then
        VortexHub.NoclipConnection = Services.RunService.Stepped:Connect(function()
            if _G.VortexNoclip and LocalPlayer.Character then
                for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
    elseif not enabled and VortexHub.NoclipConnection then
        VortexHub.NoclipConnection:Disconnect()
        VortexHub.NoclipConnection = nil
    end
end

VortexHub.Commands["set_gravity"] = function(gravity)
    workspace.Gravity = tonumber(gravity) or 196.2
end

VortexHub.Commands["time_of_day"] = function(timeStr)
    local times = { ["Mañana"] = "06:00:00", ["Mediodía"] = "12:00:00", ["Noche"] = "00:00:00" }
    Services.Lighting.TimeOfDay = times[timeStr] or timeStr or "12:00:00"
end

function VortexHub:RunCommand(commandId, payload)
    local commandFunc = self.Commands[commandId]
    if commandFunc then
        local success, err = pcall(function()
            commandFunc(payload)
        end)
        if not success then
            warn("[VortexHub] Error al ejecutar comando (" .. tostring(commandId) .. "):", err)
        end
    end
end

--------------------------------------------------------------------------------
-- 4. INTERFAZ GRÁFICA MÓVIL (STANDALONE / MONOLÍTICA)
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

    -- 1. SELECTOR DE JUGADOR
    local targetCard = Instance.new("Frame")
    targetCard.Size = UDim2.new(0.95, 0, 0, 110)
    targetCard.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    targetCard.Parent = scroll

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = targetCard

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Thickness = 1.5
    cardStroke.Color = Color3.fromRGB(45, 38, 80)
    cardStroke.Parent = targetCard

    local targetTitle = Instance.new("TextLabel")
    targetTitle.Size = UDim2.new(1, -20, 0, 25)
    targetTitle.Position = UDim2.new(0, 10, 0, 6)
    targetTitle.BackgroundTransparency = 1
    targetTitle.Text = "🎯 <b>SELECCIONAR JUGADOR OBJETIVO</b>"
    targetTitle.RichText = true
    targetTitle.Font = Enum.Font.GothamBold
    targetTitle.TextSize = 14
    targetTitle.TextColor3 = Color3.fromRGB(240, 200, 255)
    targetTitle.TextXAlignment = Enum.TextXAlignment.Left
    targetTitle.Parent = targetCard

    local playerDropdown = Instance.new("TextButton")
    playerDropdown.Size = UDim2.new(0.95, 0, 0, 36)
    playerDropdown.Position = UDim2.new(0.025, 0, 0, 36)
    playerDropdown.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    playerDropdown.Text = "Toca para elegir jugador..."
    playerDropdown.Font = Enum.Font.GothamMedium
    playerDropdown.TextSize = 13
    playerDropdown.TextColor3 = Color3.fromRGB(0, 240, 255)
    playerDropdown.Parent = targetCard

    local dropCorner = Instance.new("UICorner")
    dropCorner.CornerRadius = UDim.new(0, 8)
    dropCorner.Parent = playerDropdown

    local selectedLabel = Instance.new("TextLabel")
    selectedLabel.Size = UDim2.new(1, -20, 0, 20)
    selectedLabel.Position = UDim2.new(0, 10, 0, 80)
    selectedLabel.BackgroundTransparency = 1
    selectedLabel.Text = "Objetivo activo: <font color='#00FF66'>Ninguno</font>"
    selectedLabel.RichText = true
    selectedLabel.Font = Enum.Font.Gotham
    selectedLabel.TextSize = 12
    selectedLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
    selectedLabel.Parent = targetCard

    playerDropdown.MouseButton1Click:Connect(function()
        local players = Services.Players:GetPlayers()
        local current = self.ActiveTarget and self.ActiveTarget.Name or ""
        
        local nextIndex = 1
        for i, p in ipairs(players) do
            if p ~= LocalPlayer and p.Name == current then
                nextIndex = i + 1
                break
            end
        end
        
        local chosen = nil
        for i = nextIndex, nextIndex + #players do
            local idx = ((i - 1) % #players) + 1
            local candidate = players[idx]
            if candidate ~= LocalPlayer then
                chosen = candidate
                break
            end
        end

        if chosen then
            playerDropdown.Text = "👤 " .. chosen.DisplayName .. " (@" .. chosen.Name .. ")"
            selectedLabel.Text = "Objetivo activo: <font color='#00FF66'>" .. chosen.DisplayName .. "</font>"
            self:RunCommand("target_lock", { targetPlayer = chosen.Name, enabled = self.TargetLockEnabled })
            self:RunCommand("player_tracker", { targetPlayer = chosen.Name, enabled = self.TrackerEnabled })
        else
            playerDropdown.Text = "No hay jugadores disponibles"
        end
    end)

    -- 2. CONTROL AUTO-AIM
    local aimCard = Instance.new("Frame")
    aimCard.Size = UDim2.new(0.95, 0, 0, 90)
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
    aimToggle.Size = UDim2.new(0, 70, 0, 30)
    aimToggle.Position = UDim2.new(1, -82, 0, 8)
    aimToggle.BackgroundColor3 = self.TargetLockEnabled and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
    aimToggle.Text = self.TargetLockEnabled and "ON" or "OFF"
    aimToggle.Font = Enum.Font.GothamBold
    aimToggle.TextSize = 13
    aimToggle.TextColor3 = self.TargetLockEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    aimToggle.Parent = aimCard

    local aimToggleCorner = Instance.new("UICorner")
    aimToggleCorner.CornerRadius = UDim.new(0, 15)
    aimToggleCorner.Parent = aimToggle

    aimToggle.MouseButton1Click:Connect(function()
        local newState = not self.TargetLockEnabled
        self:RunCommand("target_lock", { enabled = newState, targetPlayer = self.ActiveTarget and self.ActiveTarget.Name or "" })
        aimToggle.BackgroundColor3 = newState and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
        aimToggle.Text = newState and "ON" or "OFF"
        aimToggle.TextColor3 = newState and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    end)

    -- 3. CONTROL PLAYER TRACKER
    local trackerCard = Instance.new("Frame")
    trackerCard.Size = UDim2.new(0.95, 0, 0, 125)
    trackerCard.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    trackerCard.Parent = scroll

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 10)
    trackCorner.Parent = trackerCard

    local trackTitle = Instance.new("TextLabel")
    trackTitle.Size = UDim2.new(0.6, 0, 0, 30)
    trackTitle.Position = UDim2.new(0, 12, 0, 8)
    trackTitle.BackgroundTransparency = 1
    trackTitle.Text = "📡 <b>RASTREADOR DE POSICIÓN</b>"
    trackTitle.RichText = true
    trackTitle.Font = Enum.Font.GothamBold
    trackTitle.TextSize = 14
    trackTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    trackTitle.TextXAlignment = Enum.TextXAlignment.Left
    trackTitle.Parent = trackerCard

    local trackToggle = Instance.new("TextButton")
    trackToggle.Size = UDim2.new(0, 70, 0, 30)
    trackToggle.Position = UDim2.new(1, -82, 0, 8)
    trackToggle.BackgroundColor3 = self.TrackerEnabled and Color3.fromRGB(0, 240, 255) or Color3.fromRGB(45, 38, 80)
    trackToggle.Text = self.TrackerEnabled and "ON" or "OFF"
    trackToggle.Font = Enum.Font.GothamBold
    trackToggle.TextSize = 13
    trackToggle.TextColor3 = self.TrackerEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    trackToggle.Parent = trackerCard

    local trackToggleCorner = Instance.new("UICorner")
    trackToggleCorner.CornerRadius = UDim.new(0, 15)
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
        local targetName = self.TrackedPlayer and self.TrackedPlayer.Name or (self.ActiveTarget and self.ActiveTarget.Name or "")
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
    pcall(function() parentGui = Services.CoreGui end)
    if not parentGui then parentGui = LocalPlayer:WaitForChild("PlayerGui") end

    if parentGui:FindFirstChild("VortexHubScreenGui") then
        parentGui.VortexHubScreenGui:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = "VortexHubScreenGui"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 9999
    screen.Parent = parentGui

    -- BOTÓN FLOTANTE DRAGGABLE (VORTEX ORBITAL LOGO)
    local toggleBtn = Instance.new("ImageButton")
    toggleBtn.Name = "VortexLogoButton"
    toggleBtn.Size = UDim2.new(0, 58, 0, 58)
    toggleBtn.Position = UDim2.new(0, 25, 0.25, 0)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    toggleBtn.BackgroundTransparency = 0.15
    toggleBtn.Image = self.LogoAsset
    toggleBtn.ScaleType = Enum.ScaleType.Fit
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

    -- Fallback Label si la imagen no carga
    local fallbackText = Instance.new("TextLabel")
    fallbackText.Size = UDim2.new(1, 0, 1, 0)
    fallbackText.BackgroundTransparency = 1
    fallbackText.Text = "<b>V</b>"
    fallbackText.RichText = true
    fallbackText.Font = Enum.Font.GothamBlack
    fallbackText.TextSize = 28
    fallbackText.TextColor3 = Color3.fromRGB(224, 176, 255)
    fallbackText.ZIndex = 0
    fallbackText.Parent = toggleBtn

    MakeDraggable(toggleBtn)

    -- FRAME PRINCIPAL (LANDSCAPE - 75% ANCHO, CENTRADO)
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "VortexMainFrame"
    mainFrame.Size = UDim2.new(0.75, 0, 0.78, 0)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    mainFrame.BackgroundTransparency = 0.12
    mainFrame.Visible = false
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

    -- HEADER BAR
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

    local headerLogo = Instance.new("ImageLabel")
    headerLogo.Size = UDim2.new(0, 24, 0, 24)
    headerLogo.Position = UDim2.new(0, 6, 0.5, -12)
    headerLogo.BackgroundTransparency = 1
    headerLogo.Image = self.LogoAsset
    headerLogo.Parent = titleContainer

    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(1, -36, 1, 0)
    titleText.Position = UDim2.new(0, 34, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = "<b>VORTEXHUB</b>"
    titleText.RichText = true
    titleText.Font = Enum.Font.GothamBold
    titleText.TextSize = 16
    titleText.TextColor3 = Color3.fromRGB(240, 200, 255)
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleContainer

    -- COLOR THEME SELECTOR
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

    -- SIDEBAR Y CONTENT AREA
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
end

--------------------------------------------------------------------------------
-- 5. INICIALIZACIÓN
--------------------------------------------------------------------------------

HookMouseAim()
VortexHub:BuildUI()

if getgenv then
    getgenv().VortexHubLoaded = true
    getgenv().VortexHub = VortexHub
end

print("[VortexHub] Ejecutado exitosamente con UI Standalone.")
return VortexHub
