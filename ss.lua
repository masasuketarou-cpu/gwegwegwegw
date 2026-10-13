_G.MasaHubExecuted = true

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    repeat task.wait() until Players.LocalPlayer
    LocalPlayer = Players.LocalPlayer
end
local player = LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ==========================================
-- GESTOR CENTRAL DE ANIMACIONES
-- ==========================================
local animatedGradients = setmetatable({}, { __mode = "k" })
task.spawn(function()
    while task.wait(0.05) do
        for grad, speed in pairs(animatedGradients) do
            if grad and grad.Parent then
                grad.Rotation = (grad.Rotation + speed * 0.05) % 360
            else
                animatedGradients[grad] = nil
            end
        end
    end
end)

-- ==========================================
-- CONFIGURACIÓN Y GUI PRINCIPAL
-- ==========================================
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local safeGuiTarget = nil
local successCore = pcall(function()
    local test = Instance.new("Folder")
    test.Parent = CoreGui
    test:Destroy()
end)
safeGuiTarget = successCore and CoreGui or (player:WaitForChild("PlayerGui", 5) or player.PlayerGui)

local function getGuiParent()
    if gethui then return gethui() end
    return safeGuiTarget
end

pcall(function()
    for _, name in ipairs({"MasaHubUI", "HexSemiTP_ProgressBar", "MasaSpeedUI", "MasaAPSpamUI", "MasaAllowDisallow"}) do
        if getGuiParent():FindFirstChild(name) then 
            getGuiParent()[name]:Destroy() 
        end
    end
end)

local MAIN_FONT = Enum.Font.FredokaOne
local COLOR_BG_DARK = Color3.fromRGB(15, 15, 18)
local COLOR_CARD_BG = Color3.fromRGB(24, 24, 28)
local COLOR_BORDER = Color3.fromRGB(80, 50, 140)
local COLOR_ACCENT = Color3.fromRGB(170, 100, 255)
local COLOR_TEXT_LIGHT = Color3.fromRGB(245, 245, 245)
local COLOR_TEXT_DARK = Color3.fromRGB(150, 150, 160)

local HEX_TEXT_PATTERN = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(230, 200, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 130, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 80, 230))
})

local function applyTextGradient(textObject)
    if not textObject then return end
    local stroke = textObject:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
    stroke.Thickness = 1.2
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Transparency = 0.2
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
    stroke.Parent = textObject

    local grad = textObject:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
    grad.Color = HEX_TEXT_PATTERN
    grad.Rotation = 45
    grad.Parent = textObject

    animatedGradients[grad] = 35
    return grad
end

local function createUICorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function addHoverAnimation(btn, normalColor, hoverColor)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = hoverColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = normalColor}):Play()
    end)
end

local configFile = "MasaHub_Config.json"
local HubConfig = { 
    speedBoostEnabled = false, 
    speedValue = 25, 
    hexSpeedVisible = false,
    speedPos = {ScaleX = 0.98, OffsetX = 0, ScaleY = 0.02, OffsetY = 0},
    stealKeybind = "E",
    potionEnabled = true,
    autoWalkEnabled = false,
    apOnStealEnabled = false,
    autoTPOnAllowEnabled = false,
    autoActivateEnabled = false,
    kickAfterStealEnabled = false,
    apDefenseEnabled = false,
    laserDefenseEnabled = false,
    aimbotEnabled = false,
    selectedSlot = 1,
    selectedGear = "Auto"
}

if isfile and isfile(configFile) then 
    local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(configFile)) end) 
    if success and decoded then 
        for k, v in pairs(decoded) do 
            if k ~= "selectedSlot" then HubConfig[k] = v end
        end 
    end 
end
HubConfig.selectedSlot = 1

local function saveHubConfig() 
    if writefile then pcall(function() writefile(configFile, HttpService:JSONEncode(HubConfig)) end) end 
end

_G.speedBoostEnabled = HubConfig.speedBoostEnabled
local currentSpeed = HubConfig.speedValue or 25
local currentStealKey = Enum.KeyCode[HubConfig.stealKeybind or "E"]
local PotionEnabled = HubConfig.potionEnabled
local AutoWalkEnabled = HubConfig.autoWalkEnabled
local APOnStealEnabled = HubConfig.apOnStealEnabled
local AutoTPOnAllowEnabled = HubConfig.autoTPOnAllowEnabled or false
local AutoActivateEnabled = HubConfig.autoActivateEnabled or false
local KickAfterStealEnabled = HubConfig.kickAfterStealEnabled or false

-- Estado compartido de las defensas (usado por el módulo al final del script)
local HexDefenseState = {
    AP = HubConfig.apDefenseEnabled or false,
    Laser = HubConfig.laserDefenseEnabled or false,
    Aimbot = HubConfig.aimbotEnabled or false
}
local selectedSlot = 1 

-- Forward declarations para la barra inferior de "Target: <animal>" / "Stealing..."
local TargetBarLabel, refreshTargetBar, setStealingStatus
local manualStealingUntil = 0

-- ==========================================
-- LÓGICA KICK AFTER STEAL (GUI DETECTOR)
-- ==========================================
local kickKeyword = "you stole"
local kickMessage = "You stole brainrot!"

local function hasKickKeyword(text)
    if typeof(text) ~= "string" then return false end
    return string.find(string.lower(text), kickKeyword) ~= nil
end

local function kickPlayer()
    pcall(function()
        player:Kick(kickMessage)
    end)
end

local function checkAndKickObject(obj)
    if not KickAfterStealEnabled then return end
    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        if hasKickKeyword(obj.Text) then
            kickPlayer()
        end
    end
end

local function scanGuiForKick(parent)
    for _, obj in ipairs(parent:GetDescendants()) do
        checkAndKickObject(obj)
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            obj:GetPropertyChangedSignal("Text"):Connect(function()
                checkAndKickObject(obj)
            end)
        end
    end
end

PlayerGui.DescendantAdded:Connect(function(desc)
    checkAndKickObject(desc)
    if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
        desc:GetPropertyChangedSignal("Text"):Connect(function()
            checkAndKickObject(desc)
        end)
    end
end)

scanGuiForKick(PlayerGui)

-- ==========================================
-- ADMIN PANEL SPAM
-- ==========================================
local ALL_CMDS = {"rocket", "tiny", "jumpscare", "morph", "inverse"}
local selectedCmds = {}
for _, cmd in ipairs(ALL_CMDS) do selectedCmds[cmd] = true end 

local function getAdminPanelButtons()
    local ap = LocalPlayer.PlayerGui:FindFirstChild("AdminPanel")
    if not ap then return nil, nil end
    local inner = ap:FindFirstChild("AdminPanel")
    if not inner then return nil, nil end
    local content, profiles = inner:FindFirstChild("Content"), inner:FindFirstChild("Profiles")
    if not content or not profiles then return nil, nil end
    return content:FindFirstChild("ScrollingFrame"), profiles:FindFirstChild("ScrollingFrame")
end

local fireCmd = function(targetPlayer, cmd)
    local csf, psf = getAdminPanelButtons()
    if not csf or not psf then return end
    local pb, cb = psf:FindFirstChild(targetPlayer.Name), csf:FindFirstChild(cmd)
    if not pb or not cb then return end

    if firesignal then
        firesignal(cb.Activated)
        firesignal(pb.Activated)
    elseif getconnections then
        for _, c in ipairs(getconnections(cb.Activated)) do if c.Function then task.spawn(c.Function) end end
        for _, c in ipairs(getconnections(pb.Activated)) do if c.Function then task.spawn(c.Function) end end
    end
end

local lastSpam, COOLDOWN = 0, 0.15
local doSpam = function()
    if tick() - lastSpam < COOLDOWN then return end
    lastSpam = tick()
    local toFire = {}
    for _, cmd in ipairs(ALL_CMDS) do if selectedCmds[cmd] then table.insert(toFire, cmd) end end
    if #toFire == 0 then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            for _, cmd in ipairs(toFire) do fireCmd(p, cmd) end
        end
    end
end

-- ==========================================
-- BOOSTER Y MOVIMIENTO
-- ==========================================
local ACCESSORIES_TO_REMOVE = {
    "Black Shield", "MechHorseHelmet_AccAccessory", "Glasses",
    "MeshPartAccessory", "LeftShoeAccessory", "RightShoeAccessory",
}

local function cleanAccessories(char)
    if not char then return end
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Accessory") then
            for _, name in ipairs(ACCESSORIES_TO_REMOVE) do
                if item.Name == name or string.find(item.Name, name) then
                    pcall(function() item:Destroy() end)
                end
            end
        end
    end
end

local activeSpeedConnections = {}
local function clearSpeedConnections() 
    for _, conn in ipairs(activeSpeedConnections) do if conn then conn:Disconnect() end end 
    activeSpeedConnections = {} 
end

local function initSpeedFeatures(char)
    clearSpeedConnections()
    cleanAccessories(char)

    local hum = char:WaitForChild("Humanoid", 5)
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if not (hum and hrp) then return end

    local att = hrp:FindFirstChild("MasaSpeedAttachment") or Instance.new("Attachment")
    att.Name = "MasaSpeedAttachment"
    att.Parent = hrp

    local lv = hrp:FindFirstChild("MasaSpeedLV") or Instance.new("LinearVelocity")
    lv.Name = "MasaSpeedLV"
    lv.Attachment0 = att
    lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
    lv.MaxAxesForce = Vector3.new(100000, 0, 100000)
    lv.Enabled = false
    lv.Parent = hrp
    
    local speedConn = RunService.Heartbeat:Connect(function()
        if not char or not char.Parent or not hum or not hrp or not lv or not lv.Parent then return end

        if _G.speedBoostEnabled then 
            if hum.FloorMaterial ~= Enum.Material.Air and hum.MoveDirection.Magnitude > 0 then 
                local flat = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z).Unit
                lv.VectorVelocity = Vector3.new(flat.X * currentSpeed, 0, flat.Z * currentSpeed)
                lv.Enabled = true
            else
                lv.Enabled = false
                lv.VectorVelocity = Vector3.zero
            end 
        else
            lv.Enabled = false
            lv.VectorVelocity = Vector3.zero
        end
    end)
    table.insert(activeSpeedConnections, speedConn)
end

if player.Character then task.spawn(initSpeedFeatures, player.Character) end
player.CharacterAdded:Connect(function(char) task.wait(0.2); initSpeedFeatures(char) end)

-- ==========================================
-- LOGICA DE TELEPORT Y STEAL
-- ==========================================
local STEAL_DURATION = 1.3
local progressFill, percentLabel = nil, nil

local function updateProgressBar(_) end -- barra de 100% desactivada

local function detectStealAndWait()
    local startTime = tick()
    while player:GetAttribute("Stealing") == nil do
        if tick() - startTime >= 3 then break end
        task.wait(0.1)
    end
    if player:GetAttribute("Stealing") ~= nil then task.wait(0.5) end
end

local cachedMyBase = nil
local function findMyBase()
    if cachedMyBase and cachedMyBase.Parent then return cachedMyBase end
    local plots = Workspace:FindFirstChild("Plots") or Workspace:FindFirstChild("Bases") or Workspace:FindFirstChild("Tycoons") or Workspace
    for _, base in pairs(plots:GetChildren()) do
        if base:IsA("Model") then
            local sign = base:FindFirstChild("PlotSign")
            local label = sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Frame") and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
            if label and (string.find(label.Text, player.Name) or string.find(label.Text, player.DisplayName)) then
                cachedMyBase = base
                return base
            end
        end
    end
    return nil
end

local function isEnemyPlot(plot)
    if not plot or not plot:IsA("Model") then return false end
    local sign = plot:FindFirstChild("PlotSign")
    local sg = sign and sign:FindFirstChild("SurfaceGui")
    local frame = sg and sg:FindFirstChild("Frame")
    local label = frame and frame:FindFirstChild("TextLabel")
    if not label or label.Text == "Empty Base" then return false end
    local owner = label.Text:gsub("'s [Bb]ase$", ""):gsub("%s+$", "")
    return owner ~= player.Name and owner ~= player.DisplayName
end

local SLOT_CONFIGS

-- Referencias fijas de los dos lados del mapa
local BASE_REF_B1 = Vector3.new(-337, -5, 100)
local BASE_REF_B2 = Vector3.new(-335, -5, 20)

local function plotSide(plot)
    if not plot then return nil end
    local pos = plot.PrimaryPart and plot.PrimaryPart.Position or plot:GetPivot().Position
    if (pos - BASE_REF_B1).Magnitude < (pos - BASE_REF_B2).Magnitude then return "b1" end
    return "b2"
end

-- Detecta MI base (por el cartel) y devuelve mi lado del mapa
local function getMySide()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:IsA("Model") then
            local sign = plot:FindFirstChild("PlotSign")
            local sg = sign and sign:FindFirstChild("SurfaceGui")
            local frame = sg and sg:FindFirstChild("Frame")
            local label = frame and frame:FindFirstChild("TextLabel")
            if label and label.Text ~= "Empty Base" then
                local owner = label.Text:gsub("'s [Bb]ase$", ""):gsub("%s+$", "")
                if owner == player.Name or owner == player.DisplayName then
                    return plotSide(plot)
                end
            end
        end
    end
    return nil
