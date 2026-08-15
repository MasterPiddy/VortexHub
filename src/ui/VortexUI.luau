--[[
    VortexUI.luau - Interfaz Móvil de VortexHub con Renderizado de Comandos de Combate
    - Pestaña "Combat" con Target Lock y Player Tracker
    - Selector dinámico de jugadores online
    - Toggles, Sliders y tarjetas de métricas en vivo
--]]

local Services = {
    TweenService = game:GetService("TweenService"),
    UserInputService = game:GetService("UserInputService"),
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    CoreGui = game:GetService("CoreGui")
}

local LocalPlayer = Services.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local VortexUI = {
    ScreenGui = nil,
    MainFrame = nil,
    ToggleButton = nil,
    ContentArea = nil,
    ActiveCategory = "combat",
    AccentColor = Color3.fromRGB(138, 43, 226),
    ThemeElements = {},
    
    LogoAsset = "https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/assets/vortex_logo.png",
    
    Themes = {
        Purple = Color3.fromRGB(138, 43, 226),
        Cyan = Color3.fromRGB(0, 240, 255),
        Crimson = Color3.fromRGB(255, 36, 0),
        Green = Color3.fromRGB(0, 255, 102),
        Amber = Color3.fromRGB(255, 179, 0)
    }
}

function VortexUI:SetAccentColor(color)
    self.AccentColor = color
    for _, item in ipairs(self.ThemeElements) do
        if item:IsA("UIStroke") then
            item.Color = color
        elseif item:IsA("TextLabel") or item:IsA("TextButton") then
            if item:GetAttribute("IsThemeAccent") then
                item.TextColor3 = color
            end
        elseif item:IsA("Frame") then
            if item:GetAttribute("IsThemeAccentBG") then
                item.BackgroundColor3 = color
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

function VortexUI:RenderCombatCategory(hubInstance)
    if not self.ContentArea then return end
    self.ContentArea:ClearAllChildren()

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = self.AccentColor
    scroll.Parent = self.ContentArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 12)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.Parent = scroll

    ----------------------------------------------------------------------------
    -- 1. TARJETA SELECTOR DE JUGADOR OBJETIVO
    ----------------------------------------------------------------------------
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

    -- Dropdown / Selector de Jugadores Online
    local playerDropdown = Instance.new("TextButton")
    playerDropdown.Size = UDim2.new(0.95, 0, 0, 36)
    playerDropdown.Position = UDim2.new(0.025, 0, 0, 36)
    playerDropdown.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    playerDropdown.Text = "Elegir jugador..."
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

    -- Menú desplegable de lista de jugadores
    playerDropdown.MouseButton1Click:Connect(function()
        local players = Services.Players:GetPlayers()
        local current = hubInstance.ActiveTarget and hubInstance.ActiveTarget.Name or ""
        
        -- Ciclar entre jugadores online
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
            
            -- Ejecutar comandos en VortexHub
            hubInstance:RunCommand("target_lock", { targetPlayer = chosen.Name, enabled = hubInstance.TargetLockEnabled })
            hubInstance:RunCommand("player_tracker", { targetPlayer = chosen.Name, enabled = hubInstance.TrackerEnabled })
        else
            playerDropdown.Text = "No hay más jugadores en servidor"
        end
    end)

    ----------------------------------------------------------------------------
    -- 2. TARJETA CONTROL: AUTO-AIM (TARGET LOCK)
    ----------------------------------------------------------------------------
    local aimCard = Instance.new("Frame")
    aimCard.Size = UDim2.new(0.95, 0, 0, 100)
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

    -- Switch Toggle para Target Lock
    local aimToggle = Instance.new("TextButton")
    aimToggle.Size = UDim2.new(0, 70, 0, 30)
    aimToggle.Position = UDim2.new(1, -82, 0, 8)
    aimToggle.BackgroundColor3 = hubInstance.TargetLockEnabled and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
    aimToggle.Text = hubInstance.TargetLockEnabled and "ON" or "OFF"
    aimToggle.Font = Enum.Font.GothamBold
    aimToggle.TextSize = 13
    aimToggle.TextColor3 = hubInstance.TargetLockEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    aimToggle.Parent = aimCard

    local aimToggleCorner = Instance.new("UICorner")
    aimToggleCorner.CornerRadius = UDim.new(0, 15)
    aimToggleCorner.Parent = aimToggle

    aimToggle.MouseButton1Click:Connect(function()
        local newState = not hubInstance.TargetLockEnabled
        hubInstance:RunCommand("target_lock", { enabled = newState, targetPlayer = hubInstance.ActiveTarget and hubInstance.ActiveTarget.Name or "" })
        aimToggle.BackgroundColor3 = newState and Color3.fromRGB(0, 255, 102) or Color3.fromRGB(45, 38, 80)
        aimToggle.Text = newState and "ON" or "OFF"
        aimToggle.TextColor3 = newState and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    end)

    -- Sub-control: Predicción de Movimiento
    local predLabel = Instance.new("TextLabel")
    predLabel.Size = UDim2.new(0.9, 0, 0, 20)
    predLabel.Position = UDim2.new(0, 12, 0, 52)
    predLabel.BackgroundTransparency = 1
    predLabel.Text = "⚡ Predicción de Movimiento: <font color='#A855F7'>0.12s</font>"
    predLabel.RichText = true
    predLabel.Font = Enum.Font.Gotham
    predLabel.TextSize = 12
    predLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    predLabel.TextXAlignment = Enum.TextXAlignment.Left
    predLabel.Parent = aimCard

    ----------------------------------------------------------------------------
    -- 3. TARJETA CONTROL: RASTREO DE JUGADOR (PLAYER TRACKER)
    ----------------------------------------------------------------------------
    local trackerCard = Instance.new("Frame")
    trackerCard.Size = UDim2.new(0.95, 0, 0, 130)
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

    -- Switch Toggle para Tracker
    local trackToggle = Instance.new("TextButton")
    trackToggle.Size = UDim2.new(0, 70, 0, 30)
    trackToggle.Position = UDim2.new(1, -82, 0, 8)
    trackToggle.BackgroundColor3 = hubInstance.TrackerEnabled and Color3.fromRGB(0, 240, 255) or Color3.fromRGB(45, 38, 80)
    trackToggle.Text = hubInstance.TrackerEnabled and "ON" or "OFF"
    trackToggle.Font = Enum.Font.GothamBold
    trackToggle.TextSize = 13
    trackToggle.TextColor3 = hubInstance.TrackerEnabled and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    trackToggle.Parent = trackerCard

    local trackToggleCorner = Instance.new("UICorner")
    trackToggleCorner.CornerRadius = UDim.new(0, 15)
    trackToggleCorner.Parent = trackToggle

    -- Métricas en vivo (Distancia y Posición)
    local metricsText = Instance.new("TextLabel")
    metricsText.Size = UDim2.new(0.95, 0, 0, 75)
    metricsText.Position = UDim2.new(0, 12, 0, 48)
    metricsText.BackgroundTransparency = 1
    metricsText.Text = "Distancia: <b>-- m</b> (-- studs)<br/>Posición X, Y, Z: <b>(0, 0, 0)</b><br/>Salud Objetivo: <b>-- %</b>"
    metricsText.RichText = true
    metricsText.Font = Enum.Font.Gotham
    metricsText.TextSize = 12
    metricsText.TextColor3 = Color3.fromRGB(200, 200, 200)
    metricsText.TextXAlignment = Enum.TextXAlignment.Left
    metricsText.Parent = trackerCard

    trackToggle.MouseButton1Click:Connect(function()
        local newState = not hubInstance.TrackerEnabled
        local targetName = hubInstance.TrackedPlayer and hubInstance.TrackedPlayer.Name or (hubInstance.ActiveTarget and hubInstance.ActiveTarget.Name or "")
        hubInstance:RunCommand("player_tracker", { enabled = newState, targetPlayer = targetName })
        
        trackToggle.BackgroundColor3 = newState and Color3.fromRGB(0, 240, 255) or Color3.fromRGB(45, 38, 80)
        trackToggle.Text = newState and "ON" or "OFF"
        trackToggle.TextColor3 = newState and Color3.fromRGB(15, 12, 28) or Color3.fromRGB(200, 200, 200)
    end)

    -- Actualizador de Métricas en Vivo
    Services.RunService.Heartbeat:Connect(function()
        if hubInstance.TrackerEnabled and hubInstance.TrackedData then
            local data = hubInstance.TrackedData
            metricsText.Text = string.format(
                "Distancia: <font color='#00FF66'><b>%d m</b> (%d studs)</font><br/>Posición X, Y, Z: <b>(%d, %d, %d)</b><br/>Salud Objetivo: <font color='#FF2400'><b>%d%%</b></font>",
                data.Meters or 0, data.Studs or 0,
                math.floor(data.Position.X or 0), math.floor(data.Position.Y or 0), math.floor(data.Position.Z or 0),
                data.Health or 100
            )
        end
    end)
