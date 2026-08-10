--[[
    VortexUI.luau - Interfaz Móvil de VortexHub con Botón Draggable y Logo "Orbital V"
    Basado en el diseño visual de VortexHub.
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
    AccentColor = Color3.fromRGB(138, 43, 226),
    ThemeElements = {},
    
    -- URL / Asset ID del Logo Oficial "V Orbital"
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

function VortexUI:Build()
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

    ----------------------------------------------------------------------------
    -- 1. BOTÓN FLOTANTE DRAGGABLE CON LOGO ORBITAL Y ANILLO GRADIENTE NEÓN
    ----------------------------------------------------------------------------
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

    -- Anillo de borde gradiente (Cyan -> Purple -> Crimson Pink)
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

    -- Icono de texto V estilizado de respaldo (si la imagen falla en cargar)
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
    self.ToggleButton = toggleBtn

    ----------------------------------------------------------------------------
    -- 2. DASHBOARD PRINCIPAL (75% ANCHO, CENTRADO LANDSCAPE)
    ----------------------------------------------------------------------------
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

    ----------------------------------------------------------------------------
    -- 3. BARRA SUPERIOR CON LOGO OFICIAL VORTEXHUB
    ----------------------------------------------------------------------------
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 45)
    header.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    header.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 14)
    headerCorner.Parent = header

    -- Badge de Titulo y Logo
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

    -- Presets de Color de Acento
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

    -- Botón de Cierre
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

    MakeDraggable(mainFrame, header)
    print("[VortexUI] UI actualizada con Logo oficial Orbital V.")
end

return VortexUI