end

-- Lado enemigo = el opuesto a mi base (no depende de dónde esté parado ni de la cámara)
local function getEnemySide()
    local mine = getMySide()
    if mine == "b1" then return "b2" end
    if mine == "b2" then return "b1" end
    return nil
end

-- Solo plots enemigos que están en el lado enemigo del mapa
local function isTargetPlot(plot)
    if not isEnemyPlot(plot) then return false end
    local enemySide = getEnemySide()
    if not enemySide then return true end
    return plotSide(plot) == enemySide
end

local darkBlueHighlight = Instance.new("Highlight")
darkBlueHighlight.Name = "Masa_Purple_Podium_Highlight"
darkBlueHighlight.FillColor = Color3.fromRGB(60, 10, 120)
darkBlueHighlight.OutlineColor = Color3.fromRGB(170, 100, 255)
darkBlueHighlight.FillTransparency = 0.35
darkBlueHighlight.OutlineTransparency = 0

-- Devuelve el podio de la base enemiga (lado fijo) para el slot seleccionado
local function pickPodiumForPlot(plot, cfg)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local side = plotSide(plot)
    local podSlots = cfg.podSlots
    local grabRef = cfg.grab
    if not podSlots and not grabRef then podSlots = {"1", "10"} end

    if podSlots then
        local primary = (side == "b1") and podSlots[1] or (podSlots[2] or podSlots[1])
        local secondary = (side == "b1") and (podSlots[2] or podSlots[1]) or podSlots[1]
        return podiums:FindFirstChild(primary) or podiums:FindFirstChild(secondary)
    end

    local ref = (side == "b1") and grabRef.b1 or grabRef.b2
    local nearest, nd = nil, math.huge
    for _, podium in ipairs(podiums:GetChildren()) do
        local cm = podium:FindFirstChild("Claim") and podium.Claim:FindFirstChild("Main")
        if cm then
            local d = (cm.Position - ref).Magnitude
            if d < nd then nd, nearest = d, podium end
        end
    end
    return nearest
end

local function getTargetPodiumForSlot(slot)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end

    local cfg = SLOT_CONFIGS and (SLOT_CONFIGS[slot] or SLOT_CONFIGS[1])
    if not cfg then return nil end

    for _, plot in ipairs(plots:GetChildren()) do
        if isTargetPlot(plot) then
            local podium = pickPodiumForPlot(plot, cfg)
            if podium and podium:FindFirstChildWhichIsA("ProximityPrompt", true) then
                return podium
            end
        end
    end
    return nil
end

-- Devuelve el nombre del animal/brainrot que esta en el slot seleccionado.
local function getSlotTargetName()
    local podium = getTargetPodiumForSlot(selectedSlot)
    if not podium then return "None" end

    local GENERIC = { [""] = true, ["steal"] = true, ["steal brainrot"] = true, ["brainrot"] = true, ["interact"] = true, ["claim"] = true, ["collect"] = true,
        ["base"] = true, ["empty base"] = true, ["empty"] = true, ["podium"] = true, ["animalpodium"] = true, ["spawn"] = true, ["platform"] = true, ["none"] = true }

    local IGNORED_PARTS = { ["base"] = true, ["claim"] = true, ["podium"] = true, ["platform"] = true, ["spawn"] = true, ["hitbox"] = true,
        ["main"] = true, ["stand"] = true, ["display"] = true, ["decorations"] = true, ["decoration"] = true, ["decor"] = true,
        ["effects"] = true, ["effect"] = true, ["particles"] = true, ["lights"] = true, ["light"] = true, ["model"] = true,
        ["part"] = true, ["mesh"] = true, ["meshpart"] = true, ["union"] = true, ["folder"] = true, ["gui"] = true,
        ["billboard"] = true, ["attachment"] = true, ["sign"] = true, ["sound"] = true, ["animals"] = true, ["animal"] = true,
        ["overhead"] = true, ["info"] = true, ["glow"] = true, ["floor"] = true, ["cover"] = true, ["lock"] = true, ["locked"] = true }

    local prompt = podium:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        for _, field in ipairs({ "ObjectText", "ActionText" }) do
            local t = prompt[field]
            if typeof(t) == "string" then
                local stripped = t:gsub("^%s*[Ss]teal%s+", ""):gsub("%s+$", "")
                if stripped ~= "" and not GENERIC[stripped:lower()] then
                    return stripped
                end
            end
        end
    end

    for _, c in ipairs(podium:GetChildren()) do
        if (c:IsA("Model") or c:IsA("Tool") or c:IsA("MeshPart")) and c.Name ~= podium.Name
            and not IGNORED_PARTS[c.Name:lower()] and not GENERIC[c.Name:lower()] then
            return c.Name
        end
    end
    for _, d in ipairs(podium:GetDescendants()) do
        if d:IsA("Model") and d.Name ~= podium.Name
            and not IGNORED_PARTS[d.Name:lower()] and not GENERIC[d.Name:lower()] then
            return d.Name
        end
    end

    -- Podio vacio (sin animal): muestra None
    return "None"
end


task.spawn(function()
    while task.wait(0.4) do
        local targetPodium = getTargetPodiumForSlot(selectedSlot)
        if targetPodium then
            if darkBlueHighlight.Adornee ~= targetPodium or darkBlueHighlight.Parent ~= targetPodium then
                darkBlueHighlight.Adornee = targetPodium
                darkBlueHighlight.Parent = targetPodium
            end
        else
            darkBlueHighlight.Adornee = nil
            darkBlueHighlight.Parent = nil
        end
    end
end)

local function isInsideHitbox(part, pos)
    if not part or not pos then return false end
    local rel = part.CFrame:PointToObjectSpace(pos)
    local s = part.Size
    return math.abs(rel.X) <= s.X/2 and math.abs(rel.Y) <= s.Y/2 and math.abs(rel.Z) <= s.Z/2
end

local FFlags = {
    GameNetPVHeaderRotationalVelocityZeroCutoffExponent = -5000, LargeReplicatorWrite5 = true,
    LargeReplicatorEnabled9 = true, AngularVelociryLimit = 360,
    TimestepArbiterVelocityCriteriaThresholdTwoDt = 2147483646, S2PhysicsSenderRate = 15000,
    DisableDPIScale = true, MaxDataPacketPerSend = 2147483647, PhysicsSenderMaxBandwidthBps = 20000,
    TimestepArbiterHumanoidLinearVelThreshold = 21, MaxMissedWorldStepsRemembered = -2147483648,
    PlayerHumanoidPropertyUpdateRestrict = true, SimDefaultHumanoidTimestepMultiplier = 0,
    StreamJobNOUVolumeLengthCap = 2147483647, DebugSendDistInSteps = -2147483648,
    GameNetDontSendRedundantNumTimes = 1, CheckPVLinearVelocityIntegrateVsDeltaPositionThresholdPercent = 1,
    CheckPVDifferencesForInterpolationMinVelThresholdStudsPerSecHundredth = 1,
    LargeReplicatorSerializeRead3 = true, ReplicationFocusNouExtentsSizeCutoffForPauseStuds = 2147483647,
    CheckPVCachedVelThresholdPercent = 10, CheckPVDifferencesForInterpolationMinRotVelThresholdRadsPerSecHundredth = 1,
    GameNetDontSendRedundantDeltaPositionMillionth = 1, InterpolationFrameVelocityThresholdMillionth = 5,
    StreamJobNOUVolumeCap = 2147483647, InterpolationFrameRotVelocityThresholdMillionth = 5,
    CheckPVCachedRotVelThresholdPercent = 10, WorldStepMax = 30,
    InterpolationFramePositionThresholdMillionth = 5, TimestepArbiterHumanoidTurningVelThreshold = 1,
    SimOwnedNOUCountThresholdMillionth = 2147483647, GameNetPVHeaderLinearVelocityZeroCutoffExponent = -5000,
    NextGenReplicatorEnabledWrite4 = true, TimestepArbiterOmegaThou = 1073741823, MaxAcceptableUpdateDelay = 1,
    LargeReplicatorSerializeWrite4 = true
}

local setFFlags = function()
    if type(setfflag) ~= "function" then return end
    for name, value in pairs(FFlags) do pcall(function() setfflag(tostring(name), tostring(value)) end) end
end

local ALLOWED_GEARS = {"FlyingCarpet", "Witch'sBroom", "Cupid'sWings", "Santa'sSleigh", "Waverider"}
local MOUNT_PRIORITY = {"Flying Carpet", "FlyingCarpet", "Witch's Broom", "Witch'sBroom", "WitchBroom", "Cupid's Wings", "Cupid'sWings", "CupidWings", "Santa's Sleigh", "Santa'sSleigh", "SantaSleigh", "Waverider"}

local function isAllowedGear(gearName)
    local cleanName = gearName:lower():gsub("[%s'%_%-]", "")
    for _, allowed in ipairs(ALLOWED_GEARS) do
        if cleanName == allowed:lower():gsub("[%s'%_%-]", "") then return true end
    end
    return false
end

local function getPriorityIndex(gearName)
    local cleanName = gearName:lower():gsub("[%s'%_%-]", "")
    for index, priorityName in ipairs(MOUNT_PRIORITY) do
        if cleanName == priorityName:lower():gsub("[%s'%_%-]", "") then return index end
    end
    return 9999
end

local function getInventoryGears()
    local gears, added = {}, {}
    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and isAllowedGear(item.Name) and not added[item.Name] then
                added[item.Name] = true
                table.insert(gears, item.Name)
            end
        end
    end
    scan(LocalPlayer:FindFirstChild("Backpack"))
    scan(LocalPlayer.Character)
    table.sort(gears, function(a, b)
        local pA, pB = getPriorityIndex(a), getPriorityIndex(b)
        return pA ~= pB and pA < pB or a < b
    end)
    return gears
end

local function getDefaultGearFromInventory()
    local inventory = getInventoryGears()
    return #inventory > 0 and inventory[1] or "Sin Gear"
end

local function findToolFlexible(container, toolName)
    if not container or not toolName then return nil end
    local exact = container:FindFirstChild(toolName)
    if exact and exact:IsA("Tool") then return exact end
    local cleanTarget = toolName:lower():gsub("[%s'%_%-]", "")
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") and child.Name:lower():gsub("[%s'%_%-]", "") == cleanTarget then return child end
    end
    return nil
end

local function EquipTargetTool(toolName)
    local character = LocalPlayer.Character
    if not character or not toolName then return nil end
    local equipped = findToolFlexible(character, toolName)
    if equipped then return equipped end
    local toolInBackpack = findToolFlexible(LocalPlayer:FindFirstChild("Backpack"), toolName)
    if toolInBackpack then
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum then hum:EquipTool(toolInBackpack) end
        return toolInBackpack
    end
    return nil
end

local function EquipBestMount()
    local chosenGear = HubConfig.selectedGear
    if not chosenGear or chosenGear == "Auto" or chosenGear == "" then
        chosenGear = getDefaultGearFromInventory()
    end
    if chosenGear and chosenGear ~= "Sin Gear" and chosenGear ~= "Auto" then
        local equipped = EquipTargetTool(chosenGear)
        if equipped then return equipped end
    end
    for _, mountName in ipairs(MOUNT_PRIORITY) do
        local equipped = EquipTargetTool(mountName)
        if equipped then return equipped end
    end
    return nil
end

local function SSEquipGrapple() EquipBestMount() end

local walkTo = function(hrp, targetCords, desiredSpeed, precisionThreshold, noGear)
    if not hrp or not hrp.Parent or not targetCords then return end
    desiredSpeed = desiredSpeed or 180
    local running = true
    local connection
    local threshold = precisionThreshold or 3

    local _ctrls
    pcall(function() _ctrls = require(player.PlayerScripts:WaitForChild("PlayerModule", 2)):GetControls() end)
    if _ctrls then pcall(function() _ctrls:Disable() end) end

    connection = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or not running then
            if connection then connection:Disconnect() end
            return
        end
        local currentPos  = hrp.Position
        local flatCurrent = Vector3.new(currentPos.X, targetCords.Y, currentPos.Z)
        local direction   = targetCords - flatCurrent
        local distance    = direction.Magnitude
        if distance <= threshold then
            running = false
            connection:Disconnect()
            hrp.Velocity = Vector3.zero
            return
        end
        if not noGear then EquipBestMount() end
        local vel = direction.Unit * desiredSpeed
        hrp.Velocity = Vector3.new(vel.X, hrp.Velocity.Y, vel.Z)
    end)

    local startT = tick()
    while running do
        if tick() - startT > 6 then break end
        task.wait()
    end

    if _ctrls then pcall(function() _ctrls:Enable() end) end
end

