--[[
    VortexHub MainLoader.luau
    Formato ejecutable listo para utilizarse mediante:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/MasterPiddy/VortexHub/main/MainLoader.luau"))()
--]]

if getgenv and getgenv().VortexHubLoaded then
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
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
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
end

--------------------------------------------------------------------------------
-- 2. REGISTRO ESTRUCTURAL DE COMANDOS
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
            else
                warn("[VortexHub] Jugador no encontrado:", args.targetPlayer)
            end
        else
            VortexHub.ActiveTarget = nil
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
    else
        warn("[VortexHub] Comando no registrado:", commandId)
    end
end

--------------------------------------------------------------------------------
-- 3. INTERFAZ MÓVIL Y SISTEMA DE TEMAS (LANDSCAPE 75% ANCHO)
--------------------------------------------------------------------------------

function VortexHub:SetAccentColor(color)
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

function VortexHub:BuildUI()
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

    -- Botón Flotante Draggable (Vortex Icon)
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "VortexToggleButton"
    toggleBtn.Size = UDim2.new(0, 52, 0, 52)
    toggleBtn.Position = UDim2.new(0, 25, 0.25, 0)
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

    -- Frame Principal (Landscape - 75% Ancho, Centrado)
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
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Color3.fromRGB(22, 18, 42)
    header.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 14)
    headerCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.4, 0, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🌀 VORTEXHUB <font color='#A855F7'>v1.0</font>"
    title.RichText = true
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    -- Palette Theme Selector (Custom Accent Color)
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
end

--------------------------------------------------------------------------------
-- 4. INICIALIZACIÓN
--------------------------------------------------------------------------------

HookMouseAim()
VortexHub:BuildUI()

if getgenv then
    getgenv().VortexHubLoaded = true
    getgenv().VortexHub = VortexHub
end

print("[VortexHub] Ejecutado exitosamente con UI Móvil Landscape.")
return VortexHub