end

function VortexUI:Build(hubInstance)
    local parentGui = (Services.RunService:IsStudio() and PlayerGui) or Services.CoreGui

    if parentGui:FindFirstChild("VortexHubScreenGui") then
        parentGui.VortexHubScreenGui:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = "VortexHubScreenGui"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 999
    screen.Parent = parentGui
    self.ScreenGui = screen

    -- Botón Flotante Draggable
    local toggleBtn = Instance.new("ImageButton")
    toggleBtn.Name = "VortexLogoButton"
    toggleBtn.Size = UDim2.new(0, 58, 0, 58)
    toggleBtn.Position = UDim2.new(0, 20, 0.3, 0)
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

    MakeDraggable(toggleBtn)
    self.ToggleButton = toggleBtn

    -- Frame Principal (Landscape 75% Ancho)
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

    -- Header Bar
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

    -- Theme Color Presets
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

    -- Close Button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -38, 0.5, -14)
    closeBtn.BackgroundColor3 = Color3.fromRGB(45, 18, 25)
    closeBtn.BackgroundTransparency = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 45, 45)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.Parent = header

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 7)
    closeCorner.Parent = closeBtn

    local closeStroke = Instance.new("UIStroke")
    closeStroke.Thickness = 1.2
    closeStroke.Color = Color3.fromRGB(255, 60, 60)
    closeStroke.Transparency = 0.2
    closeStroke.Parent = closeBtn

    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
    end)

    ----------------------------------------------------------------------------
    -- SIDEBAR Y ÁREA DE CONTENIDO
    ----------------------------------------------------------------------------
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
    self.ContentArea = contentArea

    -- Botón de Pestaña Combate
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
        self:RenderCombatCategory(hubInstance)
    end)

    MakeDraggable(mainFrame, header)
    
    -- Renderizar categoría Combat al abrir por primera vez
    self:RenderCombatCategory(hubInstance)
end

return VortexUI