local function flyTo(hrp, targetPos, speed)
    if not hrp or not hrp.Parent or not targetPos then return end
    speed = speed or 160

    local _ctrls
    pcall(function() _ctrls = require(player.PlayerScripts:WaitForChild("PlayerModule", 2)):GetControls() end)
    if _ctrls then pcall(function() _ctrls:Disable() end) end

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        local carpet = findToolFlexible(char, "flying carpet") or findToolFlexible(player:FindFirstChild("Backpack"), "flying carpet") or findToolFlexible(char, "carpet") or findToolFlexible(player:FindFirstChild("Backpack"), "carpet")
        if carpet then
            pcall(function() hum:UnequipTools() end)
            task.wait(0.03)
            pcall(function() hum:EquipTool(carpet) end)
        else
            EquipBestMount()
        end
    end

    local oldV = hrp:FindFirstChild("LinearVelocity"); if oldV then oldV:Destroy() end
    local oldA = hrp:FindFirstChild("Attachment"); if oldA then oldA:Destroy() end

    local attachment = Instance.new("Attachment")
    attachment.Parent = hrp
    local velocity = Instance.new("LinearVelocity")
    velocity.Attachment0 = attachment
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.MaxForce = 50000
    velocity.Parent = hrp

    local running = true
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or not running then
            if connection then connection:Disconnect() end
            return
        end
        local dir = targetPos - hrp.Position
        local dist = dir.Magnitude
        if dist <= 3.5 then
            running = false
            connection:Disconnect()
            velocity.VectorVelocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(targetPos)
            return
        end
        local speedMult = dist < 12 and math.max(0.15, dist / 12) or 1
        velocity.VectorVelocity = dir.Unit * speed * speedMult
    end)

    local startT = tick()
    while running do
        if tick() - startT > 8 then break end
        task.wait()
    end

    if velocity and velocity.Parent then velocity:Destroy() end
    if attachment and attachment.Parent then attachment:Destroy() end
    if hrp and hrp.Parent then hrp.AssemblyLinearVelocity = Vector3.zero end
    if _ctrls then pcall(function() _ctrls:Enable() end) end
end

local function walkToLinear(HRP, targetPos, speed, arriveDist, timeout)
    if not HRP or not HRP.Parent or not targetPos then return end
    speed = speed or 28
    arriveDist = arriveDist or 6
    timeout = timeout or 6

    local attachment = Instance.new("Attachment")
    attachment.Parent = HRP

    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.MaxForce = 100000
    linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    linearVelocity.Attachment0 = attachment
    linearVelocity.Parent = HRP

    local start = tick()
    while HRP and HRP.Parent do
        local d = targetPos - HRP.Position
        local flat = Vector3.new(d.X, 0, d.Z)
        local mag = flat.Magnitude
        if mag < arriveDist or tick() - start > timeout then break end
        local dir = flat.Unit
        linearVelocity.VectorVelocity = Vector3.new(dir.X * speed, 0, dir.Z * speed)
        task.wait()
    end

    linearVelocity.VectorVelocity = Vector3.zero
    linearVelocity:Destroy()
    attachment:Destroy()

    if HRP and HRP.Parent then HRP.AssemblyLinearVelocity = Vector3.zero end
end

local function runAutoWalkLogic(HRP, midPos)
    if not HRP or not HRP.Parent then return end
    detectStealAndWait()

    local prevSpeedState = _G.speedBoostEnabled
    _G.speedBoostEnabled = false

    pcall(function()
        local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if h then h:UnequipTools() end
    end)

    local speedVal = PotionEnabled and 33 or 28
    if midPos then walkToLinear(HRP, midPos, speedVal, 3, 6) end

    local myBase = findMyBase()
    if myBase then
        local basePos = myBase:GetPivot().Position
        local closestHitbox = nil
        local shortestDistance = math.huge

        for _, obj in pairs(myBase:GetDescendants()) do
            if obj.Name == "DeliveryHitbox" and obj:IsA("BasePart") then
                local dist = (obj.Position - basePos).Magnitude
                if dist < shortestDistance then
                    shortestDistance = dist
                    closestHitbox = obj
                end
            end
        end

        if closestHitbox then walkToLinear(HRP, closestHitbox.Position, speedVal, 6, 6) end
    end

    _G.speedBoostEnabled = prevSpeedState
end

local canDirectTp = function(HRP, targetPos)
    if not HRP or not targetPos then return false end
    -- Si hay mucha diferencia de altura no es un tramo "directo" (hay que volar)
    if math.abs(targetPos.Y - HRP.Position.Y) > 6 then return false end
    local origin = HRP.Position
    local ignored = { player.Character }
    for _ = 1, 12 do
        local direction = targetPos - origin
        if direction.Magnitude <= 0.05 then return true end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Blacklist
        params.FilterDescendantsInstances = ignored
        params.IgnoreWater = true
        local result = Workspace:Raycast(origin, direction, params)
        if not result then return true end
        local hit = result.Instance
        if not hit then return true end
        if hit:IsA("BasePart") and not hit.CanCollide then
            table.insert(ignored, hit)
            origin = result.Position + direction.Unit * 0.1
        else
            return (result.Position - targetPos).Magnitude <= 3
        end
    end
    return false
end

local function ExecuteAutoPotion()
    if PotionEnabled or APOnStealEnabled then
        local potion = player.Backpack:FindFirstChild("Giant Potion") or player.Character:FindFirstChild("Giant Potion")
        if potion then
            player.Character.Humanoid:EquipTool(potion)
            potion:Activate()
        end
    end
end

local __stealCbCache_v2 = setmetatable({}, { __mode = "k" })
local __buildStealCallbacks_v2 = function(prompt)
    if type(getconnections) ~= "function" then return nil end
    if __stealCbCache_v2[prompt] then return __stealCbCache_v2[prompt] end
    local data = { hold = {}, trigger = {} }
    local ok1, c1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 then for _, c in ipairs(c1) do if type(c.Function) == "function" then table.insert(data.hold, c.Function) end end end
    local ok2, c2 = pcall(getconnections, prompt.Triggered)
    if ok2 then for _, c in ipairs(c2) do if type(c.Function) == "function" then table.insert(data.trigger, c.Function) end end end
    if #data.hold == 0 and #data.trigger == 0 then return nil end
    __stealCbCache_v2[prompt] = data
    return data
end

local __FH_v2 = {}
function __FH_v2.startStealHold(prompt)
    if not prompt or not prompt.Parent then return nil end
    local cb = __buildStealCallbacks_v2(prompt)
    if not cb then return nil end
    for _, fn in ipairs(cb.hold) do task.spawn(fn) end
    local now = tick()
    return { prompt = prompt, cb = cb, ragdollFireTime = now, startedAt = now, holdBeganAt = now, holdDone = true }
end

function __FH_v2.doHoldAndWait(ctx)
    if ctx.holdDone then return end
    for _, fn in ipairs(ctx.cb.hold) do task.spawn(fn) end
    ctx.holdBeganAt = tick()
    task.wait(1.3)
    ctx.holdDone = true
end

function __FH_v2.waitForStealTime(ctx, sec)
    if not ctx or sec >= 1.0 then return end
    local elapsed = tick() - ctx.ragdollFireTime
    if elapsed < sec then task.wait(sec - elapsed) end
end

function __FH_v2.finishStealHold(ctx)
    if not ctx then return false end
    if not ctx.holdBeganAt then __FH_v2.doHoldAndWait(ctx) end
    local heldFor = tick() - (ctx.holdBeganAt or tick())
    if heldFor < 1.3 then task.wait(1.3 - heldFor) end
    task.wait(0.02)
    for _, fn in ipairs(ctx.cb.trigger) do task.spawn(fn) end
    return true
end

local BASES = {
    b1 = { refVec = Vector3.new(-337, -5, 100), finalPos = Vector3.new(-337, -5, 103) }, 
    b2 = { refVec = Vector3.new(-335, -5, 20),  finalPos = Vector3.new(-334.80, -5.04, 18.90) }, 
}

SLOT_CONFIGS = {
    [1] = {
        podSlots = {"1", "10"},
        b1 = { waypoints = { Vector3.new(-352.51, -6.35, 6.89), Vector3.new(-353.11, -6.46, 113.28), Vector3.new(-333.95, -4.62, 100.70) }, greenPos = Vector3.new(-349.87, -6.52, 82.97) },
        b2 = { waypoints = { Vector3.new(-352.76, -6.38, 114.06), Vector3.new(-351.49, -6.38, 7.00), Vector3.new(-334.80, -5.04, 18.90) }, greenPos = Vector3.new(-349.42, -6.52, 37.47) }
    },
    [2] = {
        grab = { b1 = Vector3.new(-323.62, -4.87, 94.83), b2 = Vector3.new(-323.81, -4.76, 24.58) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-327.32, -5.37, 95.53) }, greenPos = Vector3.new(-347.00, -7.27, 96.85) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-327.74, -5.26, 23.78) }, greenPos = Vector3.new(-344.99, -7.16, 26.28) }
    },
    [3] = {
        podSlots = {"3", "8"},
        b1 = { waypoints = { Vector3.new(-352.56, -6.35, 6.43), Vector3.new(-352.50, -6.35, 113.92), Vector3.new(-319.34, -4.62, 99.20) }, greenPos = Vector3.new(-345.00, -6.52, 92.00) },
        b2 = { waypoints = { Vector3.new(-352.76, -6.38, 114.06), Vector3.new(-352.72, -6.38, 6.30), Vector3.new(-319.81, -4.62, 20.98) }, greenPos = Vector3.new(-344.00, -6.52, 29.00) }
    },
    [4] = {
        podSlots = {"4", "7"},
        b1 = { waypoints = { Vector3.new(-352.70, -6.38, 6.47), Vector3.new(-352.59, -6.35, 113.35), Vector3.new(-311.25, -4.57, 98.98) }, greenPos = Vector3.new(-337.58, -4.42, 91.88) },
        b2 = { waypoints = { Vector3.new(-352.76, -6.38, 114.06), Vector3.new(-352.75, -6.38, 6.15), Vector3.new(-312.58, -4.62, 20.83) }, greenPos = Vector3.new(-336.70, -4.62, 28.20) }
    },
    [5] = {
        podSlots = {"5", "6"},
        b1 = { waypoints = { Vector3.new(-352.76, -6.74, 7.06), Vector3.new(-352.76, -6.74, 114.06), Vector3.new(-303.58, -4.78, 102.00) }, greenPos = Vector3.new(-331.30, -4.58, 93.20) },
        b2 = { waypoints = { Vector3.new(-352.76, -6.74, 114.06), Vector3.new(-352.76, -6.74, 7.06), Vector3.new(-303.48, -4.83, 17.91) }, greenPos = Vector3.new(-330.40, -4.53, 26.60) }
    },
    [6] = {
        grab = { b1 = Vector3.new(-301.05, -4.87, 131.80), b2 = Vector3.new(-331.58, -4.76, -11.37) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-301.45, -5.12, 126.61) }, greenPos = Vector3.new(-311.91, -5.37, 116.65) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-335.76, -5.26, -9.52) }, greenPos = Vector3.new(-345.10, -6.86, -0.77) }
    },
    [7] = {
        grab = { b1 = Vector3.new(-308.95, -4.87, 132.27), b2 = Vector3.new(-324.12, -4.76, -10.94) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-310.69, -5.12, 126.77) }, greenPos = Vector3.new(-318.30, -5.37, 117.26) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-326.93, -5.26, -7.11) }, greenPos = Vector3.new(-330.14, -5.26, 3.02) }
    },
    [8] = {
        grab = { b1 = Vector3.new(-316.43, -4.87, 131.69), b2 = Vector3.new(-316.07, -4.76, -11.31) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-318.12, -5.12, 125.58) }, greenPos = Vector3.new(-325.05, -5.37, 117.70) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-316.66, -5.06, -5.03) }, greenPos = Vector3.new(-323.05, -5.26, 4.12) }
    },
    [9] = {
        grab = { b1 = Vector3.new(-323.99, -4.87, 131.62), b2 = Vector3.new(-308.89, -4.76, -11.27) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-325.46, -5.12, 125.92) }, greenPos = Vector3.new(-335.57, -5.37, 116.43) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-310.28, -5.01, -5.47) }, greenPos = Vector3.new(-316.93, -5.26, 1.19) }
    },
    [10] = {
        grab = { b1 = Vector3.new(-331.34, -4.87, 131.85), b2 = Vector3.new(-301.45, -4.76, -11.07) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-333.38, -5.12, 126.12) }, greenPos = Vector3.new(-345.51, -6.87, 118.15) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-303.55, -5.11, -5.47) }, greenPos = Vector3.new(-310.47, -5.26, 0.60) }
    },
    [11] = {
        grab = { b1 = Vector3.new(-331.20, 13.13, 95.86), b2 = Vector3.new(-331.29, 13.24, -10.88) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-330.78, 6, 94.89) }, greenPos = Vector3.new(-343.47, -7.27, 97.07) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-331.92, 5.24, -15.30) }, greenPos = Vector3.new(-344.39, -7.16, -15.11) }
    },
    [12] = {
        grab = { b1 = Vector3.new(-331.20, 13.13, 95.86), b2 = Vector3.new(-323.97, 13.24, -10.87) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-323.71, 6, 94.51) }, greenPos = Vector3.new(-344.05, -7.27, 98.61) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-324.16, 5.24, -15.10) }, greenPos = Vector3.new(-345.10, -7.16, -10.35) }
    },
    [13] = {
        grab = { b1 = Vector3.new(-316.21, 13.13, 96.09), b2 = Vector3.new(-316.60, 13.24, -10.95) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-316.75, 6, 96.26) }, greenPos = Vector3.new(-325.61, -4.87, 96.06) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-317.35, 5.24, -14.98) }, greenPos = Vector3.new(-328.77, -5.01, -12.06) }
    },
    [14] = {
        grab = { b1 = Vector3.new(-309.03, 13.13, 95.84), b2 = Vector3.new(-308.94, 13.24, -11.24) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-312.86, 5.24, 97.53) }, greenPos = Vector3.new(-328.82, -5.12, 96.22) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-309.42, 5.24, -15.15) }, greenPos = Vector3.new(-319.79, -5.26, -11.06) }
    },
    [15] = {
        grab = { b1 = Vector3.new(-301.03, 13.13, 95.45), b2 = Vector3.new(-301.38, 13.24, -11.37) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-301.73, 6, 99.70) }, greenPos = Vector3.new(-314.93, -4.87, 96.29) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-302.82, 5.24, -14.83) }, greenPos = Vector3.new(-314.20, -5.01, -11.40) }
    },
    [16] = {
        grab = { b1 = Vector3.new(-331.54, 13.08, 130.61), b2 = Vector3.new(-331.39, 13.19, 23.74) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-331.48, 6, 129.46) }, greenPos = Vector3.new(-344.41, -7.27, 131.44) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-331.34, 5.24, 28.39) }, greenPos = Vector3.new(-345.52, -7.16, 24.30) }
    },
    [17] = {
        grab = { b1 = Vector3.new(-324.14, 13.13, 130.98), b2 = Vector3.new(-323.67, 13.24, 24.91) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-323.83, 6, 129.60) }, greenPos = Vector3.new(-343.86, -7.27, 132.08) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-323.28, 5.24, 28.10) }, greenPos = Vector3.new(-337.32, -5.26, 24.37) }
    },
    [18] = {
        grab = { b1 = Vector3.new(-316.62, 13.13, 131.50), b2 = Vector3.new(-316.54, 13.24, 24.40) },
        b1 = { waypoints = { Vector3.new(-352.76, -7.18, 7.06), Vector3.new(-353.03, -7.18, 113.20), Vector3.new(-315.83, 6, 132.49) }, greenPos = Vector3.new(-331.34, -4.87, 132.05) },
        b2 = { waypoints = { Vector3.new(-352.76, -7.18, 114.06), Vector3.new(-352.59, -7.12, 13.95), Vector3.new(-316.85, 5.24, 27.92) }, greenPos = Vector3.new(-328.71, -5.01, 24.78) }
    }
}

