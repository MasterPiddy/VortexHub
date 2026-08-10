--[[
    TargetLock.luau - Motor Optimizado de Auto-Aim para Jugadores & NPCs (Sin Lag / Sin Crashes)
--]]

local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    Workspace = game:GetService("Workspace")
}

local LocalPlayer = Services.Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local TargetLock = {
    Enabled = false,
    TargetPlayers = true,
    TargetNPCs = true,
    TargetMode = "NearestDistance",
    
    CurrentTarget = nil,
    PredictMovement = true,
    PredictionLead = 0.12,
    Hooked = false
}

local function IsValidNPC(model)
    if not model or not model:IsA("Model") then return false end
    if Services.Players:GetPlayerFromCharacter(model) then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
    return (hum and root and hum.Health > 0)
end

-- Búsqueda ultrarrápida sin lag (GetChildren en carpetas comunes)
function TargetLock:GetValidTargets()
    local targets = {}
    local myChar = LocalPlayer.Character

    if self.TargetPlayers then
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

    if self.TargetNPCs then
        local searchFolders = { Services.Workspace }
        for _, folderName in ipairs({"Enemies", "NPCs", "Mobs", "Live", "Characters"}) do
            local f = Services.Workspace:FindFirstChild(folderName)
            if f then table.insert(searchFolders, f) end
        end

        local checked = {}
        for _, folder in ipairs(searchFolders) do
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj ~= myChar and not checked[obj] then
                    checked[obj] = true
                    if IsValidNPC(obj) then
                        local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj.PrimaryPart
                        table.insert(targets, { Instance = obj, Character = obj, Root = root, IsPlayer = false })
                    end
                end
            end
        end
    end

    return targets
end

function TargetLock:GetNearestTargetByDistance()
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    local targets = self:GetValidTargets()
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

function TargetLock:GetNearestTargetByCursor()
    local camera = Services.Workspace.CurrentCamera
    if not camera then return nil end

    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    local targets = self:GetValidTargets()
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

function TargetLock:GetTargetPosition()
    if not self.Enabled or not self.CurrentTarget then return nil end

    local targetRoot = GetTargetRootPart(self.CurrentTarget)
    if not targetRoot then return nil end

    local targetPos = targetRoot.Position
    if self.PredictMovement and targetRoot:IsA("BasePart") then
        targetPos = targetPos + (targetRoot.AssemblyLinearVelocity * self.PredictionLead)
    end
    return targetPos
end

-- Bucle asíncrono para actualizar objetivo cada 0.15s
task.spawn(function()
    while task.wait(0.15) do
        if TargetLock.Enabled then
            pcall(function()
                if TargetLock.TargetMode == "NearestDistance" then
                    TargetLock.CurrentTarget = TargetLock:GetNearestTargetByDistance()
                elseif TargetLock.TargetMode == "NearestCursor" then
                    TargetLock.CurrentTarget = TargetLock:GetNearestTargetByCursor()
                end
            end)
        end
    end
end)

-- Orientación de personaje suave en RenderStepped
Services.RunService.RenderStepped:Connect(function()
    if TargetLock.Enabled and TargetLock.CurrentTarget then
        local targetPos = TargetLock:GetTargetPosition()
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

        if targetPos and myRoot then
            local lookAt = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
            myRoot.CFrame = CFrame.new(myRoot.Position, lookAt)
        end
    end
end)

function TargetLock:HookAll()
    if self.Hooked then return end

    pcall(function()
        local gmt = getrawmetatable(game)
        if setreadonly then setreadonly(gmt, false) end
        local oldIndex = gmt.__index

        gmt.__index = newcclosure(function(selfInstance, key)
            if selfInstance == Mouse then
                if key == "Hit" or key == "hit" then
                    local targetPos = TargetLock:GetTargetPosition()
                    if targetPos then
                        return CFrame.new(targetPos)
                    end
                elseif key == "Target" or key == "target" then
                    local targetRoot = GetTargetRootPart(TargetLock.CurrentTarget)
                    if targetRoot then
                        return targetRoot
                    end
                end
            end
            return oldIndex(selfInstance, key)
        end)

        if setreadonly then setreadonly(gmt, true) end
    end)

    self.Hooked = true
end

return TargetLock
