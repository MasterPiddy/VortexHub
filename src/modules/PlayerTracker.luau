--[[
    PlayerTracker.luau - Módulo de Rastreo de Jugadores para VortexHub
    Calcula distancia en tiempo real, posición relativa (X, Y, Z) y renderiza marcador visual/ESP.
--]]

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Workspace = game:GetService("Workspace")
}

local LocalPlayer = Services.Players.LocalPlayer

local PlayerTracker = {
    Enabled = false,
    TrackedPlayer = nil, -- Player Object
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

-- Limpiar marcadore visuales previos
function PlayerTracker:ClearMarker()
    if self.BillboardGui then
        self.BillboardGui:Destroy()
        self.BillboardGui = nil
    end
end

-- Asignar jugador a rastrear
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

-- Crear marcador visual sobre la cabeza del objetivo (ESP / Tracker)
function PlayerTracker:CreateMarker(targetPlayer)
    if not targetPlayer.Character then return end

    local head = targetPlayer.Character:FindFirstChild("Head") or targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not head then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "VortexTrackerTag"
    billboard.Adornee = head
    billboard.Size = UDim2.new(0, 160, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = head

    local label = Instance.new("TextLabel")
    label.Name = "TrackerText"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 0.5
    label.BackgroundColor3 = Color3.fromRGB(15, 12, 28)
    label.TextColor3 = Color3.fromRGB(0, 240, 255) -- Electric Blue
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
    stroke.Color = Color3.fromRGB(138, 43, 226)
    stroke.Parent = label

    self.BillboardGui = billboard
end

-- Obtener métricas en tiempo real (Distancia y Posición)
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

    -- Cálculo de distancia en studs (y metros equivalentes: 1 stud ≈ 0.28m)
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

    -- Actualizar marcador visual sobre la cabeza
    if self.BillboardGui and self.BillboardGui:FindFirstChild("TrackerText") then
        local label = self.BillboardGui.TrackerText
        label.Text = string.format("🎯 <b>%s</b><br/><font color='#00FF66'>%dm</font> | HP: %d%%", 
            self.TrackedPlayer.DisplayName, distanceMeters, health)
    end

    return self.TrackedData
end

-- Bucle de renderizado continuo
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