local HalfwaySteal = { debounce = false, _semiStealCtx = nil } 

function HalfwaySteal.setSlot(slot)
    if slot >= 1 and slot <= 18 then 
        selectedSlot = slot 
        HubConfig.selectedSlot = slot 
        saveHubConfig()
    end
end

function HalfwaySteal.SSDoTeleport()
    local char = player.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    setFFlags()
    SSEquipGrapple()

    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end

    local slotCfg = SLOT_CONFIGS[selectedSlot] or SLOT_CONFIGS[1]
    local podSlots = slotCfg.podSlots
    local grabRef = slotCfg.grab
    if not podSlots and not grabRef then podSlots = {"1", "10"} end

    local enemyPlots = {}
    for _, plot in ipairs(plots:GetChildren()) do
        if isTargetPlot(plot) then table.insert(enemyPlots, plot) end
    end
    if #enemyPlots == 0 then return end

    local function getClosestPodium()
        for _, plot in ipairs(enemyPlots) do
            local podium = pickPodiumForPlot(plot, slotCfg)
            if podium then
                local prompt = podium:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then
                    local cm = podium:FindFirstChild("Claim") and podium.Claim:FindFirstChild("Main")
                    local cmPos = cm and cm.Position or (podium.PrimaryPart and podium.PrimaryPart.Position or podium:GetPivot().Position)
                    return {
                        plot = plot,
                        podiumName = podium.Name,
                        position = cmPos,
                        prompt = prompt,
                        distance = (hrp.Position - cmPos).Magnitude,
                        isEnemyBase1 = (plotSide(plot) == "b1"),
                    }
                end
            end
        end
        return nil
    end


    local podium = getClosestPodium()
    if not podium then return end

    local function doTpSequence(HRP, pod)
        local config = pod.isEnemyBase1 and slotCfg.b1 or slotCfg.b2
        local greenPos = config and config.greenPos or (pod.isEnemyBase1 and Vector3.new(-349.87, -6.52, 82.97) or Vector3.new(-349.42, -6.52, 37.47))
        local waypoints = config and config.waypoints or (pod.isEnemyBase1 and {Vector3.new(-352.51, -6.35, 6.89), Vector3.new(-353.11, -6.46, 113.28), Vector3.new(-333.95, -4.62, 100.70)} or {Vector3.new(-352.76, -6.38, 114.06), Vector3.new(-351.49, -6.38, 7.00), Vector3.new(-334.80, -5.04, 18.90)})

        -- Distancia maxima para considerar un "atajo" real. Sin este limite el raycast
        -- daba linea libre por encima/por debajo del mapa y el recorrido se saltaba
        -- el pasillo, rompiendose en varios slots.
        local SKIP_MAX_DIST = 40

        local function computeStartIndex(HRP_)
            if not HRP_ or not HRP_.Parent then return 1 end
            -- Nunca se salta al ultimo waypoint: el tramo final siempre se recorre.
            for i = #waypoints - 1, 1, -1 do
                local wp = waypoints[i]
                if (wp - HRP_.Position).Magnitude <= SKIP_MAX_DIST and canDirectTp(HRP_, wp) then
                    return i
                end
            end
            return 1
        end

        local function doApproachPath(HRP_, startIndex)
            startIndex = startIndex or computeStartIndex(HRP_)
            for i = startIndex, #waypoints do
                local wp = waypoints[i]
                if wp.Y - HRP_.Position.Y > 3 then
                    flyTo(HRP_, wp, 160)
                else
                    walkTo(HRP_, wp, 180)
                end
            end
        end

        local ctx = nil
        if pod and pod.prompt and pod.prompt.Parent then
            pod.prompt.RequiresLineOfSight = false
            pod.prompt.MaxActivationDistance = math.huge
            if type(getconnections) == "function" then
                ctx = __FH_v2.startStealHold(pod.prompt)
                -- admin spam: キャラを実際につかんだ（Stealing状態になった）時に発動
                if ctx and APOnStealEnabled then
                    task.spawn(function()
                        local startCheck = tick()
                        while tick() - startCheck < 2.0 do
                            task.wait(0.05)
                            if player:GetAttribute("Stealing") then
                                doSpam()
                                break
                            end
                        end
                    end)
                end
            else
                task.spawn(function() if fireproximityprompt then fireproximityprompt(pod.prompt) end end)
            end
        end

        if ctx then __FH_v2.waitForStealTime(ctx, 0.1) end

        -- === SEMI TP TIMING SYNC: llegada a coordenada 3 en ~1.22s ===
        local SEMI_TP_TARGET = 1.2
        local timingStart = tick()

        -- Se usa el MISMO indice de inicio que usara el recorrido real, asi la
        -- estimacion de tiempo coincide con el camino que se ejecuta.
        local syncStartIndex = computeStartIndex(HRP)

        -- Estimacion por tramo: los tramos de vuelo van a 160 y los de suelo a 180.
        local estTravel = 0
        local prevPos = HRP.Position
        for i = syncStartIndex, #waypoints do
            local wp = waypoints[i]
            local segDist = (wp - prevPos).Magnitude
            local isFly = (wp.Y - prevPos.Y) > 3
            estTravel = estTravel + segDist / (isFly and 160 or 180)
            prevPos = wp
        end

        local startDelay = SEMI_TP_TARGET - estTravel - (tick() - timingStart)
        if startDelay > 0 then task.wait(startDelay) end

        doApproachPath(HRP, syncStartIndex)
        task.wait(0.25)
        
        ExecuteAutoPotion()
        SSEquipGrapple()

        if pod and pod.prompt and pod.prompt.Parent then
            if greenPos then
                if ctx then __FH_v2.waitForStealTime(ctx, 1.3) end
                HRP.CFrame = CFrame.new(greenPos)
            end
            if ctx then __FH_v2.finishStealHold(ctx) end
        end

        if AutoWalkEnabled then
            local midPos = (selectedSlot == 4 or selectedSlot == 5) and (pod.isEnemyBase1 and Vector3.new(-346.51, -6.52, 94.05) or Vector3.new(-345.94, -6.52, 26.71)) or nil
            runAutoWalkLogic(HRP, midPos)
        end
    end

    task.spawn(function() pcall(function() doTpSequence(hrp, podium) end) end)
end

local TeleportBtn = nil

function HalfwaySteal.execute()
    if player:GetAttribute("Stealing") or HalfwaySteal.debounce then return end
    HalfwaySteal.debounce = true
    if setStealingStatus then setStealingStatus(true) end
    
    -- admin spam はキャラをつかんだ瞬間に発動（下記 doTpSequence 内）
    
    task.spawn(function()
        setFFlags()
        HalfwaySteal.SSDoTeleport()
        task.wait(0.1)
        HalfwaySteal.debounce = false
        -- La barra vuelve a "Target" sola cuando expira la ventana de robo
        if setStealingStatus then setStealingStatus(false) end
    end)
end

local function checkEnemyBaseOpen()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end

    for _, plot in ipairs(plots:GetChildren()) do
        if isEnemyPlot(plot) then
            for _, desc in ipairs(plot:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and string.find(desc.ObjectText, "Disallow") then
                    return true
                end
            end
        end
    end
    return false
end

local hasAutoTPTriggered = false
task.spawn(function()
    while task.wait(1.5) do
        if checkEnemyBaseOpen() then
            if AutoTPOnAllowEnabled and not hasAutoTPTriggered and not HalfwaySteal.debounce and not player:GetAttribute("Stealing") then
                hasAutoTPTriggered = true
                HalfwaySteal.execute()
            end
        else
            hasAutoTPTriggered = false
        end
    end
end)

-- ==========================================
-- INSTANT RESET (ADAPTATIVO)
-- ==========================================
local INSTANT_RESET_STUDS = 1000000000
local resetLockConn = nil

local doReset = function()
    local local_player = player
    if not local_player then return end

    local char = local_player.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    -- Equipa dinámicamente la misma gear/montura seleccionada en el Semi TP
    local tool = EquipBestMount()
    if not tool then return end

    local lockedCFrame = hrp.CFrame + Vector3.new(0, INSTANT_RESET_STUDS, 0)

    if resetLockConn then
        pcall(function() resetLockConn:Disconnect() end)
        resetLockConn = nil
    end

    resetLockConn = RunService.Heartbeat:Connect(function()
        local currentChar = local_player.Character
        if not currentChar then
            if resetLockConn then resetLockConn:Disconnect() resetLockConn = nil end
            return
        end

        local currentHrp = currentChar:FindFirstChild("HumanoidRootPart")
        local currentHum = currentChar:FindFirstChildOfClass("Humanoid")

        if currentHrp and currentHrp ~= hrp then
            if resetLockConn then resetLockConn:Disconnect() resetLockConn = nil end
            return
        end

        if currentHrp and currentHum and currentHum.Health > 0 then
            currentHrp.CFrame = lockedCFrame
        else
            if resetLockConn then resetLockConn:Disconnect() resetLockConn = nil end
        end
    end)
end

function HalfwaySteal.activate()
    task.spawn(function()
        setFFlags()
        doReset()
    end)
end

-- ==========================================
-- INTERFAZ FLOTANTE / ALLOW DISALLOW
-- ==========================================
local AllowDisallowGui = Instance.new("ScreenGui")
AllowDisallowGui.Name = "MasaAllowDisallow"
AllowDisallowGui.ResetOnSpawn = false
AllowDisallowGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
AllowDisallowGui.Parent = safeGuiTarget

local function ApplyFastEffects(parentFrame)
    local uiStroke = Instance.new("UIStroke")
    uiStroke.Thickness = 1.2
    uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    uiStroke.Color = COLOR_BORDER
    uiStroke.Parent = parentFrame

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 100, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 50, 140))
    }
    grad.Parent = uiStroke
    animatedGradients[grad] = 500
end

