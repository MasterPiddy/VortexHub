--[[
    VortexUI.luau - Sistema de Interfaz de Usuario para VortexHub (Mobile Landscape)
    - Botón flotante arrastrable
    - Dashboard central (75% ancho de pantalla)
    - Accent Colors personalizables dinámicamente
--]]

local Services = {
    TweenService = game:GetService("TweenService"),
    UserInputService = game:GetService("UserInputService"),
    Players = game:GetService("Players"),
    CoreGui = game:GetService("CoreGui")
}

local LocalPlayer = Services.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local VortexUI = {
    ScreenGui = nil,
    MainFrame = nil,
    ToggleButton = nil,
    ActiveCategory = "combat",
    AccentColor = Color3.fromRGB(138, 43, 226), -- Purple por defecto
    ThemeElements = {}, -- UIStrokes, Highlights para actualización dinámica de tema
    
    -- Temas de Color Disponibles
    Themes = {
        Purple = Color3.fromRGB(138, 43, 226),
        Cyan = Color3.fromRGB(0, 240, 255),
        Crimson = Color3.fromRGB(255, 36, 0),
        Green = Color3.fromRGB(0, 255, 102),
        Amber = Color3.fromRGB(255, 179, 0)
    }
}

-- Cambiar el Accent Color de toda la interfaz
function VortexUI:SetAccentColor(color)
    self.AccentColor = color
    for _, item in ipairs(self.ThemeElements) do
        if item:IsA("UIStroke") then
            item.Color = color
        elseif item:IsA("TextLabel") or item:IsA("TextButton") then
            if item:GetAttribute("IsThemeAccent") then
                item.TextColor3 = color
            end
        elseif item:IsA("Frame") or item:IsA("ImageLabel") then
            if item:GetAttribute("IsThemeAccentBG") then
                item.BackgroundColor3 = color
            end
        end
    end
end

-- Hacer cualquier Frame arrastrable por Touch / Mouse
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

-- Inicializar y construir la UI
function VortexUI:Build(coreInstance)
    local parentGui = (RunService:IsStudio() and PlayerGui) or Services.CoreGui

    -- Destruir instancia previa si existe
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

    ----------------------------------------------------------------------------
    -- 1. BOTÓN FLOTANTE (DRAGGABLE)
    ----------------------------------------------------------------------------
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "VortexToggleButton"
    toggleBtn.Size = UDim2.new(0, 52, 0, 52)
    toggleBtn.Position = UDim2.new(0, 20, 0.3, 0)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    toggleBtn.BackgroundTransparency = 0.15
    toggleBtn.Text = "🌀"
    toggleBtn.TextSize = 26
    toggleBtn.Parent = screen

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(1, 0)
    btnCorner.Parent = toggleBtn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Thickness = 2
    btnStroke.Color = self.AccentColor
    btnStroke.Parent = toggleBtn
    table.insert(self.ThemeElements, btnStroke)

    MakeDraggable(toggleBtn)
    self.ToggleButton = toggleBtn

    ----------------------------------------------------------------------------
    -- 2. DASHBOARD PRINCIPAL (75% Ancho - Landscape Centrado)
    ----------------------------------------------------------------------------
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "VortexMainFrame"
    mainFrame.Size = UDim2.new(0.75, 0, 0.8, 0)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.Visible = false
    mainFrame.Parent = screen

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Thickness = 2.5
    mainStroke.Color = self.AccentColor
    mainStroke.Parent = mainFrame
    table.insert(self.ThemeElements, mainStroke)

    self.MainFrame = mainFrame

    -- Toggle Visibilidad desde el botón flotante
    toggleBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)

    ----------------------------------------------------------------------------
    -- 3. BARRA SUPERIOR (HEADER)
    ----------------------------------------------------------------------------
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 45)
    header.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    header.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.4, 0, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🌀 VORTEXHUB <font color='#A855F7'>v1.0</font>"
    title.RichText = true
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    -- Botón Cerrar
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 32, 0, 32)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -16)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    closeBtn.TextSize = 20
    closeBtn.Parent = header
    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
    end)

    -- Selector de Accent Colors (Presets)
    local themeContainer = Instance.new("Frame")
    themeContainer.Size = UDim2.new(0, 150, 0, 30)
    themeContainer.Position = UDim2.new(1, -200, 0.5, -15)
    themeContainer.BackgroundTransparency = 1
    themeContainer.Parent = header

    local themeLayout = Instance.new("UIListLayout")
    themeLayout.FillDirection = Enum.FillDirection.Horizontal
    themeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    themeLayout.Padding = UDim.new(0, 6)
    themeLayout.Parent = themeContainer

    for themeName, color in pairs(self.Themes) do
        local colorDot = Instance.new("TextButton")
        colorDot.Size = UDim2.new(0, 20, 0, 20)
        colorDot.BackgroundColor3 = color
        colorDot.Text = ""
        colorDot.Parent = themeContainer
        
        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = colorDot

        colorDot.MouseButton1Click:Connect(function()
            self:SetAccentColor(color)
        end)
    end

    ----------------------------------------------------------------------------
    -- 4. SIDEBAR LATERAL (CATEGORÍAS)
    ----------------------------------------------------------------------------
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0.25, 0, 1, -45)
    sidebar.Position = UDim2.new(0, 0, 0, 45)
    sidebar.BackgroundColor3 = Color3.fromRGB(18, 14, 34)
    sidebar.Parent = mainFrame

    local sidebarLayout = Instance.new("UIListLayout")
    sidebarLayout.Padding = UDim.new(0, 8)
    sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sidebarLayout.Parent = sidebar

    local sidePadding = Instance.new("UIPadding")
    sidePadding.PaddingTop = UDim.new(0, 12)
    sidePadding.Parent = sidebar

    local categories = {
        { id = "combat", name = "🎯 Combate" },
        { id = "player", name = "👤 Jugador" },
        { id = "world", name = "🌐 Mundo" }
    }

    for _, cat in ipairs(categories) do
        local catBtn = Instance.new("TextButton")
        catBtn.Size = UDim2.new(0.88, 0, 0, 40)
        catBtn.BackgroundColor3 = Color3.fromRGB(28, 22, 52)
        catBtn.Text = cat.name
        catBtn.Font = Enum.Font.GothamMedium
        catBtn.TextSize = 14
        catBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
        catBtn.Parent = sidebar

        local catCorner = Instance.new("UICorner")
        catCorner.CornerRadius = UDim.new(0, 8)
        catCorner.Parent = catBtn
    end

    print("[VortexUI] UI Móvil construida con éxito.")
end

return VortexUI
