--[[
    TargetLock.luau - Motor Universal de Auto-Aim y Redirección de Ataques/Habilidades
    - Soporte para Jugadores y NPCs/Mobs
    - Redirección de Mouse.Hit, Character LookVector (orientación silenciosa), Raycast y RemoteEvents
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
    TargetPlayers = true,  -- Targetear Jugadores
    TargetNPCs = true,      -- Targetear NPCs/Mobs
    TargetMode = "NearestDistance", -- "NearestDistance", "NearestCursor", "Manual"
    
    CurrentTarget = nil,    -- Instancia (Player o Model NPC)
    PredictMovement = true,
    PredictionLead = 0.12,
    
    Hooked = false,
    FaceTargetConnection = nil
}

-- Verificar si un modelo de Workspace es un NPC/Mob válido
local function IsValidNPC(model)
    if not model or not model:IsA("Model") then return false end
    if Services.Players:GetPlayerFromCharacter(model) then return false end -- No es jugador

    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart

    if hum and root and hum.Health > 0 then
        return true
    end
    return false
end

-- Obtener todos los objetivos válidos (Jugadores y/o NPCs)
function TargetLock:GetValidTargets()
    local targets = {}
    local myChar = LocalPlayer.Character

    -- 1. Jugadores
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

    -- 2. NPCs / Mobs en Workspace
    if self.TargetNPCs then
        for _, obj in ipairs(Services.Workspace:GetDescendants()) do
            if obj ~= myChar and IsValidNPC(obj) then
                local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or obj.PrimaryPart
                table.insert(targets, { Instance = obj, Character = obj, Root = root, IsPlayer = false })
            end
        end
    end

    return targets
end

-- Encontrar el objetivo más cercano por distancia 3D (Jugadores o NPCs)
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

-- Encontrar el objetivo más cercano al cursor de la pantalla
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

-- Obtener la posición RootPart de cualquier objetivo (Jugador o NPC)
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

-- Obtener la posición exacta calculada del objetivo
function TargetLock:GetTargetPosition()
    if not self.Enabled then return nil end

    -- Auto-Targeting dinámico
    if self.TargetMode == "NearestDistance" then
        self.CurrentTarget = self:GetNearestTargetByDistance()
    elseif self.TargetMode == "NearestCursor" then
        self.CurrentTarget = self:GetNearestTargetByCursor()
    end

    local targetRoot = GetTargetRootPart(self.CurrentTarget)
    if not targetRoot then return nil end

    local targetPos = targetRoot.Position

    -- Predicción de movimiento
    if self.PredictMovement and targetRoot:IsA("BasePart") then
        local velocity = targetRoot.AssemblyLinearVelocity
        targetPos = targetPos + (velocity * self.PredictionLead)
    end

    return targetPos
end

-- Orientar silenciosamente el personaje del jugador hacia el objetivo (para ataques Melee / LookVector)
function TargetLock:StartFaceTargetLoop()
    if self.FaceTargetConnection then return end

    self.FaceTargetConnection = Services.RunService.RenderStepped:Connect(function()
        if self.Enabled then
            local targetPos = self:GetTargetPosition()
            local myChar = LocalPlayer.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

            if targetPos and myRoot then
                -- Orienta el HumanoidRootPart hacia el objetivo horizontalmente sin inclinar la cámara
                local lookAt = Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z)
                myRoot.CFrame = CFrame.new(myRoot.Position, lookAt)
            end
        end
    end)
end

-- Hooks Avanzados: Mouse, Raycast y RemoteEvents
function TargetLock:HookAll()
    if self.Hooked then return end

    pcall(function()
        local gmt = getrawmetatable(game)
        if setreadonly then setreadonly(gmt, false) end
        local oldIndex = gmt.__index
        local oldNamecall = gmt.__namecall

        -- 1. Hook de Mouse.Hit y Mouse.Target
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

        -- 2. Hook de Namecall para Raycast y RemoteEvents de Habilidades
        gmt.__namecall = newcclosure(function(selfInstance, ...)
            local method = getnamecallmethod()
            local args = {...}

            if TargetLock.Enabled then
                local targetPos = TargetLock:GetTargetPosition()

                if targetPos then
                    -- Interceptar Raycast de habilidades
                    if method == "Raycast" or method == "raycast" or method == "FindPartOnRay" then
                        local origin = args[1]
                        if typeof(origin) == "Vector3" then
                            local dir = (targetPos - origin).Unit * 1000
                            args[2] = dir
                            return oldNamecall(selfInstance, unpack(args))
                        end
                    end

                    -- Interceptar disparos de RemoteEvents de ataques
                    if method == "FireServer" or method == "fireServer" then
                        for i, arg in ipairs(args) do
                            if typeof(arg) == "CFrame" then
                                args[i] = CFrame.new(arg.Position, targetPos)
                            elseif typeof(arg) == "Vector3" and (arg - targetPos).Magnitude > 5 then
                                -- Si pasa un vector de dirección o punto de impacto
                                if arg.Magnitude < 2 then -- Vector3 de dirección normalizado
                                    local myChar = LocalPlayer.Character
                                    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                                    if myRoot then
                                        args[i] = (targetPos - myRoot.Position).Unit
                                    end
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

    self.Hooked = true
    self:StartFaceTargetLoop()
end

return TargetLock