local MainAllowBtn = Instance.new("TextButton")
MainAllowBtn.Size = UDim2.new(0, 84, 0, 48)
MainAllowBtn.Position = UDim2.new(0.65, 36, 0, 15)
MainAllowBtn.BackgroundColor3 = COLOR_BG_DARK
MainAllowBtn.BackgroundTransparency = 0.2
MainAllowBtn.Text = "WAITING"
MainAllowBtn.TextColor3 = COLOR_TEXT_LIGHT
MainAllowBtn.Font = Enum.Font.GothamBold
MainAllowBtn.TextSize = 10
MainAllowBtn.Parent = AllowDisallowGui
createUICorner(MainAllowBtn, 8)
ApplyFastEffects(MainAllowBtn)

local draggingAllow, dragStartAllow, startPosAllow, dragIdAllow
MainAllowBtn.InputBegan:Connect(function(input)
    if not draggingAllow and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        draggingAllow = true
        dragIdAllow = input
        dragStartAllow = input.Position
        startPosAllow = MainAllowBtn.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                draggingAllow = false
                dragIdAllow = nil
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if draggingAllow and input == dragIdAllow and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartAllow
        MainAllowBtn.Position = UDim2.new(startPosAllow.X.Scale, startPosAllow.X.Offset + delta.X, startPosAllow.Y.Scale, startPosAllow.Y.Offset + delta.Y)
    end
end)

local activeHubs = {}
local function createFloatingHub(parent, statusText)
    if activeHubs[parent] then return end
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 40, 0, 10)
    billboard.Adornee = parent
    billboard.AlwaysOnTop = true
    billboard.ExtentsOffset = Vector3.new(0, 2.5, 0)
    billboard.Parent = AllowDisallowGui

    local HubFrame = Instance.new("Frame")
    HubFrame.Size = UDim2.new(1, 0, 1, 0)
    HubFrame.BackgroundColor3 = COLOR_BG_DARK
    HubFrame.BackgroundTransparency = 0.2
    HubFrame.BorderSizePixel = 0
    HubFrame.Parent = billboard
    createUICorner(HubFrame, 6)
    ApplyFastEffects(HubFrame)

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = statusText
    statusLabel.TextColor3 = COLOR_TEXT_LIGHT
    statusLabel.TextSize = 18 
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.Parent = HubFrame
    applyTextGradient(statusLabel)

    activeHubs[parent] = billboard
end

task.spawn(function()
    while task.wait(2) do
        local currentObjects = {}
        local myBase = findMyBase()
        local nearestPrompt = nil
        local minDist = math.huge
        local plots = Workspace:FindFirstChild("Plots")

        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                for _, desc in ipairs(plot:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") then
                        local isAllow = string.find(desc.ObjectText, "Allow Friends")
                        local isDisallow = string.find(desc.ObjectText, "Disallow Friends")
                        if isAllow or isDisallow then
                            local part = desc.Parent:IsA("BasePart") and desc.Parent or desc.Parent:FindFirstChildWhichIsA("BasePart", true)
                            if part then
                                currentObjects[part] = true
                                local status = isAllow and "X" or "☑️" 
                                if activeHubs[part] then
                                    local label = activeHubs[part].Frame.TextLabel
                                    if label.Text ~= status then label.Text = status end
                                else
                                    createFloatingHub(part, status)
                                end

                                if myBase and part:IsDescendantOf(myBase) then
                                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                                    if hrp then
                                        local dist = (hrp.Position - part.Position).Magnitude
                                        if dist < minDist then
                                            minDist = dist
                                            nearestPrompt = desc
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        MainAllowBtn.Text = nearestPrompt and (string.find(nearestPrompt.ObjectText, "Disallow") and "DISALLOW" or "ALLOW") or "NO BASE"

        for part, bbg in pairs(activeHubs) do
            if not currentObjects[part] then
                bbg:Destroy()
                activeHubs[part] = nil
            end
        end
    end
end)

MainAllowBtn.MouseButton1Click:Connect(function()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local myBase = findMyBase()
    local target = nil
    local minDist = math.huge
    
    if myBase then
        for _, desc in pairs(myBase:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and (string.find(desc.ObjectText, "Allow") or string.find(desc.ObjectText, "Disallow")) then
                local part = desc.Parent:IsA("BasePart") and desc.Parent or desc.Parent:FindFirstChildWhichIsA("BasePart", true)
                if part and hrp then
                    local dist = (hrp.Position - part.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        target = desc
                    end
                end
            end
        end
    end
    if target then fireproximityprompt(target) end
end)

-- ==========================================
-- BARRA DE PROGRESO Y MENÚ PRINCIPAL (HEX HUB)
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MasaHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.Parent = safeGuiTarget

local panelWidth = IsMobile and 235 or 215
local mainHeight = IsMobile and 215 or 205

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, panelWidth, 0, mainHeight) 
MainFrame.AnchorPoint = Vector2.new(1, 0)
MainFrame.Position = IsMobile and UDim2.new(0.88, 0, 0.05, 0) or UDim2.new(0.84, 0, 0.02, 0)
MainFrame.BackgroundColor3 = COLOR_BG_DARK
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.ClipsDescendants = false
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 14)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Thickness = 1.5
MainStroke.Color = Color3.fromRGB(120, 70, 200)

local HeaderFrame = Instance.new("Frame")
HeaderFrame.Size = UDim2.new(1, 0, 0, 38)
HeaderFrame.BackgroundColor3 = Color3.fromRGB(25, 15, 40)
HeaderFrame.BorderSizePixel = 0
HeaderFrame.Parent = MainFrame
Instance.new("UICorner", HeaderFrame).CornerRadius = UDim.new(0, 14)

local HeaderCornerFix = Instance.new("Frame")
HeaderCornerFix.Size = UDim2.new(1, 0, 0, 10)
HeaderCornerFix.Position = UDim2.new(0, 0, 1, -10)
HeaderCornerFix.BackgroundColor3 = Color3.fromRGB(25, 15, 40)
HeaderCornerFix.BorderSizePixel = 0
HeaderCornerFix.Parent = HeaderFrame

local HeaderLine = Instance.new("Frame")
HeaderLine.Size = UDim2.new(1, 0, 0, 1)
HeaderLine.Position = UDim2.new(0, 0, 1, 0)
HeaderLine.BackgroundColor3 = COLOR_BORDER
HeaderLine.BorderSizePixel = 0
HeaderLine.Parent = HeaderFrame

local mainDragging, mainDragStart, mainStartPos = false, nil, nil
HeaderFrame.InputBegan:Connect(function(input) 
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        mainDragging = true
        mainDragStart = input.Position
        mainStartPos = MainFrame.Position 
    end 
end)
UserInputService.InputChanged:Connect(function(input) 
    if mainDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then 
        local delta = input.Position - mainDragStart
        MainFrame.Position = UDim2.new(mainStartPos.X.Scale, mainStartPos.X.Offset + delta.X, mainStartPos.Y.Scale, mainStartPos.Y.Offset + delta.Y) 
    end 
end)
UserInputService.InputEnded:Connect(function(input) 
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        mainDragging = false 
    end
end)

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, 0, 1, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "MASA HUB" 
TitleText.TextColor3 = COLOR_TEXT_LIGHT
TitleText.Font = MAIN_FONT
TitleText.TextSize = 13
TitleText.Parent = HeaderFrame
applyTextGradient(TitleText)

local TabContainer = Instance.new("Frame")
TabContainer.Size = UDim2.new(1, -20, 0, 26)
TabContainer.Position = UDim2.new(0, 10, 0, 46)
TabContainer.BackgroundColor3 = Color3.fromRGB(28, 20, 38)
TabContainer.BorderSizePixel = 0
TabContainer.Parent = MainFrame
Instance.new("UICorner", TabContainer).CornerRadius = UDim.new(0, 8)

local TabList = Instance.new("UIListLayout", TabContainer)
TabList.FillDirection = Enum.FillDirection.Horizontal
TabList.SortOrder = Enum.SortOrder.LayoutOrder

local function createTabButton(text, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.5, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = text
    btn.TextColor3 = COLOR_TEXT_DARK
    btn.Font = MAIN_FONT
    btn.TextSize = 11
    btn.LayoutOrder = order
    btn.Parent = TabContainer
    
    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(1, -8, 0, 2)
    indicator.Position = UDim2.new(0, 4, 1, -2)
    indicator.BackgroundColor3 = COLOR_ACCENT
    indicator.BackgroundTransparency = 1
    indicator.BorderSizePixel = 0
    indicator.Parent = btn
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)
    return btn, indicator
end

local MainTabBtn, MainTabInd = createTabButton("Main", 1)
local UtilsTabBtn, UtilsTabInd = createTabButton("Utils", 2)

local ContentLayout = Instance.new("ScrollingFrame")
ContentLayout.Size = UDim2.new(1, -16, 1, -82)
ContentLayout.Position = UDim2.new(0, 8, 0, 78) 
ContentLayout.BackgroundTransparency = 1
ContentLayout.BorderSizePixel = 0
ContentLayout.ScrollBarThickness = 2
ContentLayout.ScrollBarImageColor3 = COLOR_ACCENT
ContentLayout.CanvasSize = UDim2.new(0, 0, 0, 0)
ContentLayout.AutomaticCanvasSize = Enum.AutomaticSize.Y
ContentLayout.ClipsDescendants = true
ContentLayout.Parent = MainFrame

local List = Instance.new("UIListLayout", ContentLayout)
List.SortOrder = Enum.SortOrder.LayoutOrder
List.Padding = UDim.new(0, 6)

local function createRowFrame(height, order)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -4, 0, height)
    card.BackgroundColor3 = COLOR_CARD_BG
    card.BorderSizePixel = 0
    card.LayoutOrder = order or 1
    card.Parent = ContentLayout
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", card)
    stroke.Thickness = 1
    stroke.Color = COLOR_BORDER
    return card
end

local function createModernToggle(parentCard, textLabel, initialState, onClick)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, 0, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = textLabel
    lbl.TextColor3 = COLOR_TEXT_LIGHT
    lbl.Font = MAIN_FONT
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parentCard

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(0, 36, 0, 18)
    track.Position = UDim2.new(1, -44, 0.5, -9)
    track.BackgroundColor3 = initialState and COLOR_ACCENT or Color3.fromRGB(35, 35, 40)
    track.BorderSizePixel = 0
    track.Text = ""
    track.Parent = parentCard
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local pin = Instance.new("Frame")
    pin.Size = UDim2.new(0, 14, 0, 14)
    pin.Position = initialState and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    pin.BackgroundColor3 = initialState and COLOR_BG_DARK or Color3.fromRGB(180, 180, 180)
    pin.BorderSizePixel = 0
    pin.Parent = track
    Instance.new("UICorner", pin).CornerRadius = UDim.new(1, 0)

    local state = initialState
    track.MouseButton1Click:Connect(function()
        state = not state
        if state then
            TweenService:Create(track, TweenInfo.new(0.2), {BackgroundColor3 = COLOR_ACCENT}):Play()
            TweenService:Create(pin, TweenInfo.new(0.2), {Position = UDim2.new(1, -16, 0.5, -7), BackgroundColor3 = COLOR_BG_DARK}):Play()
        else
            TweenService:Create(track, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(35, 35, 40)}):Play()
            TweenService:Create(pin, TweenInfo.new(0.2), {Position = UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = Color3.fromRGB(180, 180, 180)}):Play()
        end
        onClick(state)
    end)
    return track, pin
end

local Row1 = createRowFrame(28, 1)
local Label1 = Instance.new("TextLabel")
Label1.Size = UDim2.new(0.4, 0, 1, 0)
Label1.Position = UDim2.new(0, 10, 0, 0)
Label1.BackgroundTransparency = 1
Label1.Text = "Select Slot"
Label1.TextColor3 = COLOR_TEXT_LIGHT
Label1.Font = MAIN_FONT
Label1.TextSize = 11
Label1.TextXAlignment = Enum.TextXAlignment.Left
Label1.Parent = Row1

local SelectorFrame = Instance.new("Frame")
SelectorFrame.Size = UDim2.new(0, 95, 0, 20)
SelectorFrame.Position = UDim2.new(1, -103, 0.5, -10)
SelectorFrame.BackgroundTransparency = 1
SelectorFrame.Parent = Row1

local LeftBtn = Instance.new("TextButton")
LeftBtn.Size = UDim2.new(0, 20, 1, 0)
LeftBtn.Position = UDim2.new(0, 0, 0, 0)
LeftBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
LeftBtn.Text = "<"
LeftBtn.TextColor3 = COLOR_TEXT_LIGHT
LeftBtn.Font = MAIN_FONT
LeftBtn.TextSize = 12
LeftBtn.Parent = SelectorFrame
Instance.new("UICorner", LeftBtn).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", LeftBtn).Color = COLOR_BORDER
addHoverAnimation(LeftBtn, Color3.fromRGB(35, 35, 42), Color3.fromRGB(50, 50, 60))

