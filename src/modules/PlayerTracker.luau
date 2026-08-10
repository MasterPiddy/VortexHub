--[[
    PlayerTracker.luau - Módulo de Rastreo de Jugadores para VortexHub
    Calcula distancia en tiempo real, posición relativa (X, Y, Z) y renderiza marcador visual/ESP compacto y legible.
--]]

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Workspace = game:GetService("Workspace")
}

local LocalPlayer = Services.Players.LocalPlayer

local PlayerTracker = {
    Enabled = false,
    TrackedPlayer = nil,
    ShowDistance = true,
    ShowPosition = true,
    BillboardGui = nil,
    RenderConnection = nil,
    TrackedData = {
        Distance = 0,
        Position = Vector3.zero,
        Health = 100
    }
}

function PlayerTracker:ClearMarker()
    if self.BillboardGui then
        pcall(function() self.BillboardGui:Destroy() end)
        self.BillboardGui = nil
    end
end

function PlayerTracker:SetTrackedPlayer(playerName)
    self:ClearMarker()

    if not playerName or playerName == "" then
        self.TrackedPlayer = nil
        self.Enabled = false
        return nil
    end

    for _, player in ipairs(Services.Players:GetPlayers()) do
        if player ~= LocalPlayer and (player.Name:lower() == playerName:lower() or player.DisplayName:lower() == playerName:lower()) then
            self.TrackedPlayer = player
            self.Enabled = true
            self:CreateMarker(player)
            return player
        end
    end

    self.TrackedPlayer = nil
    self.Enabled = false
    return nil
end

-- Marcador Visual ESP compacto y súper legible (sin borde amarillo alrededor de las letras)
function PlayerTracker:CreateMarker(targetPlayer)
    if not targetPlayer.Character then return end

    local head = targetPlayer.Character:FindFirstChild("Head") or targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not head then return end

    -- BillboardGui compacto (130x24px)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "VortexTrackerTag"
    billboard.Adornee = head
    billboard.Size = UDim2.new(0, 135, 0, 24)
    billboard.StudsOffset = Vector3.new(0, 2.2, 0)
    billboard.AlwaysOnTop = true

    -- Frame contenedor con borde Accent
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
    frameStroke.Color = Color3.fromRGB(138, 43, 226)
    frameStroke.Parent = frame

    -- Texto legible de un solo color con sombra negra sutil
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
    self.BillboardGui = billboard
end

function PlayerTracker:GetMetrics()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

    if not self.Enabled or not self.TrackedPlayer or not self.TrackedPlayer.Character then
        return nil
    end

    local targetChar = self.TrackedPlayer.Character
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")

    if not targetRoot or not myRoot then
        return nil
    end

    local rawDistance = (targetRoot.Position - myRoot.Position).Magnitude
    local distanceMeters = math.floor(rawDistance * 0.28)
    local targetPos = targetRoot.Position
    local health = targetHumanoid and math.floor((targetHumanoid.Health / targetHumanoid.MaxHealth) * 100) or 0

    self.TrackedData = {
        Studs = math.floor(rawDistance),
        Meters = distanceMeters,
        Position = targetPos,
        Health = health
    }

    -- Formato compacto en 1 sola línea limpia: "🎯 Name • 283m • HP:100%"
    if self.BillboardGui and self.BillboardGui:FindFirstChild("TrackerFrame") then
        local label = self.BillboardGui.TrackerFrame:FindFirstChild("TrackerText")
        if label then
            label.Text = string.format("🎯 <b>%s</b> • <font color='#00FF66'>%dm</font> • %d%%", 
                self.TrackedPlayer.DisplayName, distanceMeters, health)
        end
    end

    return self.TrackedData
end

function PlayerTracker:StartLoop()
    if self.RenderConnection then return end

    self.RenderConnection = Services.RunService.Heartbeat:Connect(function()
        if self.Enabled then
            self:GetMetrics()
        end
    end)
end

function PlayerTracker:StopLoop()
    if self.RenderConnection then
        self.RenderConnection:Disconnect()
        self.RenderConnection = nil
    end
    self:ClearMarker()
end

PlayerTracker:StartLoop()

return PlayerTracker