local SlotDisplay = Instance.new("TextLabel")
SlotDisplay.Size = UDim2.new(0, 47, 1, 0)
SlotDisplay.Position = UDim2.new(0, 24, 0, 0)
SlotDisplay.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
SlotDisplay.Text = "Slot " .. tostring(selectedSlot)
SlotDisplay.TextColor3 = COLOR_TEXT_LIGHT
SlotDisplay.Font = MAIN_FONT
SlotDisplay.TextSize = 10
SlotDisplay.Parent = SelectorFrame
Instance.new("UICorner", SlotDisplay).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", SlotDisplay).Color = COLOR_BORDER

local RightBtn = Instance.new("TextButton")
RightBtn.Size = UDim2.new(0, 20, 1, 0)
RightBtn.Position = UDim2.new(1, -20, 0, 0)
RightBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
RightBtn.Text = ">"
RightBtn.TextColor3 = COLOR_TEXT_LIGHT
RightBtn.Font = MAIN_FONT
RightBtn.TextSize = 12
RightBtn.Parent = SelectorFrame
Instance.new("UICorner", RightBtn).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", RightBtn).Color = COLOR_BORDER
addHoverAnimation(RightBtn, Color3.fromRGB(35, 35, 42), Color3.fromRGB(50, 50, 60))

local function updateSlot(newSlot)
    selectedSlot = newSlot
    SlotDisplay.Text = "Slot " .. tostring(selectedSlot)
    HalfwaySteal.setSlot(selectedSlot)
    if refreshTargetBar then refreshTargetBar() end
end

LeftBtn.MouseButton1Click:Connect(function()
    local nextSlot = selectedSlot - 1
    if nextSlot < 1 then nextSlot = 18 end
    updateSlot(nextSlot)
end)

RightBtn.MouseButton1Click:Connect(function()
    local nextSlot = selectedSlot + 1
    if nextSlot > 18 then nextSlot = 1 end
    updateSlot(nextSlot)
end)

-- ==========================================
-- BARRA INFERIOR: "Target: <animal>" / "Stealing..."
-- ==========================================
refreshTargetBar = function()
    if not TargetBarLabel then return end
    local stealing = (HalfwaySteal and HalfwaySteal.debounce) or (tick() < manualStealingUntil)
    if stealing then
        TargetBarLabel.Text = "Stealing..."
    else
        local name = getSlotTargetName()
        TargetBarLabel.Text = "Target: " .. tostring(name)
    end
end

setStealingStatus = function(isStealing)
    if isStealing then
        -- No permitir que el fin interno del robo borre el estado antes de 1.3 segundos.
        manualStealingUntil = math.max(manualStealingUntil, tick() + 1.3)
        if refreshTargetBar then refreshTargetBar() end

        task.delay(1.3, function()
            if refreshTargetBar and tick() >= manualStealingUntil then
                refreshTargetBar()
            end
        end)
    elseif tick() >= manualStealingUntil and refreshTargetBar then
        refreshTargetBar()
    end
end

local BottomBar = Instance.new("Frame")
BottomBar.Name = "MasaTargetBar"
BottomBar.Size = UDim2.new(0, IsMobile and 280 or 300, 0, 30)
BottomBar.AnchorPoint = Vector2.new(0.5, 1)
BottomBar.Position = UDim2.new(0.5, 0, 1, -10)
BottomBar.BackgroundColor3 = COLOR_CARD_BG
BottomBar.BorderSizePixel = 0
BottomBar.Active = false
BottomBar.Parent = ScreenGui
Instance.new("UICorner", BottomBar).CornerRadius = UDim.new(0, 10)
local bbStroke = Instance.new("UIStroke", BottomBar)
bbStroke.Color = COLOR_BORDER
bbStroke.Thickness = 1
bbStroke.Transparency = 0.15
local bbGrad = Instance.new("UIGradient", BottomBar)
bbGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 20, 38)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 12, 32)),
})
bbGrad.Rotation = 90

local bbPad = Instance.new("UIPadding", BottomBar)
bbPad.PaddingLeft = UDim.new(0, 12)
bbPad.PaddingRight = UDim.new(0, 12)

TargetBarLabel = Instance.new("TextLabel")
TargetBarLabel.Size = UDim2.new(1, 0, 1, 0)
TargetBarLabel.BackgroundTransparency = 1
TargetBarLabel.Text = "Target: None"
TargetBarLabel.TextColor3 = COLOR_TEXT_LIGHT
TargetBarLabel.Font = MAIN_FONT
TargetBarLabel.TextSize = 13
TargetBarLabel.TextXAlignment = Enum.TextXAlignment.Center
TargetBarLabel.TextYAlignment = Enum.TextYAlignment.Center
TargetBarLabel.Parent = BottomBar
applyTextGradient(TargetBarLabel)

refreshTargetBar()

-- Refresca el nombre del animal en vivo (los podiums cambian durante la partida)
task.spawn(function()
    while task.wait(0.5) do
        if not (HalfwaySteal and HalfwaySteal.debounce) and tick() >= manualStealingUntil then
            refreshTargetBar()
        end
    end
end)

-- ==========================================
-- ESP DE TIMER (siempre activo): muestra el tiempo restante de cada base
-- Tomado de la source John_Flash_TP
-- ==========================================
do
    local timerEspBillboards = {}
    task.spawn(function()
    while task.wait(0.25) do
        local plotsFolder = Workspace:FindFirstChild("Plots")
        if plotsFolder then
            for _, plot in ipairs(plotsFolder:GetChildren()) do
                local purchases = plot:FindFirstChild("Purchases")
                local plotBlock = purchases and purchases:FindFirstChild("PlotBlock")
                local mainPart = plotBlock and plotBlock:FindFirstChild("Main")
                local timeLabel = mainPart and mainPart:FindFirstChild("BillboardGui") and mainPart.BillboardGui:FindFirstChild("RemainingTime")
                local billboard = timerEspBillboards[plot.Name]
                if timeLabel and mainPart then
                    if not billboard then
                        billboard = Instance.new("BillboardGui")
                        billboard.Name = "MasaTimerESP_" .. plot.Name
                        billboard.Size = UDim2.new(0, 50, 0, 25)
                        billboard.StudsOffset = Vector3.new(0, 5, 0)
                        billboard.AlwaysOnTop = true
                        billboard.Adornee = mainPart
                        billboard.MaxDistance = 1000
                        billboard.Parent = plot
                        local l = Instance.new("TextLabel", billboard)
                        l.Size = UDim2.new(1, 0, 1, 0)
                        l.BackgroundTransparency = 1
                        l.TextScaled = true
                        l.Font = MAIN_FONT
                        l.TextColor3 = Color3.fromRGB(255, 255, 255)
                        l.TextStrokeTransparency = 0
                        l.TextStrokeColor3 = Color3.new(0, 0, 0)
                        timerEspBillboards[plot.Name] = billboard
                    end
                    local l = billboard:FindFirstChildWhichIsA("TextLabel")
                    if l then l.Text = timeLabel.Text end
                elseif billboard then
                    billboard:Destroy()
                    timerEspBillboards[plot.Name] = nil
                end
            end
        end
    end
    end)
end

local Row5 = createRowFrame(30, 2)
local ActivateBtn = Instance.new("TextButton")
ActivateBtn.Size = UDim2.new(1, 0, 1, 0)
ActivateBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
ActivateBtn.BorderSizePixel = 0
ActivateBtn.Text = "Activate (Reset)"
ActivateBtn.TextColor3 = COLOR_TEXT_LIGHT
ActivateBtn.Font = MAIN_FONT
ActivateBtn.TextSize = 11
ActivateBtn.Parent = Row5
Instance.new("UICorner", ActivateBtn).CornerRadius = UDim.new(0, 8)
addHoverAnimation(ActivateBtn, Color3.fromRGB(30, 30, 36), Color3.fromRGB(60, 40, 90))
ActivateBtn.MouseButton1Click:Connect(function() HalfwaySteal.activate() end)

local Row6 = createRowFrame(32, 3)
TeleportBtn = Instance.new("TextButton")
TeleportBtn.Size = UDim2.new(1, 0, 1, 0)
TeleportBtn.BackgroundColor3 = COLOR_ACCENT
TeleportBtn.BorderSizePixel = 0
TeleportBtn.Text = "Steal Now"
TeleportBtn.TextColor3 = COLOR_BG_DARK 
TeleportBtn.Font = MAIN_FONT
TeleportBtn.TextSize = 12
TeleportBtn.Parent = Row6
Instance.new("UICorner", TeleportBtn).CornerRadius = UDim.new(0, 8)
addHoverAnimation(TeleportBtn, COLOR_ACCENT, Color3.fromRGB(210, 160, 255))
TeleportBtn.MouseButton1Click:Connect(function() HalfwaySteal.execute() end)

local RowAutoActivate = createRowFrame(28, 10)
createModernToggle(RowAutoActivate, "Auto Activate", AutoActivateEnabled, function(newState)
    AutoActivateEnabled = newState
    HubConfig.autoActivateEnabled = newState
    saveHubConfig()
end)

local Row2 = createRowFrame(28, 11)
createModernToggle(Row2, "Auto Potion", PotionEnabled, function(newState)
    PotionEnabled = newState
    HubConfig.potionEnabled = newState
    saveHubConfig()
end)

local RowAutoWalk = createRowFrame(28, 13)
createModernToggle(RowAutoWalk, "Auto Walk", AutoWalkEnabled, function(newState)
    AutoWalkEnabled = newState
    HubConfig.autoWalkEnabled = newState
    saveHubConfig()
end)

local RowAutoTPAllow = createRowFrame(28, 17)
createModernToggle(RowAutoTPAllow, "Auto TP on Allow", AutoTPOnAllowEnabled, function(newState)
    AutoTPOnAllowEnabled = newState
    HubConfig.autoTPOnAllowEnabled = newState
    saveHubConfig()
end)

local RowAPOnSteal = createRowFrame(28, 14)
createModernToggle(RowAPOnSteal, "AP on Steal", APOnStealEnabled, function(newState)
    APOnStealEnabled = newState
    HubConfig.apOnStealEnabled = newState
    saveHubConfig()
end)

local RowKickAfterSteal = createRowFrame(28, 18)
createModernToggle(RowKickAfterSteal, "Kick After Steal", KickAfterStealEnabled, function(newState)
    KickAfterStealEnabled = newState
    HubConfig.kickAfterStealEnabled = newState
    saveHubConfig()
    if newState then
        scanGuiForKick(PlayerGui)
    end
end)

local Row3 = createRowFrame(28, 19)
local isSpeedVisible = HubConfig.hexSpeedVisible or false
local HexSpeedFrameRef = nil

createModernToggle(Row3, "Speed Panel", isSpeedVisible, function(newState)
    if HexSpeedFrameRef then
        HexSpeedFrameRef.Visible = newState
        HubConfig.hexSpeedVisible = newState
        saveHubConfig()
    end
end)

local RowGear = createRowFrame(28, 20)
local LabelGear = Instance.new("TextLabel")
LabelGear.Size = UDim2.new(0.45, 0, 1, 0)
LabelGear.Position = UDim2.new(0, 10, 0, 0)
LabelGear.BackgroundTransparency = 1
LabelGear.Text = "Select Gear"
LabelGear.TextColor3 = COLOR_TEXT_LIGHT
LabelGear.Font = MAIN_FONT
LabelGear.TextSize = 11
LabelGear.TextXAlignment = Enum.TextXAlignment.Left
LabelGear.Parent = RowGear

local initialInventoryGears = getInventoryGears()
if #initialInventoryGears > 0 then
    local found = false
    for _, g in ipairs(initialInventoryGears) do
        if g == HubConfig.selectedGear then found = true; break end
    end
    if not found then HubConfig.selectedGear = initialInventoryGears[1]; saveHubConfig() end
else
    HubConfig.selectedGear = "Sin Gear"
end

local GearCycleBtn = Instance.new("TextButton")
GearCycleBtn.Size = UDim2.new(0, 95, 0, 20)
GearCycleBtn.Position = UDim2.new(1, -103, 0.5, -10)
GearCycleBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
GearCycleBtn.BorderSizePixel = 0
GearCycleBtn.Text = HubConfig.selectedGear
GearCycleBtn.TextColor3 = COLOR_TEXT_LIGHT
GearCycleBtn.Font = MAIN_FONT
GearCycleBtn.TextSize = 9
GearCycleBtn.ZIndex = 8
GearCycleBtn.Parent = RowGear
Instance.new("UICorner", GearCycleBtn).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", GearCycleBtn).Color = COLOR_BORDER
addHoverAnimation(GearCycleBtn, Color3.fromRGB(35, 35, 42), Color3.fromRGB(50, 50, 60))

GearCycleBtn.MouseButton1Click:Connect(function()
    local inventoryGears = getInventoryGears()
    if #inventoryGears == 0 then
        GearCycleBtn.Text = "Sin Gear"
        HubConfig.selectedGear = "Sin Gear"
        saveHubConfig()
        return
    end
    local currentIndex = 0
    for i, gearName in ipairs(inventoryGears) do
        if gearName == HubConfig.selectedGear then currentIndex = i; break end
    end
    local nextGear = inventoryGears[(currentIndex % #inventoryGears) + 1]
    GearCycleBtn.Text = nextGear
    HubConfig.selectedGear = nextGear
    saveHubConfig()
end)

local Row4 = createRowFrame(28, 21)
if IsMobile then Row4.Visible = false end

local Label4 = Instance.new("TextLabel")
Label4.Size = UDim2.new(0.5, 0, 1, 0)
Label4.Position = UDim2.new(0, 10, 0, 0)
Label4.BackgroundTransparency = 1
Label4.Text = "Steal Keybind"
Label4.TextColor3 = COLOR_TEXT_LIGHT
Label4.Font = MAIN_FONT
Label4.TextSize = 11
Label4.TextXAlignment = Enum.TextXAlignment.Left
Label4.Parent = Row4

local KeybindBtn = Instance.new("TextButton")
KeybindBtn.Size = UDim2.new(0, 50, 0, 20)
KeybindBtn.Position = UDim2.new(1, -58, 0.5, -10)
KeybindBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
KeybindBtn.Text = currentStealKey.Name
KeybindBtn.TextColor3 = COLOR_TEXT_LIGHT
KeybindBtn.Font = MAIN_FONT
KeybindBtn.TextSize = 10
KeybindBtn.Parent = Row4
Instance.new("UICorner", KeybindBtn).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", KeybindBtn).Color = COLOR_BORDER

local isBinding = false
KeybindBtn.MouseButton1Click:Connect(function() isBinding = true; KeybindBtn.Text = "..." end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if isBinding and input.UserInputType == Enum.UserInputType.Keyboard then
        isBinding = false
        currentStealKey = input.KeyCode
        KeybindBtn.Text = input.KeyCode.Name
        HubConfig.stealKeybind = input.KeyCode.Name
        saveHubConfig()
    elseif not isBinding and input.KeyCode == currentStealKey then
        if not HalfwaySteal.debounce and not player:GetAttribute("Stealing") then
            HalfwaySteal.execute()
        end
    end
end)

local RowAPDefense = createRowFrame(28, 15)
createModernToggle(RowAPDefense, "AP Defense", HexDefenseState.AP, function(newState)
    HexDefenseState.AP = newState
    HubConfig.apDefenseEnabled = newState
    saveHubConfig()
end)

local RowLaserDefense = createRowFrame(28, 16)
createModernToggle(RowLaserDefense, "Laser Defense", HexDefenseState.Laser, function(newState)
    HexDefenseState.Laser = newState
    HubConfig.laserDefenseEnabled = newState
    saveHubConfig()
end)

local RowAimbot = createRowFrame(28, 12)
createModernToggle(RowAimbot, "Aimbot", HexDefenseState.Aimbot, function(newState)
    HexDefenseState.Aimbot = newState
    HubConfig.aimbotEnabled = newState
    saveHubConfig()
    if _G.MasaAimbotRefresh then pcall(_G.MasaAimbotRefresh) end
end)

local function switchTab(tabName)
    ContentLayout.CanvasPosition = Vector2.new(0, 0)
    if tabName == "Main" then
        MainTabBtn.TextColor3 = COLOR_TEXT_LIGHT
        UtilsTabBtn.TextColor3 = COLOR_TEXT_DARK
        TweenService:Create(MainTabInd, TweenInfo.new(0.2), {BackgroundTransparency = 0}):Play()
        TweenService:Create(UtilsTabInd, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
        
        Row1.Visible, Row5.Visible, Row6.Visible = true, true, true
        RowAutoActivate.Visible, Row2.Visible, RowAutoWalk.Visible, RowAutoTPAllow.Visible, RowAPOnSteal.Visible, RowKickAfterSteal.Visible, Row3.Visible, RowGear.Visible, Row4.Visible = false, false, false, false, false, false, false, false, false
        RowAPDefense.Visible, RowLaserDefense.Visible, RowAimbot.Visible = false, false, false
    elseif tabName == "Utils" then
        UtilsTabBtn.TextColor3 = COLOR_TEXT_LIGHT
        MainTabBtn.TextColor3 = COLOR_TEXT_DARK
        TweenService:Create(UtilsTabInd, TweenInfo.new(0.2), {BackgroundTransparency = 0}):Play()
        TweenService:Create(MainTabInd, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
        
        Row1.Visible, Row5.Visible, Row6.Visible = false, false, false
        RowAutoActivate.Visible, Row2.Visible, RowAutoWalk.Visible, RowAutoTPAllow.Visible, RowAPOnSteal.Visible, RowKickAfterSteal.Visible, Row3.Visible, RowGear.Visible = true, true, true, true, true, true, true, true
        RowAPDefense.Visible, RowLaserDefense.Visible, RowAimbot.Visible = true, true, true
        Row4.Visible = not IsMobile
    end
end

MainTabBtn.MouseButton1Click:Connect(function() switchTab("Main") end)
UtilsTabBtn.MouseButton1Click:Connect(function() switchTab("Utils") end)
switchTab("Main")

-- ==========================================
-- PANEL DE CONTROL SPEED
-- ==========================================
local SpeedScreenGui = Instance.new("ScreenGui")
SpeedScreenGui.Name = "MasaSpeedUI"
SpeedScreenGui.ResetOnSpawn = false
SpeedScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SpeedScreenGui.IgnoreGuiInset = true
SpeedScreenGui.Parent = safeGuiTarget

local HexSpeed = Instance.new("Frame")
HexSpeed.Name = "MasaSpeed"
HexSpeed.Size = UDim2.new(0, 185, 0, 105)
HexSpeed.BackgroundColor3 = COLOR_BG_DARK 
HexSpeed.BorderSizePixel = 0
HexSpeed.Visible = isSpeedVisible 
HexSpeed.ZIndex = 5
HexSpeed.Parent = SpeedScreenGui
HexSpeedFrameRef = HexSpeed 

HexSpeed.AnchorPoint = Vector2.new(1, 0)
if HubConfig.speedPos and HubConfig.speedPos.ScaleX ~= 0.5 then 
    HexSpeed.Position = UDim2.new(HubConfig.speedPos.ScaleX, HubConfig.speedPos.OffsetX, HubConfig.speedPos.ScaleY, HubConfig.speedPos.OffsetY) 
else 
    HexSpeed.Position = UDim2.new(0.98, 0, 0.02, 0) 
end

Instance.new("UICorner", HexSpeed).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", HexSpeed).Thickness = 1.5
Instance.new("UIStroke", HexSpeed).Color = COLOR_BORDER

local SpeedTitle = Instance.new("TextLabel")
SpeedTitle.Size = UDim2.new(1, 0, 0, 30)
SpeedTitle.BackgroundTransparency = 1
SpeedTitle.Text = "MASA SPEED"
SpeedTitle.TextColor3 = COLOR_TEXT_LIGHT
SpeedTitle.Font = MAIN_FONT 
SpeedTitle.TextSize = 11
SpeedTitle.ZIndex = 6
SpeedTitle.Parent = HexSpeed
applyTextGradient(SpeedTitle)

local function createSpeedButton(container, yOffset, text, toggleVar, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -12, 0, 28)
    button.Position = UDim2.new(0, 6, 0, yOffset)
    button.AutoButtonColor = false
    button.Text = ""
    button.BackgroundColor3 = COLOR_CARD_BG
    button.BorderSizePixel = 0
    button.ZIndex = 3
    button.Parent = container

    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", button).Color = COLOR_BORDER

    local btnLabel = Instance.new("TextLabel")
    btnLabel.Size = UDim2.new(1, -30, 1, 0)
    btnLabel.Position = UDim2.new(0, 8, 0, 0)
    btnLabel.BackgroundTransparency = 1
    btnLabel.Text = text
    btnLabel.TextColor3 = COLOR_TEXT_LIGHT
    btnLabel.Font = MAIN_FONT 
    btnLabel.TextSize = 10
    btnLabel.TextXAlignment = Enum.TextXAlignment.Left
    btnLabel.ZIndex = 4
    btnLabel.Parent = button

    local LedDot = Instance.new("Frame")
    LedDot.Size = UDim2.new(0, 8, 0, 8)
    LedDot.Position = UDim2.new(1, -16, 0.5, -4)
    LedDot.BorderSizePixel = 0
    LedDot.ZIndex = 4
    LedDot.Parent = button
    Instance.new("UICorner", LedDot).CornerRadius = UDim.new(1, 0)

    local function updateVisuals(anim)
        local isOn = _G[toggleVar]
        local targetLed = isOn and COLOR_ACCENT or Color3.fromRGB(50, 50, 50) 
        local targetBg = isOn and Color3.fromRGB(35, 35, 42) or COLOR_CARD_BG
        if anim then 
            TweenService:Create(LedDot, TweenInfo.new(0.2), {BackgroundColor3 = targetLed}):Play()
            TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = targetBg}):Play() 
        else 
            LedDot.BackgroundColor3 = targetLed
            button.BackgroundColor3 = targetBg 
        end
    end

    updateVisuals(false)
    button.MouseButton1Click:Connect(function() 
        _G[toggleVar] = not _G[toggleVar]
        HubConfig[toggleVar] = _G[toggleVar]
        saveHubConfig()
        updateVisuals(true)
        if callback then callback(_G[toggleVar]) end 
    end)
    return button
end

local function createSpeedTextBoxInput(parent, yPos, labelText, min, max, current, callback)
    local Area = Instance.new("Frame")
    Area.Size = UDim2.new(1, -12, 0, 28)
    Area.Position = UDim2.new(0, 6, 0, yPos)
    Area.BackgroundColor3 = COLOR_CARD_BG
    Area.Parent = parent
    Instance.new("UICorner", Area).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", Area).Color = COLOR_BORDER

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.65, 0, 1, 0)
    Label.Position = UDim2.new(0, 8, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = labelText
    Label.TextColor3 = COLOR_TEXT_LIGHT
    Label.Font = MAIN_FONT 
    Label.TextSize = 10
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Area

    local InputBox = Instance.new("TextBox")
    InputBox.Size = UDim2.new(0.25, 0, 0, 18)
    InputBox.Position = UDim2.new(0.75, -4, 0.5, -9)
    InputBox.BackgroundColor3 = Color3.fromRGB(18, 18, 22) 
    InputBox.Text = tostring(current)
    InputBox.TextColor3 = COLOR_TEXT_LIGHT
    InputBox.Font = MAIN_FONT 
    InputBox.TextSize = 10
    InputBox.ClearTextOnFocus = false
    InputBox.Parent = Area
    Instance.new("UICorner", InputBox).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", InputBox).Color = COLOR_BORDER

    InputBox.FocusLost:Connect(function() 
        local num = tonumber(InputBox.Text)
        if num then 
            num = math.clamp(num, min, max)
            InputBox.Text = tostring(num)
            callback(num) 
        else 
            InputBox.Text = tostring(current) 
        end 
    end)
end

createSpeedButton(HexSpeed, 35, "Speed Boost", "speedBoostEnabled")
createSpeedTextBoxInput(HexSpeed, 69, "Steal Speed", 16, 100, currentSpeed, function(val) 
    currentSpeed = val
    HubConfig.speedValue = val
    saveHubConfig() 
end)

local speedDragging, speedDragStart, speedStartPos = false, nil, nil
SpeedTitle.InputBegan:Connect(function(input) 
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        speedDragging = true; speedDragStart = input.Position; speedStartPos = HexSpeed.Position 
    end 
end)
UserInputService.InputChanged:Connect(function(input) 
    if speedDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then 
        local delta = input.Position - speedDragStart
        HexSpeed.Position = UDim2.new(speedStartPos.X.Scale, speedStartPos.X.Offset + delta.X, speedStartPos.Y.Scale, speedStartPos.Y.Offset + delta.Y) 
    end 
end)
UserInputService.InputEnded:Connect(function(input) 
    if speedDragging == true then 
        speedDragging = false
        HubConfig.speedPos = { ScaleX = HexSpeed.Position.X.Scale, OffsetX = HexSpeed.Position.X.Offset, ScaleY = HexSpeed.Position.Y.Scale, OffsetY = HexSpeed.Position.Y.Offset }
        saveHubConfig() 
    end 
end)

local GUI = Instance.new("ScreenGui")
GUI.Name = "MasaAPSpamUI"
GUI.ResetOnSpawn = false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.DisplayOrder = 15
GUI.Enabled = false 
GUI.Parent = getGuiParent()

_G.HalfwaySteal = HalfwaySteal
_G.SSExecute = function() pcall(HalfwaySteal.execute) end
_G.SetSlot = function(slot) HalfwaySteal.setSlot(slot) end

HalfwaySteal.debounce = false

if AutoActivateEnabled then
    task.spawn(function()
        task.wait(0.5)
        HalfwaySteal.activate()
    end)
end

local Camera = workspace.CurrentCamera
local scales = {}

local function addUIScale(guiElement)
    local uiScale = guiElement:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
    uiScale.Parent = guiElement
    table.insert(scales, uiScale)
end

addUIScale(MainFrame)
addUIScale(HexSpeed)

local UpdateScale = function()
    if not Camera then return end
    local viewportSize = Camera.ViewportSize
    local baseResolution = Vector2.new(800, 450)
    local scale = math.min(viewportSize.X / baseResolution.X, viewportSize.Y / baseResolution.Y)
    local clampedScale = IsMobile and math.clamp(scale * 1.15, 0.95, 1.4) or math.clamp(scale * 0.85, 0.75, 1.2)
    for _, uiScale in ipairs(scales) do uiScale.Scale = clampedScale end
end

UpdateScale()
if Camera then Camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateScale) end

-- ==========================================
-- HEX DEFENSES: AP DEFENSE / LASER DEFENSE / AIMBOT
-- ==========================================
local HexD = {}
cloneref = cloneref or function(o) return o end
local clonefunction = clonefunction or function(f) return f end
local getconstants_shim = (debug and debug.getconstants) or getconstants

HexD.hexTargetRemote, HexD.hexFireRemote = nil, function() end
HexD.hexAimbotRange = 100
HexD.hexLaserConn, HexD.hexWebConn = nil, nil

-- Detección del RemoteEvent (misma técnica del John Aimbot)
task.spawn(function()
    local packages = ReplicatedStorage:WaitForChild("Packages", 20)
    local netFolder = packages and packages:WaitForChild("Net", 20)
    if not netFolder then return end
    while not HexD.hexTargetRemote do
        if getconnections and getconstants_shim then
            local found = false
            for _, r in ipairs(netFolder:GetChildren()) do
                if r:IsA("RemoteEvent") then
                    local ok, conns = pcall(getconnections, r.OnClientEvent)
                    if ok and type(conns) == "table" then
                        for _, c in ipairs(conns) do
                            if c and type(c.Function) == "function" then
                                local okc, consts = pcall(getconstants_shim, c.Function)
                                if okc and type(consts) == "table" then
                                    for _, k in ipairs(consts) do
                                        if k == "PaintballHitted" then
                                            HexD.hexTargetRemote = cloneref(r)
                                            HexD.hexFireRemote = clonefunction(HexD.hexTargetRemote.FireServer)
                                            found = true
                                            break
                                        end
                                    end
                                end
                            end
                            if found then break end
                        end
                    end
                end
                if found then break end
            end
        end
        if HexD.hexTargetRemote then break end
        task.wait(1)
    end
end)

function HexD.hexGetNearestPlayer(maxRange)
    maxRange = maxRange or math.huge
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos, nearest, shortest = player.Character.HumanoidRootPart.Position, nil, maxRange
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= player and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
            local h = pl.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                local dist = (pl.Character.HumanoidRootPart.Position - myPos).Magnitude
                if dist < shortest then shortest, nearest = dist, pl end
            end
        end
    end
    return nearest
end

function HexD.hexFireLaserAt(targetPart)
    if not targetPart or not HexD.hexTargetRemote then return end
    pcall(function()
        HexD.hexFireRemote(HexD.hexTargetRemote, targetPart.Position, targetPart)
    end)
end

function HexD.hexFireWebAt(targetPart)
    if not targetPart or not HexD.hexTargetRemote then return end
    local char, bp = player.Character, player:FindFirstChild("Backpack")
    local tool = (bp and bp:FindFirstChild("Web Slinger")) or (char and char:FindFirstChild("Web Slinger"))
    if tool and tool:FindFirstChild("Handle") then
        pcall(function()
            HexD.hexFireRemote(HexD.hexTargetRemote, Vector3.new(targetPart.Position.X, targetPart.Position.Y, targetPart.Position.Z), targetPart, tool.Handle)
        end)
    end
end

-- Busca la Laser Cape SIN equiparla (para el aimbot: no debe forzar el equipo)
function HexD.hexFindLaserCape()
    local char, bp = player.Character, player:FindFirstChild("Backpack")
    return (char and char:FindFirstChild("Laser Cape")) or (bp and bp:FindFirstChild("Laser Cape")) or nil
end

-- Busca la Laser Cape y la equipa (solo para Laser Defense)
function HexD.hexGetLaserCape()
    local char = player.Character
    local tool = HexD.hexFindLaserCape()
    if tool and char and tool.Parent ~= char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:EquipTool(tool) end) end
    end
    return tool
end

-- AIMBOT: al activar Laser Cape o Web Slinger apunta al jugador más cercano
function HexD.hexSetupLaserAim()
    local tool = HexD.hexFindLaserCape()
    if not tool then return end
    if HexD.hexLaserTool == tool and HexD.hexLaserConn and HexD.hexLaserConn.Connected then return end
    if HexD.hexLaserConn then HexD.hexLaserConn:Disconnect() end
    HexD.hexLaserTool = tool
    HexD.hexLaserConn = tool.Activated:Connect(function()
        if not HexDefenseState.Aimbot then return end
        local target = HexD.hexGetNearestPlayer(HexD.hexAimbotRange)
        if target and target.Character then
            local tp = target.Character:FindFirstChild("HumanoidRootPart")
            if tp then HexD.hexFireLaserAt(tp) end
        end
    end)
end

function HexD.hexSetupWebAim()
    local char, bp = player.Character, player:FindFirstChild("Backpack")
    local tool = (bp and bp:FindFirstChild("Web Slinger")) or (char and char:FindFirstChild("Web Slinger"))
    if not tool then return end
    if HexD.hexWebTool == tool and HexD.hexWebConn and HexD.hexWebConn.Connected then return end
    if HexD.hexWebConn then HexD.hexWebConn:Disconnect() end
    HexD.hexWebTool = tool
    HexD.hexWebConn = tool.Activated:Connect(function()
        if not HexDefenseState.Aimbot then return end
        local target = HexD.hexGetNearestPlayer(HexD.hexAimbotRange)
        if target and target.Character then
            local tp = target.Character:FindFirstChild("HumanoidRootPart")
            if tp then HexD.hexFireWebAt(tp) end
        end
    end)
end

function HexD.hexRefreshAimbot()
    if HexDefenseState.Aimbot then
        pcall(HexD.hexSetupLaserAim)
        pcall(HexD.hexSetupWebAim)
    else
        if HexD.hexLaserConn then HexD.hexLaserConn:Disconnect(); HexD.hexLaserConn = nil end
        if HexD.hexWebConn then HexD.hexWebConn:Disconnect(); HexD.hexWebConn = nil end
        HexD.hexLaserTool, HexD.hexWebTool = nil, nil
    end
end
_G.MasaAimbotRefresh = HexD.hexRefreshAimbot

if player.Backpack then
    player.Backpack.ChildAdded:Connect(function() task.wait(0.1) HexD.hexRefreshAimbot() end)
end
player.CharacterAdded:Connect(function(char)
    char.ChildAdded:Connect(function() task.wait(0.1) HexD.hexRefreshAimbot() end)
end)
if player.Character then
    player.Character.ChildAdded:Connect(function() task.wait(0.1) HexD.hexRefreshAimbot() end)
end

-- AP DEFENSE: lógica del HEX Defender (comandos de admin balloon/ragdoll/rocket)
HexD.hexGlobalCooldowns = { balloon = 0, ragdoll = 0, rocket = 0 }
HexD.hexLastCommandTime = 0
HexD.hexProcessedTexts = setmetatable({}, { __mode = "k" })
HexD.hexAdminButtonsCache = {}
HexD.hexLastCacheTime = 0
HexD.hexLaserLastShot = 0

function HexD.hexClickAdminButton(button)
    pcall(function()
        if firesignal then
            firesignal(button.MouseButton1Click)
            firesignal(button.Activated)
        else
            for _, c in ipairs(getconnections(button.MouseButton1Click)) do pcall(c.Function) end
            for _, c in ipairs(getconnections(button.Activated)) do pcall(c.Function) end
        end
    end)
end

function HexD.hexUpdateAdminCache()
    local now = tick()
    if now - HexD.hexLastCacheTime < 3 and #HexD.hexAdminButtonsCache > 0 then return end
    HexD.hexLastCacheTime = now
    table.clear(HexD.hexAdminButtonsCache)
    local adminPanel = PlayerGui:FindFirstChild("AdminPanel")
    if not adminPanel then return end
    for _, desc in ipairs(adminPanel:GetDescendants()) do
        if desc:IsA("TextButton") or desc:IsA("ImageButton") then
            local txt = (desc:IsA("TextButton") and desc.Text) or ""
            if txt == "" then
                local lbl = desc:FindFirstChildWhichIsA("TextLabel", true)
                if lbl then txt = lbl.Text end
            end
            if txt ~= "" then
                table.insert(HexD.hexAdminButtonsCache, { btn = desc, text = txt:lower() })
            end
        end
    end
end

function HexD.hexFindPlayerButton(targetPlayer)
    HexD.hexUpdateAdminCache()
    local displayName = targetPlayer.DisplayName:lower()
    local userName = targetPlayer.Name:lower()
    for _, data in ipairs(HexD.hexAdminButtonsCache) do
        local txt = data.text
        if txt == displayName or txt:find(displayName, 1, true) or txt == userName or txt:find(userName, 1, true) then
            return data.btn
        end
    end
    return nil
end

function HexD.hexGetCommandButton(cmdName)
    HexD.hexUpdateAdminCache()
    for _, data in ipairs(HexD.hexAdminButtonsCache) do
        local txt = data.text
        if (txt:match("^:") or txt:match("^;")) and txt:find(cmdName, 1, true) then
            return data.btn
        end
    end
    return nil
end

function HexD.hexPunishWithAP(target)
    if not HexDefenseState.AP or not target then return end
    local now = tick()
    if now - HexD.hexLastCommandTime < 1.5 then return end
    local playerBtn = HexD.hexFindPlayerButton(target)
    if not playerBtn then return end
    local cmd = nil
    if now - HexD.hexGlobalCooldowns.balloon >= 30 then
        cmd = "balloon"
    elseif now - HexD.hexGlobalCooldowns.ragdoll >= 30 then
        cmd = "ragdoll"
    elseif now - HexD.hexGlobalCooldowns.rocket >= 120 then
        cmd = "rocket"
    end
    if cmd then
        local cmdBtn = HexD.hexGetCommandButton(cmd)
        if cmdBtn then
            HexD.hexGlobalCooldowns[cmd] = now
            HexD.hexLastCommandTime = now
            HexD.hexClickAdminButton(playerBtn)
            HexD.hexClickAdminButton(cmdBtn)
            warn("[MASA] AP Defense ejecutó: " .. cmd)
        end
    end
end

-- LASER DEFENSE: selecciona la Laser Cape y dispara al intruso como el aimbot
function HexD.hexPunishWithLaser(target)
    if not HexDefenseState.Laser or not target then return end
    if not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then return end
    local now = tick()
    if now - HexD.hexLaserLastShot < 1 then return end
    local tool = HexD.hexGetLaserCape()
    if not tool then return end
    HexD.hexLaserLastShot = now
    task.spawn(function()
        task.wait(0.1) -- dar tiempo a que la Laser Cape se equipe
        if target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            HexD.hexFireLaserAt(target.Character.HumanoidRootPart)
            warn("[MASA] Laser Defense disparó a: " .. target.Name)
        end
    end)
end

-- Detecta jugador dentro de MI base (reutiliza findMyBase del script)
function HexD.hexGetPlayerInMyBase()
    local base = findMyBase()
    if not base then return nil end
    local baseCFrame, baseSize = base:GetBoundingBox()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local localPoint = baseCFrame:PointToObjectSpace(p.Character.HumanoidRootPart.Position)
            if math.abs(localPoint.X) <= (baseSize.X / 2)
               and math.abs(localPoint.Y) <= (baseSize.Y / 2)
               and math.abs(localPoint.Z) <= (baseSize.Z / 2) then
                return p
            end
        end
    end
    return nil
end

function HexD.hexCheckStealText(desc)
    if not HexDefenseState.AP and not HexDefenseState.Laser then return end
    local text = desc.Text
    if not text or text == "" then return end
    if text:lower():find("stealing") then
        if desc.Visible and desc.AbsoluteSize.X > 0 and desc.AbsoluteSize.Y > 0 then
            if HexD.hexProcessedTexts[desc] ~= text then
                HexD.hexProcessedTexts[desc] = text
                local intruder = HexD.hexGetPlayerInMyBase()
                if intruder then
                    HexD.hexPunishWithAP(intruder)
                    HexD.hexPunishWithLaser(intruder)
                end
            end
        end
    end
end

function HexD.hexSetupLabel(desc)
    if desc:IsA("TextLabel") or desc:IsA("TextBox") then
        HexD.hexCheckStealText(desc)
        desc:GetPropertyChangedSignal("Text"):Connect(function() HexD.hexCheckStealText(desc) end)
        desc:GetPropertyChangedSignal("Visible"):Connect(function() HexD.hexCheckStealText(desc) end)
    end
end

for _, desc in ipairs(PlayerGui:GetDescendants()) do
    task.spawn(HexD.hexSetupLabel, desc)
end
PlayerGui.DescendantAdded:Connect(HexD.hexSetupLabel)
