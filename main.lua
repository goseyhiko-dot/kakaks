-- V215 | Renommage persistant des 5 sauvegardes dans Paramètres.
-- V214 | Aimbot : suppression du raccourci clavier et du texte d’aide, contrôles remontés. Base V213.
-- V218 | Mode réduit sans chevauchement de texte ; angles plus arrondis. Base V217.
-- V211 | Polish visuel UX : thème cohérent, hover/focus, en-tête propre, cartes et scrollbars. Base V210.
-- V210 | Garde-fous contre les redémarrages rapides Auto Buy + synchronisation du montant Give Money. Base V209.
-- V182 | TP diagnostic build — logs server/client rubber-band after Shore TP
-- V128 | Cleaned V127 base — no duplicate legacy sidebar
-- V98 CHECK BUILD - FREECAM BELOW NOCLIP
-- VERSION : V102 / BARRES NOURRITURE-BOISSON REFAITES
-- V220 : badge de version supprimé ; réglages de l’Aimbot remontés
-- V191 : Anti-AFK réel pour Auto-Fish via Player.Idled + VirtualUser.
-- Le système ne dépend plus d'un saut et répond directement à la détection d'inactivité.
-- V186 : préserver la vraie vitesse avant le nettoyage de l'ancienne version.
-- Les anciennes versions pouvaient remettre WalkSpeed à 16 pendant leur unload,
-- ce qui contaminait ensuite la "vitesse normale" mémorisée par la nouvelle version.
local __PRISONRP_PreviousHumanoidWalkSpeed = nil
pcall(function()
    local __player = game:GetService("Players").LocalPlayer
    local __char = __player and __player.Character
    local __hum = __char and __char:FindFirstChildOfClass("Humanoid")
    if __hum then
        __PRISONRP_PreviousHumanoidWalkSpeed = __hum.WalkSpeed
    end
end)

_G.CombinedHubReady = false

-- V208 : certains systèmes des anciennes versions n'étaient pas reliés à UNLOAD.
-- Les arrêter avant de construire le nouveau hub empêche Freecam/Auto Arm
-- de continuer en arrière-plan lors d'un rechargement.
pcall(function()
    if type(_G.PRISONRP_SPEC_STOP) == "function" then
        _G.PRISONRP_SPEC_STOP()
    elseif type(_G.PRISONRP_SET_SPEC_STATE) == "function" then
        _G.PRISONRP_SET_SPEC_STATE({Armed = false})
    end
end)
pcall(function()
    if type(_G.PRISONRP_AUTO_ARM_WRESTLE_CLEANUP) == "function" then
        _G.PRISONRP_AUTO_ARM_WRESTLE_CLEANUP()
    elseif type(_G.PRISONRP_STOP_AUTO_ARM_WRESTLE) == "function" then
        _G.PRISONRP_STOP_AUTO_ARM_WRESTLE()
        local previousArmState = _G.PRISONRP_AUTO_ARM_WRESTLE_STATE
        if previousArmState and previousArmState.MatchConnection then
            pcall(function() previousArmState.MatchConnection:Disconnect() end)
        end
    end
end)
pcall(function()
    if type(_G.PRISONRP_GIVE_MONEY_STOP) == "function" then
        _G.PRISONRP_GIVE_MONEY_STOP()
        _G.PRISONRP_GIVE_MONEY_STOP = nil
    end
end)

-- Nettoyage ultra-sûr : une ancienne version ne doit JAMAIS empêcher l'interface de démarrer.
if _G.CombinedHubLoaded and type(_G.CombinedHubCleanup) == "function" then
    pcall(_G.CombinedHubCleanup)
end

-- Restaurer immédiatement la vitesse qui existait avant l'unload.
pcall(function()
    local __player = game:GetService("Players").LocalPlayer
    local __char = __player and __player.Character
    local __hum = __char and __char:FindFirstChildOfClass("Humanoid")
    if __hum and tonumber(__PRISONRP_PreviousHumanoidWalkSpeed) then
        __hum.WalkSpeed = __PRISONRP_PreviousHumanoidWalkSpeed
    end
end)

_G.CombinedHubLoaded = true
-- V187 : toujours repartir avec le Fly désactivé au chargement.
MovementFlyEnabled = false

_G.PRISONRP_PREVIOUS_NORMAL_WALKSPEED = __PRISONRP_PreviousHumanoidWalkSpeed

-- Stopper l'ancien Aimbot intégré avant un nouveau chargement.
if _G.PRISONRP_AIMBOT_STOP then
    pcall(_G.PRISONRP_AIMBOT_STOP)
    _G.PRISONRP_AIMBOT_STOP = nil
end

-- Variables Globales Pêche & ESP
_G.AutoFishingEnabled = false
_G.AutoSellEnabled = false
_G.MinRarityIndex = 1
_G.BlackMarketESP = false

-- Auto Pompes (ajouté, sans modifier le fonctionnement de la pêche)
_G.AutoPushupEnabled = false
AutoPushupWorker = nil

-- Auto Eat / Drink
AutoEatDrinkEnabled = false
AutoEatDrinkBusy = false
AutoEatDrinkThreadRunning = true
AutoEatDrinkWasPushupActive = false
AUTO_EAT_DRINK_THRESHOLD = 50
AUTO_EAT_DRINK_CHECK_INTERVAL = 0.5

RarityList = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Unknown", "Mythical", "Secret"}

-- Services & References
Players = game:GetService("Players")
ReplicatedStorage = game:GetService("ReplicatedStorage")
RunService = game:GetService("RunService")
LocalPlayer = Players.LocalPlayer

get_gc = getgc or (debug and debug.getgc)
get_upvalues = getupvalues or (debug and debug.getupvalues)

-- IMPORTANT : on utilise PlayerGui directement pour maximiser la compatibilité.
-- Certains executors renvoient un parent invalide avec gethui(), ce qui peut faire
-- planter le script avant même que la moindre fenêtre soit créée.
guiParent = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
if not guiParent and LocalPlayer then
    guiParent = LocalPlayer:WaitForChild("PlayerGui", 10)
end
if not guiParent then
    error("[Hub Prison RP] PlayerGui introuvable")
end

-- Dépendances du jeu : déclarées ici, initialisées APRÈS la création de l'interface.
-- Ainsi un WaitForChild lent/absent ne peut plus empêcher le menu de s'afficher.
FishingSystem, FishingModules, MinigameSystem, SoundManager, GUIManager = nil, nil, nil, nil, nil
InventoryEvents, Inventory_SellAll = nil, nil
ToolEvent, vendingMachine, foodEvent, drinkEvent = nil, nil, nil, nil
POND_GROUND_CFRAME = CFrame.new(Vector3.new(-585, 0.5, -100), Vector3.new(-615, 0.5, -85))

-- V180 : TP robuste + retour à la position d'origine.
-- Le jeu peut corriger instantanément un CFrame unique après une mise à jour ;
-- on réapplique donc la position sur plusieurs Heartbeats.
TeleportSavedCFrame = nil
TeleportSavedCharacter = nil
TeleportAtTarget = false
TeleportReturnMode = nil -- "Shore" ou "BlackMarket"

function getMovementRoot()
    local char = LocalPlayer and LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- V181 : déplacement rapide par petites étapes.
-- Certaines mises à jour rejettent un gros saut de position effectué en une seule frame.
-- On conserve donc le comportement "TP" pour l'utilisateur, mais la position est
-- envoyée progressivement afin de limiter le rubber-band serveur.
TP_STEP_TIME = 0.45
TP_MAX_STEP_DISTANCE = 7
TP_HOLD_TIME = 0.12

function robustTeleportTo(targetCFrame)
    local char = LocalPlayer and LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or typeof(targetCFrame) ~= "CFrame" then return false end

    local startPos = root.Position
    local targetPos = targetCFrame.Position
    local delta = targetPos - startPos
    local distance = delta.Magnitude

    if distance <= 2 then
        pcall(function()
            if char and char.PivotTo then
                char:PivotTo(targetCFrame)
            else
                root.CFrame = targetCFrame
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        return true
    end

    local steps = math.max(1, math.ceil(distance / TP_MAX_STEP_DISTANCE))
    local started = os.clock()

    for i = 1, steps do
        if not root.Parent then return false end

        local alpha = i / steps
        local pos = startPos:Lerp(targetPos, alpha)
        local cf = CFrame.new(pos) * targetCFrame.Rotation

        pcall(function()
            if char and char.PivotTo then
                char:PivotTo(cf)
            else
                root.CFrame = cf
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if hum then
                hum:Move(Vector3.zero, false)
            end
        end)

        RunService.Heartbeat:Wait()
    end

    -- Petite phase de stabilisation à l'arrivée.
    local holdUntil = os.clock() + TP_HOLD_TIME
    while os.clock() < holdUntil do
        if not root.Parent then return false end
        pcall(function()
            if char and char.PivotTo then
                char:PivotTo(targetCFrame)
            else
                root.CFrame = targetCFrame
            end
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
        RunService.Heartbeat:Wait()
    end

    return (root.Position - targetPos).Magnitude <= 10
end

function saveCurrentTeleportPosition(mode)
    local root = getMovementRoot()
    if not root then return false end
    TeleportSavedCFrame = root.CFrame
    TeleportSavedCharacter = LocalPlayer.Character
    TeleportAtTarget = false
    TeleportReturnMode = mode
    return true
end

function returnToSavedTeleportPosition(expectedMode)
    local root = getMovementRoot()
    if not root or not TeleportSavedCFrame then return false end
    if expectedMode and TeleportReturnMode ~= expectedMode then return false end
    if TeleportSavedCharacter ~= LocalPlayer.Character then
        TeleportSavedCFrame = nil
        TeleportSavedCharacter = nil
        TeleportAtTarget = false
        return false
    end

    local ok = robustTeleportTo(TeleportSavedCFrame)
    if ok then
        TeleportAtTarget = false
        TeleportSavedCFrame = nil
        TeleportSavedCharacter = nil
        TeleportReturnMode = nil
    end
    return ok
end
stats = {totalCaught = 0, perfectCount = 0, lastFish = "None", status = "Idle"}

pcall(function()
    local old = guiParent:FindFirstChild("CombinedHubUI")
    if old then old:Destroy() end
end)

-- GUI Setup (Agrandissement vertical à 720px)
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CombinedHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999999
ScreenGui.IgnoreGuiInset = true
ScreenGui.Enabled = false
ScreenGui.Archivable = false



MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 320, 0, 620)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

-- Agrandissement réel de toute l'interface.
-- UIScale applique le facteur 1.25 à MainFrame et à tous ses enfants.
MainFrameScale = Instance.new("UIScale")
MainFrameScale.Name = "InterfaceScale"
MainFrameScale.Scale = 0.875
MainFrameScale.Parent = MainFrame

-- V100 : interface principale arrondie.
MainFrameCorner = Instance.new("UICorner")
MainFrameCorner.CornerRadius = UDim.new(0, 14)
MainFrameCorner.Parent = MainFrame

-- Parent immédiatement l'interface : même si une fonction plus bas rencontre une erreur,
-- le menu reste visible et le script peut continuer à être diagnostiqué.
ScreenGui.Parent = guiParent
ScreenGui.Enabled = false
MainFrame.Visible = true

-- Marqueur de démarrage : doit être visible même si une partie du script échoue plus loin.
-- Petit garde-fou : le menu de base doit être visible immédiatement.
pcall(function()
    MainFrame.ZIndex = 10
end)

task.wait()

-- V99 : interface principale avec angles carrés.
-- Le coin inférieur gauche ne doit plus être arrondi.

-- V101 : suppression du contour bleu de l'interface.

-- Header
TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 44)
TitleBar.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

-- V102 : arrondi des coins supérieurs de la barre.
TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 14)
TitleCorner.Parent = TitleBar

-- V99 : pas de coin arrondi sur la barre supérieure.

TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(0, 180, 1, 0)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "⛏ Hub : PRISON RP"
TitleLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
TitleLabel.TextSize = 14
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

-- Raccourci d'affichage : texte simple dans la barre du haut.
RightShiftLabel = Instance.new("TextLabel")
RightShiftLabel.Name = "RightShiftHint"
RightShiftLabel.Size = UDim2.fromOffset(250, 52)
RightShiftLabel.Position = UDim2.fromOffset(145, 0)
RightShiftLabel.BackgroundTransparency = 1
RightShiftLabel.Text = "RightShift : afficher / masquer"
RightShiftLabel.TextColor3 = Color3.fromRGB(185, 190, 198)
RightShiftLabel.TextSize = 9
RightShiftLabel.Font = Enum.Font.GothamMedium
RightShiftLabel.TextXAlignment = Enum.TextXAlignment.Left
RightShiftLabel.Parent = TitleBar

-- Boutons de la barre supérieure : réduction + UNLOAD.
-- UNLOAD est volontairement plus petit et placé à l’extrême droite.
CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(34, 30)
CloseBtn.Position = UDim2.new(1, -120, 0, 7)
CloseBtn.BackgroundColor3 = Color3.fromRGB(38, 42, 54)
CloseBtn.Text = "−"
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseBtn.TextSize = 17
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.AutoButtonColor = false
CloseBtn.ZIndex = 120
CloseBtn.Parent = MainFrame

CloseBtnCorner = Instance.new("UICorner")
CloseBtnCorner.CornerRadius = UDim.new(0, 9)
CloseBtnCorner.Parent = CloseBtn

UnloadBtn = Instance.new("TextButton")
UnloadBtn.Name = "UnloadButton"
UnloadBtn.Size = UDim2.fromOffset(76, 30)
UnloadBtn.Position = UDim2.new(1, -82, 0, 7)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(120, 45, 48)
UnloadBtn.Text = "UNLOAD"
UnloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadBtn.TextSize = 11
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.AutoButtonColor = false
UnloadBtn.ZIndex = 120
UnloadBtn.Parent = MainFrame

UnloadBtnCorner = Instance.new("UICorner")
UnloadBtnCorner.CornerRadius = UDim.new(0, 9)
UnloadBtnCorner.Parent = UnloadBtn

UnloadBtnStroke = Instance.new("UIStroke")
UnloadBtnStroke.Color = Color3.fromRGB(170, 75, 78)
UnloadBtnStroke.Transparency = 0.45
UnloadBtnStroke.Thickness = 1
UnloadBtnStroke.Parent = UnloadBtn

Content = Instance.new("ScrollingFrame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -24, 1, -100)
Content.Position = UDim2.new(0, 12, 0, 92)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 5
Content.CanvasSize = UDim2.new(0, 0, 0, 980)
Content.ScrollingDirection = Enum.ScrollingDirection.Y
Content.Parent = MainFrame

-- Status UI Pêche
StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 22)
StatusLabel.Position = UDim2.new(0, 0, 0, 0)
StatusLabel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
StatusLabel.Text = "Status: Idle"
StatusLabel.TextColor3 = Color3.fromRGB(130, 200, 255)
StatusLabel.TextSize = 11
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.Parent = Content

StatsLabel = Instance.new("TextLabel")
StatsLabel.Size = UDim2.new(1, 0, 0, 22)
StatsLabel.Position = UDim2.new(0, 0, 0, 26)
StatsLabel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
StatsLabel.Text = "Caught: 0 | Perfect: 0"
StatsLabel.TextColor3 = Color3.fromRGB(150, 240, 160)
StatsLabel.TextSize = 11
StatsLabel.Font = Enum.Font.GothamMedium
StatsLabel.Parent = Content

LastFishLabel = Instance.new("TextLabel")
LastFishLabel.Size = UDim2.new(1, 0, 0, 22)
LastFishLabel.Position = UDim2.new(0, 0, 0, 52)
LastFishLabel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
LastFishLabel.Text = "Last Fish: None"
LastFishLabel.TextColor3 = Color3.fromRGB(255, 215, 100)
LastFishLabel.TextSize = 11
LastFishLabel.Font = Enum.Font.GothamMedium
LastFishLabel.Parent = Content

ToggleFishBtn = Instance.new("TextButton")
ToggleFishBtn.Size = UDim2.new(1, 0, 0, 32)
ToggleFishBtn.Position = UDim2.new(0, 0, 0, 78)
ToggleFishBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 50)
ToggleFishBtn.Text = "🎣 START AUTO-FISH"
ToggleFishBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleFishBtn.TextSize = 13
ToggleFishBtn.Font = Enum.Font.GothamBold
ToggleFishBtn.Parent = Content

RarityBtn = Instance.new("TextButton")
RarityBtn.Size = UDim2.new(1, 0, 0, 26)
RarityBtn.Position = UDim2.new(0, 0, 0, 116)
RarityBtn.BackgroundColor3 = Color3.fromRGB(50, 40, 90)
RarityBtn.Text = "Pêcher à partir de : Common"
RarityBtn.TextColor3 = Color3.fromRGB(220, 200, 255)
RarityBtn.TextSize = 11
RarityBtn.Font = Enum.Font.GothamMedium
RarityBtn.Parent = Content

TeleportBtn = Instance.new("TextButton")
TeleportBtn.Size = UDim2.new(0.49, 0, 0, 30)
TeleportBtn.Position = UDim2.new(0, 0, 0, 148)
TeleportBtn.BackgroundColor3 = Color3.fromRGB(30, 95, 185)
TeleportBtn.Text = "🏃 SHORE"
TeleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TeleportBtn.TextSize = 11
TeleportBtn.Font = Enum.Font.GothamMedium
TeleportBtn.Parent = Content

AutoSellBtn = Instance.new("TextButton")
AutoSellBtn.Size = UDim2.new(0.49, 0, 0, 30)
AutoSellBtn.Position = UDim2.new(0.51, 0, 0, 148)
AutoSellBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
AutoSellBtn.Text = "💰 AUTO-SELL"
AutoSellBtn.Font = Enum.Font.GothamMedium
AutoSellBtn.Parent = Content

SellNowBtn = Instance.new("TextButton")
SellNowBtn.Size = UDim2.new(1, 0, 0, 26)
SellNowBtn.Position = UDim2.new(0, 0, 0, 184)
SellNowBtn.BackgroundColor3 = Color3.fromRGB(150, 90, 30)
SellNowBtn.Text = "💰 Vendre Tout Maintenant"
SellNowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SellNowBtn.TextSize = 11
SellNowBtn.Font = Enum.Font.GothamMedium
SellNowBtn.Parent = Content

Separator1 = Instance.new("Frame")
Separator1.Size = UDim2.new(1, 0, 0, 2)
Separator1.Position = UDim2.new(0, 0, 0, 216)
Separator1.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
Separator1.BorderSizePixel = 0
Separator1.Parent = Content

AutoEatDrinkBtn = Instance.new("TextButton")
AutoEatDrinkBtn.Size = UDim2.new(1, 0, 0, 28)
AutoEatDrinkBtn.Position = UDim2.new(0, 0, 0, 216)
AutoEatDrinkBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
AutoEatDrinkBtn.Text = "🍔 AUTO EAT / DRINK (50)"
AutoEatDrinkBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
AutoEatDrinkBtn.TextSize = 11
AutoEatDrinkBtn.Font = Enum.Font.GothamBold
AutoEatDrinkBtn.Parent = Content

AutoEatDrinkCorner = Instance.new("UICorner")
AutoEatDrinkCorner.CornerRadius = UDim.new(0, 6)
AutoEatDrinkCorner.Parent = AutoEatDrinkBtn

Separator2 = Instance.new("Frame")
Separator2.Size = UDim2.new(1, 0, 0, 2)
Separator2.Position = UDim2.new(0, 0, 0, 252)
Separator2.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
Separator2.BorderSizePixel = 0
Separator2.Parent = Content

-- Les anciennes cases Nourriture / Boisson étaient créées ici.
-- Elles sont maintenant créées une seule fois dans la mise en page FARM,
-- avec un remplissage animé basé sur readNeedValues().
FoodStatus = nil
DrinkStatus = nil
FoodText = nil
DrinkText = nil
FoodFill = nil
DrinkFill = nil

StartBtn = Instance.new("TextButton")
StartBtn.Size = UDim2.new(1, 0, 0, 35)
StartBtn.Position = UDim2.new(0.51, 0, 0, 216)
StartBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
StartBtn.Text = "🛒 Auto Buy Food"
StartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StartBtn.TextSize = 12
StartBtn.Font = Enum.Font.GothamBold
StartBtn.Parent = Content

StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 8)
StartCorner.Parent = StartBtn

Separator3 = Instance.new("Frame")
Separator3.Size = UDim2.new(1, 0, 0, 2)
Separator3.Position = UDim2.new(0, 0, 0, 373)
Separator3.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
Separator3.BorderSizePixel = 0
Separator3.Parent = Content

-- Section Black Market
BlackMarketBtn = Instance.new("TextButton")
BlackMarketBtn.Size = UDim2.new(1, -215, 0, 32)
BlackMarketBtn.Position = UDim2.new(0, 0, 0, 93)
BlackMarketBtn.BackgroundColor3 = Color3.fromRGB(140, 35, 170)
BlackMarketBtn.Text = "🏃 BLACK MARKET"
BlackMarketBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BlackMarketBtn.TextSize = 11
BlackMarketBtn.Font = Enum.Font.GothamBold
BlackMarketBtn.Parent = Content

BMCorner = Instance.new("UICorner")
BMCorner.CornerRadius = UDim.new(0, 8)
BMCorner.Parent = BlackMarketBtn

ESPToggleBtn = Instance.new("TextButton")
ESPToggleBtn.Size = UDim2.new(1, -215, 0, 32)
ESPToggleBtn.Position = UDim2.new(0, 0, 0, 131)
ESPToggleBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 50)
ESPToggleBtn.Text = "👁️ ESP Black Market"
ESPToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ESPToggleBtn.TextSize = 11
ESPToggleBtn.Font = Enum.Font.GothamMedium
ESPToggleBtn.Parent = Content

ESPCorner = Instance.new("UICorner")
ESPCorner.CornerRadius = UDim.new(0, 6)
ESPCorner.Parent = ESPToggleBtn

--==============================================================
-- AUTO POMPES
-- Ajouté dans l'interface principale. Aucun déplacement de souris.
--==============================================================
AutoPushupBtn = Instance.new("TextButton")
AutoPushupBtn.Size = UDim2.new(1, -215, 0, 32)
AutoPushupBtn.Position = UDim2.new(0, 0, 0, 55)
AutoPushupBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
AutoPushupBtn.Text = "💪 AUTO POMPES : OFF"
AutoPushupBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
AutoPushupBtn.TextSize = 11
AutoPushupBtn.Font = Enum.Font.GothamBold
AutoPushupBtn.Parent = Content

AutoPushupCorner = Instance.new("UICorner")
AutoPushupCorner.CornerRadius = UDim.new(0, 6)
AutoPushupCorner.Parent = AutoPushupBtn

--==============================================================
-- AUTO MINE V32 — CHARACTER AIM SANS CONTROLE CAMERA
-- Déplacement progressif + Noclip, sans TP vers les minerais.
-- Vitesse réglable dans AUTO_MINE_CONFIG.SpeedMultiplier / MaxSpeed.
-- Visée corrigée : caméra + personnage restent centrés sur la roche.
--==============================================================
AutoMineRunService = game:GetService("RunService")
AutoMineVirtualInputManager = game:GetService("VirtualInputManager")
AutoMineRunning = false
AutoMinePreviousFlyEnabled = false
AutoMineNoclipConnection = nil
AutoMineFlyConnection = nil
AutoMineMouseHeld = false

-- V206 : gestion partagée du Noclip entre Auto Mine et le Noclip manuel.
-- Chaque valeur CanCollide est sauvegardée une seule fois, puis restaurée même
-- si une pièce a quitté le personnage (outil rangé, accessoire retiré, respawn).
PRISONRP_NoclipOriginalCollision = PRISONRP_NoclipOriginalCollision or setmetatable({}, {__mode = "k"})
PRISONRP_NoclipSources = PRISONRP_NoclipSources or {AutoMine = false, Movement = false}
PRISONRP_NoclipSources.AutoMine = false
PRISONRP_NoclipSources.Movement = false

function PRISONRP_ApplyNoclipToCharacter(char)
    local sources = PRISONRP_NoclipSources
    local active = sources and (sources.AutoMine == true or sources.Movement == true) or false
    local currentParts = {}

    if char then
        for _, obj in ipairs(char:GetDescendants()) do
            if obj:IsA("BasePart") then
                currentParts[obj] = true
                if active then
                    if PRISONRP_NoclipOriginalCollision[obj] == nil then
                        PRISONRP_NoclipOriginalCollision[obj] = obj.CanCollide
                    end
                    pcall(function() obj.CanCollide = false end)
                end
            end
        end
    end

    -- Restaurer les parties qui ont quitté le personnage, même si le Noclip
    -- reste actif pour les pièces qui en font toujours partie.
    for obj, original in pairs(PRISONRP_NoclipOriginalCollision) do
        if not active or not currentParts[obj] then
            pcall(function()
                -- La propriété reste restaurable même si l'instance a été détachée
                -- temporairement (Parent == nil) puis réutilisée plus tard.
                if obj then obj.CanCollide = original end
            end)
            PRISONRP_NoclipOriginalCollision[obj] = nil
        end
    end
end

function PRISONRP_SetNoclipSource(source, enabled)
    if not PRISONRP_NoclipSources then
        PRISONRP_NoclipSources = {AutoMine = false, Movement = false}
    end
    PRISONRP_NoclipSources[source] = (enabled == true)
    PRISONRP_ApplyNoclipToCharacter(LocalPlayer and LocalPlayer.Character)
end

-- Nettoie à l'initialisation tout reliquat de Noclip provenant d'une ancienne
-- exécution du hub, maintenant que les deux sources ont été mises sur OFF.
pcall(function()
    PRISONRP_ApplyNoclipToCharacter(LocalPlayer and LocalPlayer.Character)
end)

AutoMineMouseX, AutoMineMouseY = 0, 0
AutoMinePreviousCameraType = nil
AutoMinePreviousCameraSubject = nil
AutoMinePreviousCameraCFrame = nil
AutoMinePreviousAutoRotate = nil

AUTO_MINE_CONFIG = {
    SpeedMultiplier = 1,
    MinSpeed = 35,
    MaxSpeed = 35,
    ScanInterval = 0.02,
    MiningTimeout = 15,
    MoveDistance = 4.5,
    HoldDuration = 1.00,
    ReclickInterval = 1.00,
}

-- Position de départ AUTO MINE fournie par l'utilisateur.
-- Le TP n'est effectué qu'une seule fois au lancement de l'AUTO MINE.
AUTO_MINE_START_CFRAME = CFrame.new(
    -356.731995, 4.07552624, 166.393158,
     0.161931038, 0, 0.986802101,
     0, 1, 0,
    -0.986802101, 0, 0.161931038
)

AutoMineBtn = Instance.new("TextButton")
AutoMineBtn.Size = UDim2.new(0.49, 0, 0, 32)
AutoMineBtn.Position = UDim2.new(0, 0, 0, 411)
AutoMineBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
AutoMineBtn.Text = "⛏ AUTO MINE : OFF"
AutoMineBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
AutoMineBtn.TextSize = 11
AutoMineBtn.Font = Enum.Font.GothamBold
AutoMineBtn.Parent = Content

AutoMineBtnCorner = Instance.new("UICorner")
AutoMineBtnCorner.CornerRadius = UDim.new(0, 6)
AutoMineBtnCorner.Parent = AutoMineBtn

AutoMineSellerBtn = Instance.new("TextButton")
AutoMineSellerBtn.Size = UDim2.new(0.49, 0, 0, 32)
AutoMineSellerBtn.Position = UDim2.new(0.51, 0, 0, 411)
AutoMineSellerBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
AutoMineSellerBtn.Text = "📍 TP VENDEUR"
AutoMineSellerBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
AutoMineSellerBtn.TextSize = 11
AutoMineSellerBtn.Font = Enum.Font.GothamBold
AutoMineSellerBtn.Parent = Content

AutoMineSellerCorner = Instance.new("UICorner")
AutoMineSellerCorner.CornerRadius = UDim.new(0, 6)
AutoMineSellerCorner.Parent = AutoMineSellerBtn

AutoMineTpMineBtn = Instance.new("TextButton")
AutoMineTpMineBtn.Size = UDim2.new(0.49, 0, 0, 32)
AutoMineTpMineBtn.Position = UDim2.new(0, 0, 0, 449)
AutoMineTpMineBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
AutoMineTpMineBtn.Text = "📍 TP MINE"
AutoMineTpMineBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
AutoMineTpMineBtn.TextSize = 11
AutoMineTpMineBtn.Font = Enum.Font.GothamBold
AutoMineTpMineBtn.Parent = Content

AutoMineTpMineCorner = Instance.new("UICorner")
AutoMineTpMineCorner.CornerRadius = UDim.new(0, 6)
AutoMineTpMineCorner.Parent = AutoMineTpMineBtn

AutoMineStatus = Instance.new("TextLabel")
AutoMineStatus.Size = UDim2.new(1, 0, 0, 20)
AutoMineStatus.Position = UDim2.new(0, 0, 0, 487)
AutoMineStatus.BackgroundTransparency = 1
AutoMineStatus.Text = "⛏ Mine : OFF"
AutoMineStatus.TextColor3 = Color3.fromRGB(160, 170, 185)
AutoMineStatus.TextSize = 10
AutoMineStatus.Font = Enum.Font.GothamMedium
AutoMineStatus.Parent = Content


function autoMineStatus(s)
    AutoMineStatus.Text = "⛏ Mine : " .. tostring(s)
end

function autoMineCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

function autoMineRoot()
    local char = autoMineCharacter()
    return char:FindFirstChild("HumanoidRootPart")
end

function autoMineFindRocksFolder()
    local candidates = {}

    local prisoner = workspace:FindFirstChild("Prisoner")
    if prisoner then
        local rocks = prisoner:FindFirstChild("Rocks")
        if rocks then table.insert(candidates, rocks) end
    end

    local tasks = workspace:FindFirstChild("Tasks")
    if tasks then
        local taskPrisoner = tasks:FindFirstChild("Prisoner")
        if taskPrisoner then
            local rocks = taskPrisoner:FindFirstChild("Rocks")
            if rocks then table.insert(candidates, rocks) end
        end
    end

    return candidates[1]
end

function autoMineVisiblePart(p)
    return p and p:IsA("BasePart") and p.Transparency < 1
end

function autoMineGetRockPart(obj)
    if autoMineVisiblePart(obj) then
        return obj
    end

    if obj:IsA("Model") and obj.PrimaryPart and autoMineVisiblePart(obj.PrimaryPart) then
        return obj.PrimaryPart
    end

    for _, d in ipairs(obj:GetDescendants()) do
        if autoMineVisiblePart(d) then
            return d
        end
    end

    return nil
end

function autoMineGetActiveRocks()
    local folder = autoMineFindRocksFolder()
    if not folder then return {} end

    local rocks, seen = {}, {}

    for _, obj in ipairs(folder:GetChildren()) do
        local part = autoMineGetRockPart(obj)
        if part and not seen[part] then
            seen[part] = true
            table.insert(rocks, {
                object = obj,
                part = part,
                name = obj.Name,
            })
        end
    end

    if #rocks == 0 then
        for _, d in ipairs(folder:GetDescendants()) do
            if autoMineVisiblePart(d) and not seen[d] then
                seen[d] = true
                table.insert(rocks, {
                    object = d,
                    part = d,
                    name = d.Name,
                })
            end
        end
    end

    return rocks
end

function autoMineNearestRock()
    local r = autoMineRoot()
    if not r then return nil end

    local best, dist = nil, math.huge
    for _, rock in ipairs(autoMineGetActiveRocks()) do
        local p = rock.part
        if p and p.Parent and autoMineVisiblePart(p) then
            local d = (r.Position - p.Position).Magnitude
            if d < dist then
                dist = d
                best = rock
                best.distance = d
            end
        end
    end

    return best
end

function autoMineEquipPickaxe()
    local char = autoMineCharacter()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end

    local function isPick(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local n = string.lower(tool.Name)
        return string.find(n, "pickaxe")
            or string.find(n, "pick axe")
            or string.find(n, "pick")
            or string.find(n, "pioche")
            or string.find(n, "mine")
    end

    local equipped = char:FindFirstChildOfClass("Tool")
    if isPick(equipped) then return equipped end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return nil end

    for _, tool in ipairs(backpack:GetChildren()) do
        if isPick(tool) then
            pcall(function() hum:EquipTool(tool) end)
            task.wait(0.15)
            return char:FindFirstChildOfClass("Tool") or tool
        end
    end

    return nil
end

function autoMineReleaseMouse()
    if not AutoMineMouseHeld then return end
    AutoMineMouseHeld = false
    pcall(function()
        AutoMineVirtualInputManager:SendMouseButtonEvent(
            AutoMineMouseX, AutoMineMouseY, 0, false, game, 0
        )
    end)
end

function autoMineStopFly()
    if AutoMineFlyConnection then
        pcall(function() AutoMineFlyConnection:Disconnect() end)
        AutoMineFlyConnection = nil
    end

    local rr = autoMineRoot()
    local hum = autoMineCharacter():FindFirstChildOfClass("Humanoid")
    if rr then
        pcall(function()
            rr.AssemblyLinearVelocity = Vector3.zero
            rr.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    if hum then
        pcall(function()
            hum.PlatformStand = false
            if AutoMinePreviousAutoRotate ~= nil then
                hum.AutoRotate = AutoMinePreviousAutoRotate
            end
        end)
    end

    -- IMPORTANT : Auto Mine ne touche plus à la caméra.
    -- On efface simplement les anciennes sauvegardes pour éviter toute restauration
    -- d'un état de caméra forcé provenant d'une ancienne version.
    AutoMinePreviousCameraType = nil
    AutoMinePreviousCameraSubject = nil
    AutoMinePreviousCameraCFrame = nil
    AutoMinePreviousAutoRotate = nil
end

function autoMineRestorePreviousFly()
    local shouldResume = (AutoMinePreviousFlyEnabled == true)
    MovementFlyEnabled = shouldResume

    if shouldResume then
        local connectionActive = MovementFlyConnection and MovementFlyConnection.Connected
        if not connectionActive then
            pcall(function()
                if type(movementStartFly) == "function" then movementStartFly() end
            end)
        end
    else
        if MovementFlyConnection or MovementFlyBodyVelocity or MovementFlyBodyGyro then
            pcall(function()
                if type(movementStopFly) == "function" then movementStopFly() end
            end)
        end
    end
end

function autoMineStartAim()
    local hum = autoMineCharacter():FindFirstChildOfClass("Humanoid")
    if hum and AutoMinePreviousAutoRotate == nil then
        pcall(function()
            AutoMinePreviousAutoRotate = hum.AutoRotate
            hum.AutoRotate = false
        end)
    end

    -- Aucun CameraType / CameraSubject / CameraCFrame n'est modifié.
end

function autoMineAimAtPart(part)
    if not part or not part.Parent then return end

    local rr = autoMineRoot()
    if rr then
        pcall(function()
            -- Rotation horizontale uniquement : le personnage regarde la roche
            -- sans incliner son corps et sans toucher à la caméra du joueur.
            local flatTarget = Vector3.new(part.Position.X, rr.Position.Y, part.Position.Z)
            if (flatTarget - rr.Position).Magnitude > 0.05 then
                rr.CFrame = CFrame.lookAt(rr.Position, flatTarget)
            end
        end)
    end
end

function autoMineSetNoclip(enabled)
    if AutoMineNoclipConnection then
        pcall(function() AutoMineNoclipConnection:Disconnect() end)
        AutoMineNoclipConnection = nil
    end

    PRISONRP_SetNoclipSource("AutoMine", enabled == true)
    if not enabled then return end

    AutoMineNoclipConnection = AutoMineRunService.Stepped:Connect(function()
        if not AutoMineRunning then return end
        PRISONRP_ApplyNoclipToCharacter(LocalPlayer.Character)
    end)
end

function autoMineFlyToPosition(targetPosition, maxTime)
    local hum = autoMineCharacter():FindFirstChildOfClass("Humanoid")
    local rr = autoMineRoot()
    if not hum or not rr then return false end

    local started = os.clock()
    local speed = math.clamp(
        math.max(hum.WalkSpeed, 16) * AUTO_MINE_CONFIG.SpeedMultiplier,
        AUTO_MINE_CONFIG.MinSpeed,
        AUTO_MINE_CONFIG.MaxSpeed
    )

    autoMineSetNoclip(true)
    pcall(function()
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.Freefall)
    end)

    AutoMineFlyConnection = AutoMineRunService.Heartbeat:Connect(function()
        if not AutoMineRunning then
            autoMineStopFly()
            return
        end

        local rootNow = autoMineRoot()
        if not rootNow then return end

        local delta = targetPosition - rootNow.Position
        local distance = delta.Magnitude

        if distance <= AUTO_MINE_CONFIG.MoveDistance then
            autoMineStopFly()
            pcall(function() hum:Move(Vector3.zero, false) end)
            return
        end

        local direction = delta.Unit

        pcall(function()
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.Freefall)
            rootNow.AssemblyLinearVelocity =
                direction * math.min(speed, distance * 3)
        end)

        pcall(function()
            hum:Move(direction, false)
        end)
    end)

    while AutoMineRunning and os.clock() - started < (maxTime or 12) do
        local rrNow = autoMineRoot()
        if not rrNow then
            autoMineStopFly()
            return false
        end

        if (rrNow.Position - targetPosition).Magnitude <= AUTO_MINE_CONFIG.MoveDistance then
            autoMineStopFly()
            pcall(function() hum:Move(Vector3.zero, false) end)
            return true
        end

        task.wait(0.05)
    end

    autoMineStopFly()
    return false
end

function autoMineMine(rock)
    local r = autoMineRoot()
    if not r or not rock or not rock.object then return false end

    local rockObject = rock.object
    local currentPart = autoMineGetRockPart(rockObject)
    if not currentPart then return false end

    local hum = autoMineCharacter():FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    autoMineSetNoclip(true)

    -- Déplacement en Fly + noclip vers la roche.
    -- On vise légèrement au-dessus de la roche pour éviter d'entrer dans son volume.
    local targetPosition = currentPart.Position + Vector3.new(0, 2.5, 0)
    autoMineFlyToPosition(targetPosition, 12)

    local h = autoMineCharacter():FindFirstChildOfClass("Humanoid")
    local rr2 = autoMineRoot()
    if h then
        pcall(function()
            h:Move(Vector3.zero, false)
            h.PlatformStand = false
            h:ChangeState(Enum.HumanoidStateType.Freefall)
        end)
    end
    if rr2 then
        pcall(function() rr2.AssemblyLinearVelocity = Vector3.zero end)
    end

    local lastPart = currentPart
    local phase = 1
    local last = 0
    local missingSince = nil

    autoMineStartAim()

    while AutoMineRunning and rockObject.Parent do
        currentPart = autoMineGetRockPart(rockObject)

        if currentPart then
            missingSince = nil

            -- Oriente uniquement le personnage vers la roche.
            -- La caméra reste entièrement contrôlée par le joueur.
            autoMineAimAtPart(currentPart)

            if currentPart ~= lastPart then
                lastPart = currentPart
                phase += 1
                autoMineStatus(string.format(
                    "%s — phase %d",
                    rockObject.Name, phase
                ))
            end
        else
            if not missingSince then
                missingSince = os.clock()
            end

            if os.clock() - missingSince >= 2 then
                autoMineReleaseMouse()
                autoMineSetNoclip(false)
                return true
            end
        end

        local tool = autoMineEquipPickaxe()
        if not tool then
            autoMineStatus("⚠ Pioche introuvable")
            autoMineReleaseMouse()
            task.wait(0.5)
            continue
        end

        if os.clock() - last >= AUTO_MINE_CONFIG.ReclickInterval then
            last = os.clock()
            autoMineReleaseMouse()

            local camera = workspace.CurrentCamera
            if camera then
                local v = camera.ViewportSize
                local x = math.floor(v.X / 2)
                local y = math.floor(v.Y / 2)
                AutoMineMouseX, AutoMineMouseY = x, y

                pcall(function()
                    AutoMineVirtualInputManager:SendMouseButtonEvent(
                        x, y, 0, true, game, 0
                    )
                end)

                AutoMineMouseHeld = true

                pcall(function()
                    tool:Activate()
                end)

                task.wait(AUTO_MINE_CONFIG.HoldDuration)

                pcall(function()
                    AutoMineVirtualInputManager:SendMouseButtonEvent(
                        x, y, 0, false, game, 0
                    )
                end)
                AutoMineMouseHeld = false
            end
        end

        task.wait(0.04)
    end

    autoMineReleaseMouse()
    autoMineSetNoclip(false)
    autoMineStopFly()
    return true
end

function autoMineTpSeller()
    local r = autoMineRoot()
    local entities = workspace:FindFirstChild("Entities")
    local buyer = entities and entities:FindFirstChild("Mineral Buyer")
    local buyerRoot = buyer and buyer:FindFirstChild("HumanoidRootPart")

    if not r or not buyerRoot then
        autoMineStatus("⚠ Mineral Buyer introuvable")
        return
    end

    -- TP vendeur uniquement, sans interaction avec le Prompt.
    pcall(function()
        local frontPos = buyerRoot.Position + (buyerRoot.CFrame.LookVector * 4) + Vector3.new(0, 1.5, 0)
        r.CFrame = CFrame.lookAt(frontPos, buyerRoot.Position + Vector3.new(0, 1, 0))
    end)

    autoMineStatus("📍 TP vendeur effectué")
end

function autoMineStop()
    AutoMineRunning = false
    autoMineReleaseMouse()
    autoMineStopFly()
    autoMineSetNoclip(false)

    -- Restaure l'état du Fly d'avant Auto Mine sans créer de boucle en double.
    autoMineRestorePreviousFly()

    AutoMineBtn.Text = "⛏ AUTO MINE : OFF"
    AutoMineBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
    autoMineStatus("OFF")
end

function autoMineTeleportToMineStart()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then
        return false
    end

    local ok = pcall(function()
        root.CFrame = AUTO_MINE_START_CFRAME
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    if ok then
        autoMineStatus("📍 Position mine")
        task.wait(0.15)
    end

    return ok
end

function autoMineStart()
    if AutoMineRunning then return end

    AutoMinePreviousFlyEnabled = (MovementFlyEnabled == true)

    -- Retire complètement les contrôleurs du Fly manuel avant qu'Auto Mine
    -- utilise sa propre boucle de déplacement. On conserve l'état à restaurer.
    pcall(function()
        if type(movementStopFly) == "function" then movementStopFly(true) end
    end)
    MovementFlyEnabled = false

    AutoMineRunning = true
    AutoMineBtn.Text = "⛏ AUTO MINE : ON"
    AutoMineBtn.BackgroundColor3 = Color3.fromRGB(40, 145, 75)

    task.spawn(function()
        while AutoMineRunning do
            local folder = autoMineFindRocksFolder()

            if not folder then
                autoMineStatus("⚠ Aucun chemin Rocks")
                task.wait(1)
                continue
            end

            local rocks = autoMineGetActiveRocks()
            if #rocks == 0 then
                autoMineStatus("⚠ 0 roche active")
                task.wait(AUTO_MINE_CONFIG.ScanInterval)
                continue
            end

            local target = autoMineNearestRock()
            if target then
                autoMineStatus(string.format(
                    "%s — %.0f studs",
                    target.name, target.distance or 0
                ))
                autoMineMine(target)
            else
                autoMineStatus("⚠ Cible impossible")
                task.wait(AUTO_MINE_CONFIG.ScanInterval)
            end

            autoMineReleaseMouse()
            task.wait(0.08)
        end

        autoMineReleaseMouse()
        autoMineStopFly()
        autoMineSetNoclip(false)
        autoMineRestorePreviousFly()
        autoMineStatus("OFF")
    end)
end

AutoMineBtn.MouseButton1Click:Connect(function()
    if AutoMineRunning then
        autoMineStop()
    else
        autoMineStart()
    end
end)

AutoMineSellerBtn.MouseButton1Click:Connect(function()
    if AutoMineRunning then
        autoMineReleaseMouse()
    end
    autoMineTpSeller()
end)

AutoMineTpMineBtn.MouseButton1Click:Connect(function()
    autoMineTeleportToMineStart()
end)

-- Initialisation des dépendances après construction de l'UI.
task.spawn(function()
    local ok, err = pcall(function()
        FishingSystem = ReplicatedStorage:WaitForChild("FishingSystem", 20)
        if not FishingSystem then error("FishingSystem introuvable") end
        FishingModules = FishingSystem:WaitForChild("FishingModules", 20)
        if not FishingModules then error("FishingModules introuvable") end
        MinigameSystem = require(FishingModules:WaitForChild("MinigameSystem", 20))
        SoundManager = require(FishingModules:WaitForChild("SoundManager", 20))
        GUIManager = require(FishingModules:WaitForChild("GUIManager", 20))
        InventoryEvents = FishingSystem:WaitForChild("InventoryEvents", 20)
        Inventory_SellAll = InventoryEvents and InventoryEvents:FindFirstChild("Inventory_SellAll")
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
        if remotes then
            local toolFolder = remotes:WaitForChild("Tool", 20)
            if toolFolder then ToolEvent = toolFolder:WaitForChild("Event", 20) end
        end
        local map = workspace:WaitForChild("Map", 20)
        local cells = map and map:WaitForChild("Cells", 20)
        local props = cells and cells:WaitForChild("Props", 20)
        vendingMachine = props and props:FindFirstChild("Red Vending Machine")
        if vendingMachine then
            local money = vendingMachine:FindFirstChild("Money")
            local prompt = money and money:FindFirstChild("Prompt")
            foodEvent = prompt and prompt:FindFirstChild("Food") and prompt.Food:FindFirstChild("Event")
            drinkEvent = prompt and prompt:FindFirstChild("Drink") and prompt.Drink:FindFirstChild("Event")
        end
    end)
    if ok then
    else
        warn("[Hub Prison RP] Dépendances non disponibles : " .. tostring(err))
    end
end)

--==============================================================
-- AUTO POMPES - moteur de la version standalone qui fonctionne
-- Utilise PlayEmote("Pompes"), MainGui.Pushups, Track/Zone/Needle
-- et envoie uniquement ESPACE (aucun clic souris).
--==============================================================
PushupReplicatedStorage = game:GetService("ReplicatedStorage")
PushupVirtualInputManager = game:GetService("VirtualInputManager")
PushupPlayerGui = LocalPlayer:WaitForChild("PlayerGui")

PUSHUP_PRESS_COOLDOWN = 0.08
PUSHUP_CHECK_INTERVAL = 0.01
PUSHUP_ZONE_MARGIN = 0
PushupLastPress = 0

function findPushupsGui()
    local mainGui = PushupPlayerGui:FindFirstChild("MainGui")

    if not mainGui then
        for _, obj in ipairs(PushupPlayerGui:GetDescendants()) do
            if obj.Name == "Pushups" then
                local parent = obj.Parent
                if parent then
                    return obj
                end
            end
        end
        return nil
    end

    return mainGui:FindFirstChild("Pushups", true)
end

function getTrackObjects()
    local pushups = findPushupsGui()

    if not pushups then
        return nil, nil, nil
    end

    local track = pushups:FindFirstChild("Track", true)
    if not track then
        return pushups, nil, nil
    end

    local zone = track:FindFirstChild("Zone", true)
    local needle = track:FindFirstChild("Needle", true)

    return pushups, zone, needle
end

function activatePompes()
    local remotes = PushupReplicatedStorage:FindFirstChild("Remotes")

    if not remotes then
        return false
    end

    local playEmote = remotes:FindFirstChild("PlayEmote")

    if not playEmote then
        return false
    end

    local ok = pcall(function()
        playEmote:FireServer("Pompes")
    end)

    return ok
end

function pressPushupSpace()
    local now = os.clock()

    if now - PushupLastPress < PUSHUP_PRESS_COOLDOWN then
        return
    end

    PushupLastPress = now

    pcall(function()
        PushupVirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.Space,
            false,
            game
        )

        task.wait(0.025)

        PushupVirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.Space,
            false,
            game
        )
    end)
end

function needleIsInsidePushupZone(zone, needle)
    if not zone or not needle then
        return false
    end

    local zonePos = zone.Position.X.Scale
    local zoneSize = zone.Size.X.Scale
    local needlePos = needle.Position.X.Scale

    if zoneSize == 0 and zone.AbsoluteSize.X > 0 then
        local left = zone.AbsolutePosition.X
        local right = left + zone.AbsoluteSize.X
        local center = needle.AbsolutePosition.X + needle.AbsoluteSize.X / 2

        return center >= left and center <= right
    end

    local left = zonePos - PUSHUP_ZONE_MARGIN
    local right = zonePos + zoneSize + PUSHUP_ZONE_MARGIN
    local needleCenter = needlePos + (needle.Size.X.Scale / 2)

    return needleCenter >= left and needleCenter <= right
end


--==============================================================
-- OUTILS DE DÉPLACEMENT : WALKSPEED / FLY / NOCLIP
--==============================================================
MovementRunService = game:GetService("RunService")
MovementUserInputService = game:GetService("UserInputService")
MovementWalkSpeed = 35
MovementFlySpeed = 80
MovementWalkSpeedEnabled = false
MovementNormalWalkSpeed = nil
MovementTrackedCharacter = nil
MovementFlyEnabled = false
MovementNoclipEnabled = false
MovementFlyConnection = nil
MovementFlyBodyVelocity = nil
MovementFlyBodyGyro = nil
MovementNoclipConnection = nil
MovementInputBegan = nil
MovementInputEnded = nil
MovementCharacterConnection = nil
MovementKeys = {W=false,A=false,S=false,D=false,Space=false,Ctrl=false}
running = true

-- V191 : Anti-AFK Auto-Fish
-- Actif uniquement lorsque Auto-Fish est actif.
-- Utilise Player.Idled + VirtualUser au moment exact où Roblox détecte l'inactivité.
do
    pcall(function()
        if type(_G.PRISONRP_ANTIAFK_STOP) == "function" then
            _G.PRISONRP_ANTIAFK_STOP()
        end
    end)

    local __antiAFKRunning = true
    local __antiAFKConnection = nil
    local __antiAFKVirtualUser = nil

    pcall(function()
        __antiAFKVirtualUser = game:GetService("VirtualUser")
    end)

    pcall(function()
        __antiAFKConnection = LocalPlayer.Idled:Connect(function()
            if not __antiAFKRunning or _G.AutoFishingEnabled ~= true then
                return
            end

            if not __antiAFKVirtualUser then
                return
            end

            pcall(function()
                __antiAFKVirtualUser:CaptureController()
                __antiAFKVirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end)

    _G.PRISONRP_ANTIAFK_STOP = function()
        __antiAFKRunning = false
        pcall(function()
            if __antiAFKConnection then
                __antiAFKConnection:Disconnect()
            end
        end)
        __antiAFKConnection = nil
    end
end

--==============================================================
-- DÉPLACEMENT : intégré directement dans le même ScrollingFrame
--==============================================================
MovementTitle = Instance.new("TextLabel")
MovementTitle.Size = UDim2.new(1, 0, 0, 24)
MovementTitle.Position = UDim2.new(0, 0, 0, 565)
MovementTitle.BackgroundColor3 = Color3.fromRGB(28, 38, 45)
MovementTitle.Text = "⚡ DÉPLACEMENT"
MovementTitle.TextColor3 = Color3.fromRGB(100, 210, 255)
MovementTitle.TextSize = 12
MovementTitle.Font = Enum.Font.GothamBold
MovementTitle.Parent = Content

MovementSpeedBox = Instance.new("TextBox")
MovementSpeedBox.Size = UDim2.new(0.49, 0, 0, 32)
MovementSpeedBox.Position = UDim2.new(0, 0, 0, 595)
MovementSpeedBox.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
MovementSpeedBox.Text = "50"
MovementSpeedBox.PlaceholderText = "SpeedHack"
MovementSpeedBox.TextColor3 = Color3.fromRGB(235, 235, 235)
MovementSpeedBox.TextSize = 11
MovementSpeedBox.Font = Enum.Font.GothamBold
MovementSpeedBox.ClearTextOnFocus = false
MovementSpeedBox.Font = Enum.Font.GothamMedium
MovementSpeedBox.TextSize = 16
MovementSpeedBox.TextXAlignment = Enum.TextXAlignment.Center
MovementSpeedBox.TextYAlignment = Enum.TextYAlignment.Center
MovementSpeedBox.Parent = Content

MovementFlySpeedBox = Instance.new("TextBox")
MovementFlySpeedBox.Size = UDim2.new(0.49, 0, 0, 32)
MovementFlySpeedBox.Position = UDim2.new(0, 0, 0, 633)
MovementFlySpeedBox.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
MovementFlySpeedBox.Text = "80"
MovementFlySpeedBox.PlaceholderText = "Fly Speed"
MovementFlySpeedBox.TextColor3 = Color3.fromRGB(235, 235, 235)
MovementFlySpeedBox.TextSize = 11
MovementFlySpeedBox.Font = Enum.Font.GothamBold
MovementFlySpeedBox.ClearTextOnFocus = false
MovementFlySpeedBox.Parent = Content

MovementSpeedBtn = Instance.new("TextButton")
MovementSpeedBtn.Size = UDim2.new(0.49, 0, 0, 32)
MovementSpeedBtn.Position = UDim2.new(0.51, 0, 0, 595)
MovementSpeedBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
MovementSpeedBtn.Text = "🏃 SPEEDHACK : OFF"
MovementSpeedBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
MovementSpeedBtn.TextSize = 11
MovementSpeedBtn.Font = Enum.Font.GothamBold
MovementSpeedBtn.TextSize = 11
MovementSpeedBtn.TextXAlignment = Enum.TextXAlignment.Center
MovementSpeedBtn.TextYAlignment = Enum.TextYAlignment.Center
MovementSpeedBtn.Parent = Content

MovementFlyBtn = Instance.new("TextButton")
MovementFlyBtn.Size = UDim2.new(0.49, 0, 0, 32)
MovementFlyBtn.Position = UDim2.new(0.51, 0, 0, 633)
MovementFlyBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
MovementFlyBtn.Text = "✈ FLY"
MovementFlyBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
MovementFlyBtn.TextSize = 11
MovementFlyBtn.Font = Enum.Font.GothamBold
MovementFlyBtn.Parent = Content

MovementNoclipBtn = Instance.new("TextButton")
MovementNoclipBtn.Size = UDim2.new(0.49, 0, 0, 32)
MovementNoclipBtn.Position = UDim2.new(0, 0, 0, 671)
MovementNoclipBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
MovementNoclipBtn.Text = "👻 NOCLIP : OFF"
MovementNoclipBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
MovementNoclipBtn.TextSize = 11
MovementNoclipBtn.Font = Enum.Font.GothamBold
MovementNoclipBtn.Parent = Content

MovementHint = Instance.new("TextLabel")
MovementHint.Size = UDim2.new(1, 0, 0, 28)
MovementHint.Position = UDim2.new(0, 0, 0, 709)
MovementHint.BackgroundTransparency = 1
MovementHint.Text = "Fly : WASD • Espace = monter • Ctrl = descendre • Vitesse Fly réglable à gauche"
MovementHint.TextColor3 = Color3.fromRGB(130, 140, 155)
MovementHint.TextSize = 9
MovementHint.Font = Enum.Font.GothamMedium
MovementHint.Parent = Content

function movementGetCharacter()
    return LocalPlayer.Character
end

function movementGetHumanoid()
    local char = movementGetCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

function movementCleanup()
    pcall(function()
        if type(movementStopFly) == "function" then movementStopFly() end
    end)
    MovementWalkSpeedEnabled = false
    MovementFlyEnabled = false
    pcall(function() movementSetNoclip(false) end)
    if MovementFlyConnection then pcall(function() MovementFlyConnection:Disconnect() end) end
    MovementFlyConnection = nil
    if MovementNoclipConnection then pcall(function() MovementNoclipConnection:Disconnect() end) end
    MovementNoclipConnection = nil
    if MovementInputBegan then pcall(function() MovementInputBegan:Disconnect() end) end
    MovementInputBegan = nil
    if MovementInputEnded then pcall(function() MovementInputEnded:Disconnect() end) end
    MovementInputEnded = nil
    if MovementCharacterConnection then pcall(function() MovementCharacterConnection:Disconnect() end) end
    MovementCharacterConnection = nil
    if MovementHumanoidSpeedConnection then pcall(function() MovementHumanoidSpeedConnection:Disconnect() end) end
    MovementHumanoidSpeedConnection = nil
    if MovementWalkSpeedHeartbeat then pcall(function() MovementWalkSpeedHeartbeat:Disconnect() end) end
    MovementWalkSpeedHeartbeat = nil
    local hum = movementGetHumanoid()
    if hum then
        local restoreSpeed = tonumber(MovementNormalWalkSpeed)
        if restoreSpeed then
            pcall(function() hum.WalkSpeed = restoreSpeed end)
        end
    end
    local char = movementGetCharacter()
    if char then
        -- Ne restaure que les valeurs réellement mémorisées. Si Auto Mine utilise
        -- encore le Noclip, les collisions restent désactivées jusqu'à son arrêt.
        pcall(function() PRISONRP_ApplyNoclipToCharacter(char) end)
    end
end

_G.PRISONRP_MOVEMENT_CLEANUP = movementCleanup


function movementGetRoot()
    local char = movementGetCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

function movementApplyWalkSpeed()
    local hum = movementGetHumanoid()
    if not hum then return end

    -- OFF : ne touche pas à la vitesse normale du jeu.
    if not MovementWalkSpeedEnabled then
        return
    end

    local wanted = math.clamp(tonumber(MovementWalkSpeed) or 35, 1, 250)
    if hum.WalkSpeed ~= wanted then
        pcall(function()
            hum.WalkSpeed = wanted
        end)
    end
end

-- V187 : nettoyage renforcé du Fly et restauration de la gravité normale.

-- Si le jeu réécrit WalkSpeed, on conserve aussi la vitesse horizontale voulue
-- tant que le joueur se déplace. La composante verticale est préservée.
function movementApplyVelocitySpeed()
    if not MovementWalkSpeedEnabled then return end

    local hum = movementGetHumanoid()
    local root = movementGetRoot()
    if not hum or not root then return end

    local move = hum.MoveDirection
    if move.Magnitude <= 0.05 then return end

    local horizontal = Vector3.new(move.X, 0, move.Z)
    if horizontal.Magnitude <= 0.05 then return end

    horizontal = horizontal.Unit * math.clamp(MovementWalkSpeed, 1, 250)
    local current = root.AssemblyLinearVelocity
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(horizontal.X, current.Y, horizontal.Z)
    end)
end

-- Capture la vitesse normale du jeu avant de brancher la boucle.
do
    local hum = movementGetHumanoid()
    if hum then
        local previous = tonumber(_G.PRISONRP_PREVIOUS_NORMAL_WALKSPEED)
        MovementNormalWalkSpeed = previous or hum.WalkSpeed
        pcall(function()
            if not MovementWalkSpeedEnabled and previous and hum.WalkSpeed ~= previous then
                hum.WalkSpeed = previous
            end
        end)
        MovementTrackedCharacter = LocalPlayer.Character
    end
end

-- Certains jeux réécrivent WalkSpeed régulièrement : on le réapplique en continu.
MovementWalkSpeedHeartbeat = MovementRunService.Heartbeat:Connect(function()
    if running then
        movementApplyWalkSpeed()
        movementApplyVelocitySpeed()
    end
end)

MovementHumanoidSpeedConnection = nil
function movementHookHumanoid(hum)
    if MovementHumanoidSpeedConnection then
        pcall(function()
            MovementHumanoidSpeedConnection:Disconnect()
        end)
        MovementHumanoidSpeedConnection = nil
    end

    if not hum then return end

    MovementTrackedCharacter = LocalPlayer.Character

    -- Mémorise la vitesse normale définie par le jeu.
    if not MovementWalkSpeedEnabled then
        MovementNormalWalkSpeed = hum.WalkSpeed
    end

    MovementHumanoidSpeedConnection = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if running and MovementWalkSpeedEnabled and hum.WalkSpeed ~= MovementWalkSpeed then
            pcall(function()
                hum.WalkSpeed = MovementWalkSpeed
            end)
        end
    end)

    movementApplyWalkSpeed()
end

function movementSetNoclip(enabled)
    MovementNoclipEnabled = (enabled == true)

    if MovementNoclipConnection then
        pcall(function() MovementNoclipConnection:Disconnect() end)
        MovementNoclipConnection = nil
    end

    PRISONRP_SetNoclipSource("Movement", MovementNoclipEnabled)

    if MovementNoclipEnabled then
        -- Réapplique le Noclip aux nouvelles parties sans perdre leur CanCollide d'origine.
        MovementNoclipConnection = MovementRunService.Stepped:Connect(function()
            if not MovementNoclipEnabled then return end
            PRISONRP_ApplyNoclipToCharacter(movementGetCharacter())
        end)
    end
end

-- V204 : arrêt du Fly propre, remise du personnage à la verticale et reprise
-- de l'état Humanoid normal. Si le Noclip est resté actif, on le coupe aussi
-- à l'arrêt du Fly pour éviter de traverser le sol pendant l'atterrissage.
function movementStopFly(keepPose)
    if MovementFlyConnection then
        pcall(function()
            MovementFlyConnection:Disconnect()
        end)
        MovementFlyConnection = nil
    end

    -- Retire d'abord les contrôleurs pour que la physique normale puisse reprendre.
    if MovementFlyBodyVelocity then
        pcall(function() MovementFlyBodyVelocity:Destroy() end)
        MovementFlyBodyVelocity = nil
    end
    if MovementFlyBodyGyro then
        pcall(function() MovementFlyBodyGyro:Destroy() end)
        MovementFlyBodyGyro = nil
    end

    -- Reset des touches pour éviter une reprise de mouvement fantôme.
    MovementKeys.W = false
    MovementKeys.A = false
    MovementKeys.S = false
    MovementKeys.D = false
    MovementKeys.Space = false
    MovementKeys.Ctrl = false

    local root = movementGetRoot()
    local hum = movementGetHumanoid()

    -- Nettoie aussi les BodyMovers orphelins d'un ancien chargement si leurs
    -- références Lua avaient été perdues avant l'arrêt du Fly.
    if root then
        for _, mover in ipairs(root:GetChildren()) do
            local isOldFlyVelocity = mover:IsA("BodyVelocity") and mover.Name == "PRISONRP_FlyVelocity"
            local isOldFlyGyro = mover:IsA("BodyGyro") and mover.Name == "PRISONRP_FlyGyro"
            if isOldFlyVelocity or isOldFlyGyro then
                pcall(function() mover:Destroy() end)
            end
        end
    end

    if root then
        pcall(function()
            root.Anchored = false

            if not keepPose then
                -- La rotation de vol peut incliner tout le personnage. À l'arrêt,
                -- on garde le cap horizontal, mais on remet le corps bien droit.
                local flatLook = Vector3.zero
                local camera = workspace.CurrentCamera
                if camera then
                    flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
                end
                if flatLook.Magnitude < 0.001 then
                    flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
                end
                if flatLook.Magnitude < 0.001 then
                    flatLook = Vector3.new(0, 0, -1)
                end
                root.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit, Vector3.yAxis)
            end

            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    -- Le Fly place le Humanoid en Physics/PlatformStand. Le forcer à reprendre
    -- un état normal évite qu'il reste couché ou en chute physique indéfinie.
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.AutoRotate = true
            if not keepPose then
                if hum.FloorMaterial == Enum.Material.Air then
                    hum:ChangeState(Enum.HumanoidStateType.Freefall)
                else
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end)

        if not keepPose then
            local stoppedHumanoid = hum
            task.delay(0.15, function()
                if not stoppedHumanoid.Parent or stoppedHumanoid.Health <= 0 or MovementFlyEnabled then
                    return
                end
                pcall(function()
                    stoppedHumanoid.PlatformStand = false
                    stoppedHumanoid.AutoRotate = true
                    if stoppedHumanoid.FloorMaterial == Enum.Material.Air then
                        stoppedHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                    else
                        stoppedHumanoid:ChangeState(Enum.HumanoidStateType.Running)
                    end
                end)
            end)
        end
    end

    -- Noclip activé = aucune collision avec le sol. On le désactive à l'arrêt
    -- du Fly pour garantir un atterrissage normal et synchroniser le bouton.
    if not keepPose and MovementNoclipEnabled then
        pcall(function() movementSetNoclip(false) end)
        if MovementNoclipBtn then
            MovementNoclipBtn.Text = "👻 NOCLIP : OFF"
            MovementNoclipBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
        end
    end
end

-- V204 : Fly piloté par la caméra. W/S suivent le LookVector complet.
-- Le corps s'incline pendant le vol et est remis à la verticale quand on coupe le Fly.
function movementStartFly()
    -- Auto Mine utilise son propre moteur de déplacement : ne jamais créer ses
    -- contrôleurs de Fly manuel en même temps.
    if AutoMineRunning then
        MovementFlyEnabled = false
        return
    end

    -- Garder la pose lors du remplacement des contrôleurs : ne pas déclencher
    -- artificiellement la séquence d'atterrissage pendant un redémarrage du Fly.
    movementStopFly(true)

    local root = movementGetRoot()
    local hum = movementGetHumanoid()
    if not root or not hum then return end

    MovementFlyBodyVelocity = Instance.new("BodyVelocity")
    MovementFlyBodyVelocity.Name = "PRISONRP_FlyVelocity"
    MovementFlyBodyVelocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    MovementFlyBodyVelocity.P = 25000
    MovementFlyBodyVelocity.Velocity = Vector3.zero
    MovementFlyBodyVelocity.Parent = root

    MovementFlyBodyGyro = Instance.new("BodyGyro")
    MovementFlyBodyGyro.Name = "PRISONRP_FlyGyro"
    MovementFlyBodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    MovementFlyBodyGyro.P = 45000
    MovementFlyBodyGyro.D = 1200
    MovementFlyBodyGyro.CFrame = root.CFrame
    MovementFlyBodyGyro.Parent = root

    pcall(function()
        hum.AutoRotate = false
        hum.PlatformStand = true
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end)

    MovementFlyConnection = MovementRunService.Heartbeat:Connect(function()
        if not MovementFlyEnabled then return end

        local currentRoot = movementGetRoot()
        local currentHum = movementGetHumanoid()
        local camera = workspace.CurrentCamera
        if not currentRoot or not currentHum or not camera then return end

        -- Si le personnage a respawn, recréer les contrôleurs sur le nouveau root.
        if MovementFlyBodyVelocity and MovementFlyBodyVelocity.Parent ~= currentRoot then
            movementStartFly()
            return
        end

        local cf = camera.CFrame
        local forward = cf.LookVector
        local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
        if right.Magnitude > 0.001 then
            right = right.Unit
        else
            right = Vector3.new(currentRoot.CFrame.RightVector.X, 0, currentRoot.CFrame.RightVector.Z)
            if right.Magnitude > 0.001 then right = right.Unit end
        end

        local direction = Vector3.zero
        if MovementKeys.W then direction += forward end
        if MovementKeys.S then direction -= forward end
        if MovementKeys.D then direction += right end
        if MovementKeys.A then direction -= right end
        if MovementKeys.Space then direction += Vector3.yAxis end
        if MovementKeys.Ctrl then direction -= Vector3.yAxis end
        if direction.Magnitude > 1 then direction = direction.Unit end

        local speed = math.clamp(tonumber(MovementFlySpeed) or 80, 10, 500)
        if MovementFlyBodyVelocity then
            MovementFlyBodyVelocity.Velocity = direction * speed
        else
            currentRoot.AssemblyLinearVelocity = direction * speed
        end

        -- Copie la rotation complète de la caméra pendant le vol.
        if MovementFlyBodyGyro then
            MovementFlyBodyGyro.CFrame = CFrame.new(currentRoot.Position) * cf.Rotation
        end

        pcall(function()
            currentHum.PlatformStand = true
            currentHum.AutoRotate = false
            currentHum:ChangeState(Enum.HumanoidStateType.Physics)
        end)
    end)
end

MovementSpeedBtn.MouseButton1Click:Connect(function()
    local value = tonumber(MovementSpeedBox.Text)
    if value then
        MovementWalkSpeed = math.clamp(value, 1, 250)
        MovementSpeedBox.Text = tostring(MovementWalkSpeed)
    else
        MovementSpeedBox.Text = tostring(MovementWalkSpeed)
    end
    MovementWalkSpeedEnabled = not MovementWalkSpeedEnabled
    movementApplyWalkSpeed()
    MovementSpeedBtn.Text = MovementWalkSpeedEnabled and ("🏃 SPEEDHACK : ON (" .. MovementWalkSpeed .. ")") or "🏃 SPEEDHACK : OFF"
    MovementSpeedBtn.BackgroundColor3 = MovementWalkSpeedEnabled and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(45, 48, 62)
end)

MovementSpeedBox.FocusLost:Connect(function()
    local value = tonumber(MovementSpeedBox.Text)
    if value then
        MovementWalkSpeed = math.clamp(value, 1, 250)
        MovementSpeedBox.Text = tostring(MovementWalkSpeed)
        if MovementWalkSpeedEnabled then movementApplyWalkSpeed() end
    else
        MovementSpeedBox.Text = tostring(MovementWalkSpeed)
    end
end)

MovementFlySpeedBox.FocusLost:Connect(function()
    local value = tonumber(MovementFlySpeedBox.Text)
    if value then
        MovementFlySpeed = math.clamp(value, 10, 500)
        MovementFlySpeedBox.Text = tostring(MovementFlySpeed)
        if type(_G.PRISONRP_SETTINGS_SET_FLYSPEED) == "function" then
            pcall(_G.PRISONRP_SETTINGS_SET_FLYSPEED, MovementFlySpeed)
        end
    else
        MovementFlySpeedBox.Text = tostring(MovementFlySpeed)
    end
end)

MovementFlyBtn.MouseButton1Click:Connect(function()
    MovementFlyEnabled = not MovementFlyEnabled
    if MovementFlyEnabled then
        movementStartFly()
    else
        movementStopFly()
    end
    MovementFlyBtn.Text = "✈ FLY"
    MovementFlyBtn.BackgroundColor3 = MovementFlyEnabled and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(45, 48, 62)
end)

MovementNoclipBtn.MouseButton1Click:Connect(function()
    movementSetNoclip(not MovementNoclipEnabled)
    MovementNoclipBtn.Text = MovementNoclipEnabled and "👻 NOCLIP : ON" or "👻 NOCLIP : OFF"
    MovementNoclipBtn.BackgroundColor3 = MovementNoclipEnabled and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(45, 48, 62)
end)

MovementInputBegan = MovementUserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.W then MovementKeys.W = true end
    if input.KeyCode == Enum.KeyCode.A then MovementKeys.A = true end
    if input.KeyCode == Enum.KeyCode.S then MovementKeys.S = true end
    if input.KeyCode == Enum.KeyCode.D then MovementKeys.D = true end
    if input.KeyCode == Enum.KeyCode.Space then MovementKeys.Space = true end
    if input.KeyCode == Enum.KeyCode.LeftControl then MovementKeys.Ctrl = true end
end)

MovementInputEnded = MovementUserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.W then MovementKeys.W = false end
    if input.KeyCode == Enum.KeyCode.A then MovementKeys.A = false end
    if input.KeyCode == Enum.KeyCode.S then MovementKeys.S = false end
    if input.KeyCode == Enum.KeyCode.D then MovementKeys.D = false end
    if input.KeyCode == Enum.KeyCode.Space then MovementKeys.Space = false end
    if input.KeyCode == Enum.KeyCode.LeftControl then MovementKeys.Ctrl = false end
end)

MovementCharacterConnection = LocalPlayer.CharacterAdded:Connect(function(char)
    -- Une mort/respawn invalide l'ancienne position de retour.
    TeleportSavedCFrame = nil
    TeleportSavedCharacter = nil
    TeleportAtTarget = false
    TeleportReturnMode = nil
    if TeleportBtn then TeleportBtn.Text = "📍 TP Shore" end
    if BlackMarketBtn then BlackMarketBtn.Text = "🛒 TP BLACK MARKET" end

    task.wait(0.5)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    movementHookHumanoid(hum)
    movementApplyWalkSpeed()
    if MovementNoclipEnabled then movementSetNoclip(true) end
    if MovementFlyEnabled then movementStartFly() end
end)

movementHookHumanoid(movementGetHumanoid())

--==============================================================
-- STAFF ESP INTÉGRÉ AU HUB
-- Même détection que le script Staff ESP fourni, mais sans créer
-- une deuxième interface. Le hub principal reste unique et défilant.
--==============================================================
StaffESPEnabled = false
StaffAutoLeaveEnabled = false
StaffAutoLeaveDelay = 0.15
StaffESPColor = Color3.fromRGB(255, 45, 45)
StaffOutlineColor = Color3.fromRGB(255, 45, 45)
StaffESPData = {}
StaffDetectedData = {}
StaffConnections = {}
StaffGlobalConnections = {}
StaffLeaving = false

StaffGroupId = 304256484
StaffMinGroupRank = 200
StaffUseGroupRank = true
StaffKeywords = {
    "staff", "admin", "administrateur", "administratrice",
    "modérateur", "moderateur", "modératrice", "moderatrice",
    "fondateur", "fondatrice", "développeur", "developpeur",
    "développeuse", "developpeuse", "dev", "support",
    "responsable", "manager", "superadmin", "owner",
    "administrator", "moderator", "developer", "founder", "tester",
    "community manager", "head admin",
}
StaffAttributeNames = {
    "Role", "RoleName", "RoleTitle", "PlayerRole",
    "StaffRole", "AdminRole", "ModeratorRole",
    "Rank", "GroupRank", "GroupRole",
    "IsStaff", "IsAdmin", "IsModerator",
    "Staff", "Admin", "Moderator",
}
StaffUserIds = {
    -- [123456789] = true,
}

StaffTitle = Instance.new("TextLabel")
StaffTitle.Visible = false
StaffTitle.Size = UDim2.new(1, 0, 0, 24)
StaffTitle.Position = UDim2.new(0, 0, 0, 725)
StaffTitle.BackgroundColor3 = Color3.fromRGB(35, 28, 38)
StaffTitle.Text = "🛡 STAFF ESP"
StaffTitle.TextColor3 = Color3.fromRGB(255, 100, 100)
StaffTitle.TextSize = 12
StaffTitle.Font = Enum.Font.GothamBold
StaffTitle.Parent = Content

StaffESPBtn = Instance.new("TextButton")
StaffESPBtn.Size = UDim2.new(0.49, 0, 0, 32)
StaffESPBtn.Position = UDim2.new(0, 0, 0, 755)
StaffESPBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
StaffESPBtn.Text="🛡️ ESP STAFF"
StaffESPBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
StaffESPBtn.TextSize = 11
StaffESPBtn.Font = Enum.Font.GothamBold
StaffESPBtn.Parent = Content

StaffAutoLeaveBtn = Instance.new("TextButton")
StaffAutoLeaveBtn.Size = UDim2.new(0.49, 0, 0, 32)
StaffAutoLeaveBtn.Position = UDim2.new(0.51, 0, 0, 755)
StaffAutoLeaveBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
StaffAutoLeaveBtn.Text = "🚪 AUTO-LEAVE : OFF"
StaffAutoLeaveBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
StaffAutoLeaveBtn.TextSize = 11
StaffAutoLeaveBtn.Font = Enum.Font.GothamBold
StaffAutoLeaveBtn.Parent = Content

StaffListTitle = Instance.new("TextLabel")
StaffListTitle.Text = "🛡 STAFF DÉTECTER"
StaffListTitle.TextColor3 = Color3.fromRGB(255, 130, 130)
StaffListTitle.TextSize = 10
StaffListTitle.Font = Enum.Font.GothamMedium
StaffListTitle.TextXAlignment = Enum.TextXAlignment.Left
StaffListTitle.Visible = false

StaffList = Instance.new("TextLabel")
StaffList.Size = UDim2.new(1, 0, 0, 90)
StaffList.Position = UDim2.new(0, 0, 0, 815)
StaffList.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
StaffList.Text = ""
StaffList.TextColor3 = StaffESPColor
StaffList.TextSize = 10
StaffList.Font = Enum.Font.GothamMedium
StaffList.TextXAlignment = Enum.TextXAlignment.Left
StaffList.TextYAlignment = Enum.TextYAlignment.Top
StaffList.TextWrapped = true
StaffList.Parent = Content

StaffHint = Instance.new("TextLabel")
StaffHint.Size = UDim2.new(1, 0, 0, 34)
StaffHint.Position = UDim2.new(0, 0, 0, 910)
StaffHint.BackgroundTransparency = 1
StaffHint.Text = ""
StaffHint.TextColor3 = Color3.fromRGB(130, 140, 155)
StaffHint.TextSize = 9
StaffHint.Font = Enum.Font.GothamMedium
StaffHint.TextWrapped = true
StaffHint.Parent = Content

function staffStr(v)
    if v == nil then return "" end
    return tostring(v)
end

function staffHasKeyword(value)
    local txt = string.lower(staffStr(value))
    for _, word in ipairs(StaffKeywords) do
        if string.find(txt, string.lower(word), 1, true) then
            return true, word
        end
    end
    return false, nil
end

function staffScanAttributes(instance)
    if not instance then return false, nil end
    for _, attributeName in ipairs(StaffAttributeNames) do
        local ok, value = pcall(function()
            return instance:GetAttribute(attributeName)
        end)
        if ok and value ~= nil then
            if value == true then
                return true, attributeName .. "=true"
            end
            local found = staffHasKeyword(value)
            if found then
                return true, attributeName .. "=" .. staffStr(value)
            end
        end
    end
    return false, nil
end

function detectStaffIntegrated(player)
    if not player or player == LocalPlayer then return false, nil end
    if StaffUserIds[player.UserId] then return true, "UserId" end

    local found, reason = staffScanAttributes(player)
    if found then return true, reason end

    if player.Team then
        found = staffHasKeyword(player.Team.Name)
        if found then return true, "Team=" .. player.Team.Name end
    end

    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        for _, child in ipairs(leaderstats:GetChildren()) do
            local value = child.Value
            found = staffHasKeyword(child.Name)
            if found then return true, "LeaderstatName=" .. child.Name end
            found = staffHasKeyword(value)
            if found then return true, child.Name .. "=" .. staffStr(value) end
        end
    end

    for _, child in ipairs(player:GetChildren()) do
        local n = string.lower(child.Name)
        if string.find(n, "role", 1, true)
            or string.find(n, "staff", 1, true)
            or string.find(n, "admin", 1, true)
            or string.find(n, "rank", 1, true) then
            local value
            pcall(function() value = child.Value end)
            found = staffHasKeyword(child.Name)
            if found then return true, "PlayerChild=" .. child.Name end
            if value ~= nil then
                found = staffHasKeyword(value)
                if found then return true, child.Name .. "=" .. staffStr(value) end
            end
        end
    end

    if StaffGroupId and StaffGroupId > 0 then
        local ok, rank, role = pcall(function()
            return player:GetRankInGroup(StaffGroupId), player:GetRoleInGroup(StaffGroupId)
        end)
        if ok then
            if role and role ~= "Guest" and role ~= "Member" then
                found = staffHasKeyword(role)
                if found then return true, "GroupRole=" .. role end
            end
            if StaffUseGroupRank and tonumber(rank) and rank >= StaffMinGroupRank then
                return true, "GroupRank=" .. tostring(rank) .. " (" .. staffStr(role) .. ")"
            end
        end
    end

    local pg = player:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, obj in ipairs(pg:GetDescendants()) do
            local n = string.lower(obj.Name)
            if string.find(n, "staff", 1, true)
                or string.find(n, "admin", 1, true)
                or string.find(n, "moder", 1, true)
                or string.find(n, "role", 1, true) then
                local textValue
                pcall(function() textValue = obj.Text end)
                if textValue and textValue ~= "" then
                    found = staffHasKeyword(textValue)
                    if found then return true, "GUI=" .. textValue end
                end
            end
        end
    end

    return false, nil
end

function destroyStaffESP(player)
    local data = StaffESPData[player]
    if not data then return end
    if data.Highlight then pcall(function() data.Highlight:Destroy() end) end
    if data.Billboard then pcall(function() data.Billboard:Destroy() end) end
    StaffESPData[player] = nil
end

function getStaffRoot(character)
    return character and (character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("Head"))
end

function createStaffESP(player, reason)
    local character = player.Character
    local root = getStaffRoot(character)
    if not root then return end
    destroyStaffESP(player)

    local highlight = Instance.new("Highlight")
    highlight.Name = "PRISONRP_StaffHighlight"
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = StaffESPColor
    highlight.FillTransparency = 0.72
    highlight.OutlineColor = StaffOutlineColor
    highlight.OutlineTransparency = 0
    highlight.Parent = character

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PRISONRP_StaffBillboard"
    billboard.Adornee = root
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 0
    billboard.Size = UDim2.new(0, 220, 0, 48)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.Parent = character

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = StaffESPColor
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Text = "🛡 STAFF\n" .. player.DisplayName .. "  @" .. player.Name .. "\n" .. staffStr(reason)
    label.Parent = billboard

    StaffESPData[player] = {Highlight = highlight, Billboard = billboard, Reason = reason}
end

StaffDisplayOrder = {}

function staffRefreshList()
    -- Keep one stable slot per player. Do not rebuild the display order from
    -- pairs() on every detection tick.
    local present = {}

    for _, entry in ipairs(StaffDisplayOrder) do
        local player = entry.player
        if player and player.Parent and StaffDetectedData[player] then
            present[player] = true
        end
    end

    -- Add newly detected staff in alphabetical order.
    local newcomers = {}
    for player, data in pairs(StaffDetectedData) do
        if player and player.Parent and data and not present[player] then
            table.insert(newcomers, player)
        end
    end

    table.sort(newcomers, function(a, b)
        return string.lower(a.Name) < string.lower(b.Name)
    end)

    for _, player in ipairs(newcomers) do
        table.insert(StaffDisplayOrder, {
            player = player
        })
    end

    -- Remove players no longer detected while preserving the order of everyone else.
    for i = #StaffDisplayOrder, 1, -1 do
        local player = StaffDisplayOrder[i].player
        if not (player and player.Parent and StaffDetectedData[player]) then
            table.remove(StaffDisplayOrder, i)
        end
    end

    local rows = {}
    for _, entry in ipairs(StaffDisplayOrder) do
        local player = entry.player
        local data = StaffDetectedData[player]
        if player and player.Parent and data then
            table.insert(rows, "🛡 @" .. player.Name .. " — " .. staffStr(data.Reason))
        end
    end

    if #rows > 0 then
        StaffList.Text = "\n\n\n\n" .. table.concat(rows, "\n")
    else
        StaffList.Text = "\n\n\n\nAucun staff détecté"
    end
    StaffListTitle.Text = "🛡 STAFF DÉTECTER"
end

function staffLeave(player, reason)
    if StaffLeaving or not StaffAutoLeaveEnabled then return end
    StaffLeaving = true
    task.delay(StaffAutoLeaveDelay, function()
        if not running then return end
        pcall(function()
            LocalPlayer:Kick("Staff détecté : " .. tostring(player.DisplayName) .. " | " .. tostring(reason))
        end)
    end)
end

function staffUpdate(player)
    if player == LocalPlayer then return end

    local staff, reason = detectStaffIntegrated(player)

    if staff then
        StaffDetectedData[player] = {Reason = reason}

        -- Affichage Staff géré par le moteur ESP intégré.
        destroyStaffESP(player)

        staffLeave(player, reason)
    else
        StaffDetectedData[player] = nil
        destroyStaffESP(player)
    end

    staffRefreshList()
end

function staffHook(player)
    if player == LocalPlayer then return end
    if StaffConnections[player] then return end
    StaffConnections[player] = {}
    table.insert(StaffConnections[player], player.CharacterAdded:Connect(function()
        task.wait(0.4)
        if running then staffUpdate(player) end
    end))
    table.insert(StaffConnections[player], player:GetPropertyChangedSignal("Team"):Connect(function()
        task.defer(function() if running then staffUpdate(player) end end)
    end))
    table.insert(StaffConnections[player], player.AttributeChanged:Connect(function()
        task.defer(function() if running then staffUpdate(player) end end)
    end))
end

function staffUnhook(player)
    if StaffConnections[player] then
        for _, c in ipairs(StaffConnections[player]) do pcall(function() c:Disconnect() end) end
        StaffConnections[player] = nil
    end
    destroyStaffESP(player)
    StaffDetectedData[player] = nil
    for i = #StaffDisplayOrder, 1, -1 do
        if StaffDisplayOrder[i].player == player then
            table.remove(StaffDisplayOrder, i)
            break
        end
    end
    staffRefreshList()
end

function stopStaffESP()
    StaffESPEnabled = false
    for player in pairs(StaffESPData) do destroyStaffESP(player) end
    staffRefreshList()
    StaffESPBtn.Text = "🛡️ ESP STAFF"
    StaffESPBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
end

if _G.PRISONRP_STAFF_ESP_STOP then
    pcall(_G.PRISONRP_STAFF_ESP_STOP)
end
_G.PRISONRP_STAFF_ESP_STOP = stopStaffESP

for _, player in ipairs(Players:GetPlayers()) do staffHook(player) end
StaffGlobalConnections = {
    Players.PlayerAdded:Connect(staffHook),
    Players.PlayerRemoving:Connect(staffUnhook),
}
_G.PRISONRP_STAFF_GLOBAL_CLEANUP = function()
    for _, connection in ipairs(StaffGlobalConnections) do
        pcall(function() connection:Disconnect() end)
    end
    StaffGlobalConnections = {}
    for player in pairs(StaffConnections) do
        pcall(function() staffUnhook(player) end)
    end
    for player in pairs(StaffESPData) do
        pcall(function() destroyStaffESP(player) end)
    end
    StaffDetectedData = {}
    StaffDisplayOrder = {}
end

StaffAutoLeaveBtn.MouseButton1Click:Connect(function()
    StaffAutoLeaveEnabled = not StaffAutoLeaveEnabled
    StaffAutoLeaveBtn.Text = StaffAutoLeaveEnabled and "🚪 AUTO-LEAVE : ON" or "🚪 AUTO-LEAVE : OFF"
    StaffAutoLeaveBtn.BackgroundColor3 = StaffAutoLeaveEnabled
        and Color3.fromRGB(150, 45, 55)
        or Color3.fromRGB(45, 48, 62)
end)

task.spawn(function()
    while running and ScreenGui and ScreenGui.Parent do
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then task.spawn(staffUpdate, player) end
        end
        staffRefreshList()
        task.wait(1)
    end
end)


-- Couleurs du bouton "Pêcher à partir de :" selon la rareté sélectionnée
local function getRarityButtonColor(rarity)
    local r = string.lower(tostring(rarity or ""))

    if r == "common" then
        return Color3.fromRGB(135, 135, 135) -- gris plus clair
    elseif r == "uncommon" then
        return Color3.fromRGB(30, 145, 55) -- vert plus foncé
    elseif r == "rare" then
        return Color3.fromRGB(55, 125, 235) -- bleu
    elseif r == "epic" then
        return Color3.fromRGB(155, 75, 220) -- violet
    elseif r == "legendary" then
        return Color3.fromRGB(255, 180, 80) -- orange clair
    elseif r == "unknown" then
        return Color3.fromRGB(70, 190, 205) -- cyan
    elseif r == "mythical" then
        return Color3.fromRGB(235, 85, 150) -- rose
    elseif r == "secret" then
        return Color3.fromRGB(245, 215, 85) -- or
    end

    return Color3.fromRGB(50, 40, 90)
end

function updateUI()
    StatusLabel.Text = "Status: " .. stats.status
    StatsLabel.Text = string.format("Caught: %d | Perfect: %d", stats.totalCaught, stats.perfectCount)
    LastFishLabel.Text = "Last Fish: " .. stats.lastFish
    local selectedRarity = RarityList[_G.MinRarityIndex]
    RarityBtn.Text = "Pêcher à partir de : " .. selectedRarity
    RarityBtn.BackgroundColor3 = getRarityButtonColor(selectedRarity)
    RarityBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

    -- V213 : les intitulés restent stables ; l'interrupteur animé montre l'état ON/OFF.
    ToggleFishBtn.Text = "🎣 AUTO-FISH"
    ToggleFishBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 50)
    ToggleFishBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

    AutoSellBtn.Text = "💰 AUTO-SELL"
    AutoSellBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 50)
    AutoSellBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

    ESPToggleBtn.Text = "👁️ ESP BLACK MARKET"
    ESPToggleBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 50)
    ESPToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
end

-- V205 : les fonctions AUTO POMPES sont définies une seule fois plus haut.

function updateAutoPushupUI()
    if _G.AutoPushupEnabled then
        AutoPushupBtn.Text = "💪 AUTO POMPES : ON"
        AutoPushupBtn.BackgroundColor3 = Color3.fromRGB(40, 145, 75)
        AutoPushupBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    else
        AutoPushupBtn.Text = "💪 AUTO POMPES : OFF"
        AutoPushupBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
        AutoPushupBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    end
end



function startAutoPushup()
    if _G.AutoPushupEnabled then
        return
    end

    _G.AutoPushupEnabled = true
    updateAutoPushupUI()

    -- Même activation que dans la version standalone fonctionnelle.
    activatePompes()

    AutoPushupWorker = task.spawn(function()
        while _G.AutoPushupEnabled do
            local pushups, zone, needle = getTrackObjects()

            if pushups and pushups.Visible and zone and needle then
                if needleIsInsidePushupZone(zone, needle) then
                    pressPushupSpace()
                end
            end

            task.wait(PUSHUP_CHECK_INTERVAL)
        end
    end)
end

function stopAutoPushup()
    _G.AutoPushupEnabled = false

    if AutoPushupWorker then
        task.cancel(AutoPushupWorker)
        AutoPushupWorker = nil
    end

    updateAutoPushupUI()
end

AutoPushupBtn.MouseButton1Click:Connect(function()
    if _G.AutoPushupEnabled then
        stopAutoPushup()
    else
        startAutoPushup()
    end
end)

-- Gestion ESP Black Market
function applyESP(targetModel)
    if not targetModel then return end
    
    local existingHL = targetModel:FindFirstChild("BM_ESP_Highlight")
    local existingBB = targetModel:FindFirstChild("BM_ESP_Text")
    
    if _G.BlackMarketESP then
        if not existingHL then
            local hl = Instance.new("Highlight")
            hl.Name = "BM_ESP_Highlight"
            hl.FillColor = Color3.fromRGB(180, 0, 255)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.4
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = targetModel
        end
        
        if not existingBB then
            local hrp = targetModel:FindFirstChild("HumanoidRootPart") or targetModel.PrimaryPart
            if hrp then
                local bb = Instance.new("BillboardGui")
                bb.Name = "BM_ESP_Text"
                bb.Adornee = hrp
                bb.Size = UDim2.new(0, 150, 0, 30)
                bb.StudsOffset = Vector3.new(0, 3.5, 0)
                bb.AlwaysOnTop = true
                
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text = "🛒 BLACK MARKET"
                lbl.TextColor3 = Color3.fromRGB(220, 130, 255)
                lbl.TextStrokeTransparency = 0
                lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 13
                lbl.Parent = bb
                
                bb.Parent = targetModel
            end
        end
    else
        if existingHL then existingHL:Destroy() end
        if existingBB then existingBB:Destroy() end
    end
end

function toggleBlackMarketESP()
    local success, bmModel = pcall(function()
        return workspace.Entities["Black Market"]["Black Market"]
    end)
    if success and bmModel then
        applyESP(bmModel)
    end
end

ESPToggleBtn.MouseButton1Click:Connect(function()
    _G.BlackMarketESP = not _G.BlackMarketESP
    toggleBlackMarketESP()
    updateUI()

        ESPToggleBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 50)
    end)

-- Recherche élargie des items
function findItemAnywhere(targetNames)
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    -- On ne recherche que de vrais Tools : la recherche "large" dans les
    -- instances sans parent pouvait confondre un objet d'interface nommé
    -- par exemple "OmegaSidebar" avec "Bar" (car "sidebar" contient "bar").
    local function isConsumableTool(obj)
        return obj and obj:IsA("Tool")
    end

    for _, name in ipairs(targetNames) do
        local charItem = char and char:FindFirstChild(name)
        if isConsumableTool(charItem) then
            return charItem
        end

        local backpackItem = backpack and backpack:FindFirstChild(name)
        if isConsumableTool(backpackItem) then
            return backpackItem
        end
    end

    -- Fallback facultatif : uniquement les Tools réellement retrouvés sans
    -- parent. On ne touche jamais aux Frames/TextButtons/etc.
    local get_nil = getnilinstances or (debug and debug.getnilinstances)
    if get_nil then
        for _, obj in ipairs(get_nil()) do
            if isConsumableTool(obj) then
                local objName = string.lower(obj.Name or "")
                for _, name in ipairs(targetNames) do
                    local wanted = string.lower(tostring(name))
                    if objName == wanted then
                        return obj
                    end
                end
            end
        end
    end

    return nil
end

function forceConsumeFull(actionType, possibleNames)
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    if not char or not humanoid then return false end

    local item = findItemAnywhere(possibleNames)
    if not item then return false end

    if not item:IsA("Tool") then
        return false
    end

    if item.Parent ~= char then
        if backpack and item.Parent ~= backpack then
            local moved = pcall(function()
                item.Parent = backpack
            end)
            if not moved or item.Parent ~= backpack then
                return false
            end
            task.wait(0.1)
        end

        local equipped = pcall(function()
            humanoid:EquipTool(item)
        end)
        if not equipped then
            return false
        end
        task.wait(0.4)
    end

    for bite = 1, 3 do
        if not item or not item.Parent then break end

        if item.Parent ~= char then
            humanoid:EquipTool(item)
            task.wait(0.3)
        end

        if ToolEvent then
            pcall(function() ToolEvent:FireServer(actionType, item) end)
        end

        task.wait(2.8)
    end

    task.wait(0.3)
    if humanoid then 
        humanoid:UnequipTools() 
    end

    return true
end

-- Cycle séquentiel : Manger d'abord (barre entière), puis Boire ensuite (soda entier)
function eatThenDrinkCycle()
    forceConsumeFull("Eat", {"CerealBar", "Barre de céréale", "Pain", "Bread", "Food", "Bar"})
    task.wait(0.5)
    forceConsumeFull("Drink", {"Boîte de soda", "Soda", "Water", "Eau", "Bottle", "Drink"})
end

-- Pêche
function ensureRodEquipped()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = char:WaitForChild("Humanoid")
    if char:FindFirstChild("FishingRod") then return true end

    local rodInBackpack = LocalPlayer.Backpack:FindFirstChild("FishingRod")
    if rodInBackpack then
        humanoid:EquipTool(rodInBackpack)
        task.wait(0.3)
        return true
    end
    return false
end

function resetRod()
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChild("Humanoid")
        local rod = char:FindFirstChild("FishingRod")
        if humanoid and rod then
            humanoid:UnequipTools()
            task.wait(0.2)
            humanoid:EquipTool(rod)
            task.wait(0.2)
        end
    end
end

function getActiveRodFunctions()
    if not get_gc then return nil, nil, nil end
    local onActionBeganFunc, onActionEndedFunc, performCastFunc
    for _, obj in ipairs(get_gc(false)) do
        if typeof(obj) == "function" and islclosure(obj) then
            local info = debug.getinfo(obj)
            if info.name == "OnActionBegan" then onActionBeganFunc = obj
            elseif info.name == "OnActionEnded" then onActionEndedFunc = obj
            elseif info.name == "PerformCast" then performCastFunc = obj end
        end
    end
    return onActionBeganFunc, onActionEndedFunc, performCastFunc
end

function getRarityIndex(rarityName)
    if rarityName == nil then return #RarityList end

    -- Normalise la valeur afin que les différences de casse, d'espaces,
    -- de tirets ou de préfixes/suffixes ne fassent pas classer un poisson rare
    -- comme Common par erreur.
    local rarity = string.lower(tostring(rarityName))
    rarity = string.gsub(rarity, "^%s+", "")
    rarity = string.gsub(rarity, "%s+$", "")
    rarity = string.gsub(rarity, "[_%-]", "")

    -- Comparaison d'abord par les raretés les plus spécifiques.
    if string.find(rarity, "secret", 1, true) then return 8 end
    if string.find(rarity, "mythical", 1, true) or string.find(rarity, "mythic", 1, true) or string.find(rarity, "mythique", 1, true) then return 7 end
    if string.find(rarity, "unknown", 1, true) or string.find(rarity, "inconnu", 1, true) then return 6 end
    if string.find(rarity, "legendary", 1, true) or string.find(rarity, "legendaire", 1, true) or string.find(rarity, "légendaire", 1, true) then return 5 end
    if string.find(rarity, "epic", 1, true) or string.find(rarity, "épique", 1, true) or string.find(rarity, "epique", 1, true) then return 4 end
    if string.find(rarity, "uncommon", 1, true) or string.find(rarity, "inhabituel", 1, true) then return 2 end
    if string.find(rarity, "common", 1, true) or string.find(rarity, "commun", 1, true) then return 1 end
    if string.find(rarity, "rare", 1, true) then return 3 end

    -- Dernier recours : ne pas rejeter une nouvelle rareté inconnue en la
    -- considérant à tort comme Common. Cela la traite comme une rareté élevée.
    return #RarityList
end

-- Logique d'achat à distance
isBuying = false
buyRequest = false
totalToBuy = 30
cooldown = 1.0
originalCFrame = nil
originalVelocity = nil
originalAngularVelocity = nil

-- Auto Buy Food : nouvelle approche par interaction du déclencheur.
-- Priorité : ProximityPrompt (si présent) -> RemoteEvent.
-- Aucun déplacement du personnage n'est effectué par cette version.
isBuying = false
buyRequest = false
totalToBuy = 30
cooldown = 1.0
originalCFrame = nil
local remoteBuyBusy = false
-- V210 : invalide explicitement les anciennes boucles lors d'un stop/restart rapide.
remoteBuyRunToken = tonumber(remoteBuyRunToken) or 0

local function findPurchasePrompt(kind)
    if not vendingMachine then return nil end
    local wanted = string.lower(kind)

    local candidates = {}
    for _, obj in ipairs(vendingMachine:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local n = string.lower(obj.Name)
            local pn = obj.Parent and string.lower(obj.Parent.Name) or ""
            if string.find(n, wanted, 1, true) or string.find(pn, wanted, 1, true) then
                table.insert(candidates, obj)
            end
        end
    end

    if #candidates > 0 then
        return candidates[1]
    end
    return nil
end

local function getVendingTargetCFrame()
    if not vendingMachine then return nil end
    local ok, cf = pcall(function()
        local primary = vendingMachine.PrimaryPart
        if primary then
            return primary.CFrame
        end
        return vendingMachine:GetPivot()
    end)
    if ok then return cf end
    return nil
end

local function fireRemoteDirect(remote)
    if not remote or not remote:IsA("RemoteEvent") then
        return false
    end
    local ok = pcall(function()
        remote:FireServer()
    end)
    return ok
end

local function createVisualPresence(char, savedCFrame)
    if not char or not savedCFrame then return nil end

    local oldArchivable = char.Archivable
    local clone = nil

    pcall(function()
        char.Archivable = true
        clone = char:Clone()
        char.Archivable = oldArchivable
    end)

    if not clone then
        pcall(function() char.Archivable = oldArchivable end)
        return nil
    end

    clone.Name = "PRISONRP_AutoBuyVisualPresence"

    for _, obj in ipairs(clone:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.Anchored = true
            obj.CanCollide = false
            obj.CanTouch = false
            obj.CanQuery = false
            obj.CastShadow = false
        elseif obj:IsA("Script") or obj:IsA("LocalScript") then
            obj.Disabled = true
        elseif obj:IsA("Humanoid") then
            pcall(function() obj.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
        end
    end

    local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
    if cloneRoot then
        clone:PivotTo(savedCFrame)
    else
        clone:PivotTo(savedCFrame)
    end

    clone.Parent = workspace
    return clone
end

local function setRealCharacterInvisibleLocal(char, enabled)
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            pcall(function() obj.LocalTransparencyModifier = enabled and 1 or 0 end)
        end
    end
end

local function firePurchaseAtVending(kind, remote, runToken)
    if runToken ~= nil and (not buyRequest or runToken ~= remoteBuyRunToken) then
        return false, "stopped"
    end
    -- AUTO BUY TP : le personnage est déjà placé devant le distributeur
    -- pendant toute la session d'achat. Le retour à la position d'activation
    -- est effectué uniquement lorsque l'utilisateur désactive l'Auto Buy.
    if not remote or not remote:IsA("RemoteEvent") then
        return false, "none"
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return false, "none"
    end

    local target = getVendingTargetCFrame()
    if not target then
        return false, "none"
    end

    -- Si le personnage a été déplacé manuellement pendant l'Auto Buy,
    -- on le remet près du distributeur avant l'achat.
    local distance = (hrp.Position - (target.Position)).Magnitude
    if distance > 7 then
        pcall(function()
            hrp.CFrame = target * CFrame.new(0, 0, -3)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
        RunService.Heartbeat:Wait()
        -- L'arrêt peut survenir pendant le Heartbeat: ne pas envoyer la requête ensuite.
        if runToken ~= nil and (not buyRequest or runToken ~= remoteBuyRunToken) then
            return false, "stopped"
        end
    end

    -- Food et Drink passent tous les deux par leur RemoteEvent dédié.
    -- On évite de considérer un ProximityPrompt comme un achat réussi :
    -- dans PRISON RP il peut exister un prompt qui ne déclenche pas le paiement.
    local ok = pcall(function()
        remote:FireServer()
    end)

    return ok, ok and "tp-buy" or "none"
end

function stopRemoteBuy()
    -- Le token empêche une boucle ancienne de repartir si Auto Buy est réactivé vite.
    remoteBuyRunToken = (tonumber(remoteBuyRunToken) or 0) + 1
    buyRequest = false
    isBuying = false

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and originalCFrame then
        pcall(function()
            hrp.CFrame = originalCFrame
            hrp.AssemblyLinearVelocity = originalVelocity or Vector3.zero
            hrp.AssemblyAngularVelocity = originalAngularVelocity or Vector3.zero
        end)
    end

    originalCFrame = nil
    originalVelocity = nil
    originalAngularVelocity = nil

    if StartBtn then
        StartBtn.Text = "🛒 Auto Buy Food"
        StartBtn.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
    end
end

function startRemoteBuy()
    if isBuying or not running then return end
    if not foodEvent or not drinkEvent then
        if FoodText then FoodText.Text = "🥖 Achat : événement nourriture introuvable" end
        if DrinkText then DrinkText.Text = "🥤 Achat : événement boisson introuvable" end
        return
    end
    if not vendingMachine then
        if FoodText then FoodText.Text = "🥖 Achat : distributeur introuvable" end
        if DrinkText then DrinkText.Text = "🥤 Achat : distributeur introuvable" end
        return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    local vendorTarget = getVendingTargetCFrame()
    if not vendorTarget then
        if FoodText then FoodText.Text = "🥖 Achat : position du distributeur introuvable" end
        if DrinkText then DrinkText.Text = "🥤 Achat : position du distributeur introuvable" end
        return
    end

    -- Position exacte à laquelle l'utilisateur a activé l'Auto Buy.
    originalCFrame = hrp.CFrame
    originalVelocity = hrp.AssemblyLinearVelocity
    originalAngularVelocity = hrp.AssemblyAngularVelocity
    remoteBuyRunToken = (tonumber(remoteBuyRunToken) or 0) + 1
    local thisRunToken = remoteBuyRunToken
    -- Bloque les clics doubles pendant le petit Heartbeat de stabilisation.
    isBuying = true

    -- TP une fois au distributeur et reste sur place pendant les achats.
    local moved = pcall(function()
        hrp.CFrame = vendorTarget * CFrame.new(0, 0, -3)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)

    if not moved then
        if thisRunToken == remoteBuyRunToken then
            originalCFrame = nil
            originalVelocity = nil
            originalAngularVelocity = nil
            isBuying = false
            buyRequest = false
            remoteBuyRunToken += 1
        end
        return
    end

    RunService.Heartbeat:Wait()
    if thisRunToken ~= remoteBuyRunToken or not running then
        -- Si le token est toujours le même, il faut restaurer l'état de départ.
        if thisRunToken == remoteBuyRunToken then
            stopRemoteBuy()
        end
        return
    end

    buyRequest = true

    if StartBtn then
        StartBtn.Text = "🛒 Auto Buy Food : ON"
        StartBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
    end

    -- Deux boucles indépendantes : Food et Drink ont chacune leur propre
    -- cooldown de 1 seconde, mais démarrent en même temps.
    task.spawn(function()
        local i = 0
        while buyRequest and thisRunToken == remoteBuyRunToken do
            i += 1
            while AutoEatDrinkBusy and buyRequest and thisRunToken == remoteBuyRunToken do task.wait(0.1) end
            if not buyRequest or thisRunToken ~= remoteBuyRunToken then break end

            local foodOk = firePurchaseAtVending("food", foodEvent, thisRunToken)
            if FoodText then
                FoodText.Text = foodOk
                    and string.format("🥖 Nourriture : %d", i)
                    or string.format("🥖 Échec achat : %d", i)
            end

            task.wait(cooldown)
        end
    end)

    task.spawn(function()
        local i = 0
        while buyRequest and thisRunToken == remoteBuyRunToken do
            i += 1
            while AutoEatDrinkBusy and buyRequest and thisRunToken == remoteBuyRunToken do task.wait(0.1) end
            if not buyRequest or thisRunToken ~= remoteBuyRunToken then break end

            local drinkOk = firePurchaseAtVending("drink", drinkEvent, thisRunToken)
            if DrinkText then
                DrinkText.Text = drinkOk
                    and string.format("🥤 Boisson : %d", i)
                    or string.format("🥤 Échec achat : %d", i)
            end

            task.wait(cooldown)
        end
    end)

    -- Le bouton reste ON jusqu'à désactivation manuelle.
    task.spawn(function()
        while buyRequest and thisRunToken == remoteBuyRunToken do
            task.wait(0.25)
        end
        -- Une ancienne tâche ne doit pas réinitialiser l'interface d'une nouvelle session.
        if thisRunToken == remoteBuyRunToken then
            isBuying = false
            if StartBtn then
                StartBtn.Text = "🛒 Auto Buy Food"
                StartBtn.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
            end
        end
    end)
end

StartBtn.Text = "🛒 Auto Buy Food"
StartBtn.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
StartBtn.MouseButton1Click:Connect(function()
    if isBuying then
        stopRemoteBuy()
    else
        startRemoteBuy()
    end
end)

-- V193 : TP direct par CFrame.
-- Aucun déplacement progressif, aucun scanner, aucun diagnostic console.
MoveToTargetToken = 0

function stopMoveToTarget()
    MoveToTargetToken += 1

    local char = LocalPlayer and LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

-- Correctif TP conservé : TP instantané par CFrame direct.
-- Aucun déplacement intermédiaire, aucune vitesse forcée, aucun Heartbeat.
function directTeleportTo(targetCFrame)
    if typeof(targetCFrame) ~= "CFrame" then
        return false
    end

    -- Stoppe uniquement un éventuel ancien déplacement du système TP.
    stopMoveToTarget()

    local char = LocalPlayer and LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not root then
        return false
    end

    local ok = pcall(function()
        root.CFrame = targetCFrame
    end)

    return ok
end

-- TP Black Market : position devant le vendeur.
BlackMarketBtn.MouseButton1Click:Connect(function()
    local bmPart
    local ok = pcall(function()
        local entities = workspace:FindFirstChild("Entities")
        local bmFolder = entities and entities:FindFirstChild("Black Market")
        local bmModel = bmFolder and bmFolder:FindFirstChild("Black Market")
        bmPart = bmModel and (
            bmModel:FindFirstChild("HumanoidRootPart")
            or bmModel.PrimaryPart
            or bmModel:FindFirstChildWhichIsA("BasePart", true)
        )
    end)

    if not ok or not bmPart then
        return
    end

    local frontPos = bmPart.Position + (bmPart.CFrame.LookVector * 3) + Vector3.new(0, 2, 0)
    local target = CFrame.lookAt(frontPos, bmPart.Position + Vector3.new(0, 1, 0))

    if directTeleportTo(target) then
        BlackMarketBtn.Text = "🏃 BLACK MARKET"
    end
end)

-- ============================================================
-- AUTO EAT / DRINK : seuil 50 + pause/reprise de toutes les tâches
-- ============================================================
FOOD_NAMES = {
    "Food", "Hunger", "HungerLevel", "FoodLevel",
    "Nutrition", "Calories", "HungerValue"
}

WATER_NAMES = {
    "Water", "Thirst", "ThirstLevel", "WaterLevel",
    "Hydration", "ThirstValue"
}

function getNamedNeedValue(root, names)
    if not root then return nil end

    for _, name in ipairs(names) do
        local ok, value = pcall(function() return root:GetAttribute(name) end)
        if ok and typeof(value) == "number" then return value end
    end

    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("NumberValue") or obj:IsA("IntValue") then
            local objName = obj.Name:lower()
            for _, name in ipairs(names) do
                if objName == name:lower() then return obj.Value end
            end
        end
    end
    return nil
end

function readNeedValues()
    local char = LocalPlayer.Character
    local food = getNamedNeedValue(LocalPlayer, FOOD_NAMES)
    local water = getNamedNeedValue(LocalPlayer, WATER_NAMES)
    if food == nil then food = getNamedNeedValue(char, FOOD_NAMES) end
    if water == nil then water = getNamedNeedValue(char, WATER_NAMES) end
    return food, water
end

function updateAutoEatDrinkUI()
    -- V213 : même libellé/couleur dans les deux états ; le switch vert/gris fait foi.
    AutoEatDrinkBtn.Text = "🍔 AUTO EAT / DRINK (" .. tostring(AUTO_EAT_DRINK_THRESHOLD) .. ")"
    AutoEatDrinkBtn.BackgroundColor3 = Color3.fromRGB(31, 38, 48)
    AutoEatDrinkBtn.TextColor3 = Color3.fromRGB(236, 240, 248)
end

AutoEatDrinkWasMineActive = false

function pauseAllForConsumption()
    AutoEatDrinkBusy = true

    AutoEatDrinkWasPushupActive = _G.AutoPushupEnabled == true
    if AutoEatDrinkWasPushupActive then stopAutoPushup() end

    -- Même principe pour l'Auto Mine : on arrête temporairement,
    -- puis on le relance automatiquement après avoir mangé/bu.
    AutoEatDrinkWasMineActive = AutoMineRunning == true
    if AutoEatDrinkWasMineActive then autoMineStop() end

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then pcall(function() humanoid:UnequipTools() end) end

    stats.status = "Pause : Nourriture / Boisson..."
    updateUI()
    task.wait(0.5)
end

function resumeAllAfterConsumption()
    AutoEatDrinkBusy = false

    if AutoEatDrinkWasPushupActive then
        AutoEatDrinkWasPushupActive = false
        if not _G.AutoPushupEnabled then startAutoPushup() end
    end

    if AutoEatDrinkWasMineActive then
        AutoEatDrinkWasMineActive = false
        if not AutoMineRunning then autoMineStart() end
    end

    if _G.AutoFishingEnabled then
        stats.status = "Reprise de l'Auto-Pêche..."
        updateUI()
        ensureRodEquipped()
        task.wait(0.5)
    else
        stats.status = "Prêt"
        updateUI()
    end
end

function runAutoEatDrink(food, water)
    if AutoEatDrinkBusy or not AutoEatDrinkEnabled then return end

    local needEat = food ~= nil and food <= AUTO_EAT_DRINK_THRESHOLD
    local needDrink = water ~= nil and water <= AUTO_EAT_DRINK_THRESHOLD
    if not needEat and not needDrink then return end

    pauseAllForConsumption()

    if needEat and AutoEatDrinkEnabled then
        stats.status = "🍔 Nourriture ≤ 50 : je mange..."
        updateUI()
        forceConsumeFull("Eat", {"CerealBar", "Barre de céréale", "Pain", "Bread", "Food", "Bar"})
        task.wait(0.5)
    end

    if needDrink and AutoEatDrinkEnabled then
        stats.status = "🥤 Eau ≤ 50 : je bois..."
        updateUI()
        forceConsumeFull("Drink", {"Boîte de soda", "Soda", "Water", "Eau", "Bottle", "Drink"})
        task.wait(0.5)
    end

    resumeAllAfterConsumption()
end

AutoEatDrinkBtn.MouseButton1Click:Connect(function()
    AutoEatDrinkEnabled = not AutoEatDrinkEnabled
    _G.AutoEatDrinkEnabled = AutoEatDrinkEnabled
    updateAutoEatDrinkUI()
    stats.status = AutoEatDrinkEnabled and "Auto Eat / Drink : ON (seuil 50)" or (_G.AutoFishingEnabled and "Running..." or "Stopped")
    updateUI()
end)

RarityBtn.MouseButton1Click:Connect(function()
    _G.MinRarityIndex = (_G.MinRarityIndex % #RarityList) + 1
    updateUI()
end)



TeleportBtn.MouseButton1Click:Connect(function()
    if directTeleportTo(POND_GROUND_CFRAME) then
        TeleportBtn.Text = "🏃 SHORE"
    end
end)


SellNowBtn.MouseButton1Click:Connect(function()
    if Inventory_SellAll then
        pcall(function() Inventory_SellAll:InvokeServer() end)
        stats.status = "Sold All Fish!"
        updateUI()
    end
end)

AutoSellBtn.MouseButton1Click:Connect(function()
    _G.AutoSellEnabled = not _G.AutoSellEnabled
    updateUI()
end)

ToggleFishBtn.MouseButton1Click:Connect(function()
    _G.AutoFishingEnabled = not _G.AutoFishingEnabled
    stats.status = _G.AutoFishingEnabled and "Running..." or "Stopped"
    updateUI()
end)

task.spawn(function()
    local TweenService = game:GetService("TweenService")
    local lastFoodValue = nil
    local lastWaterValue = nil

    while AutoEatDrinkThreadRunning and running and ScreenGui and ScreenGui.Parent do
        task.wait(AUTO_EAT_DRINK_CHECK_INTERVAL)

        local food, water = readNeedValues()

        -- Les cases sont créées une seule fois dans la mise en page FARM.
        -- Ici on ne fait que mettre à jour leur texte et leur remplissage.
        local function updateNeedBar(fill, value, lastValue)
            if not fill then return end

            local numericValue = tonumber(value)
            if numericValue == nil then return end

            -- Les besoins du jeu sont lus sur une base 0-100.
            local ratio = math.clamp(numericValue / 100, 0, 1)

            if lastValue == nil or math.abs(numericValue - lastValue) > 0.001 then
                local tween = TweenService:Create(
                    fill,
                    TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    {Size = UDim2.new(ratio, 0, 1, 0)}
                )
                tween:Play()
            else
                fill.Size = UDim2.new(ratio, 0, 1, 0)
            end
        end

        if FoodText then
            FoodText.Text = food ~= nil
                and string.format("🥖 Nourriture : %d / 100", math.floor(food + 0.5))
                or "🥖 Nourriture : ? / 100"
        end

        if DrinkText then
            DrinkText.Text = water ~= nil
                and string.format("🥤 Boisson : %d / 100", math.floor(water + 0.5))
                or "🥤 Boisson : ? / 100"
        end

        updateNeedBar(FoodFill, food, lastFoodValue)
        updateNeedBar(DrinkFill, water, lastWaterValue)

        lastFoodValue = tonumber(food) or lastFoodValue
        lastWaterValue = tonumber(water) or lastWaterValue

        if AutoEatDrinkEnabled and not AutoEatDrinkBusy then
            if (food ~= nil and food <= AUTO_EAT_DRINK_THRESHOLD) or (water ~= nil and water <= AUTO_EAT_DRINK_THRESHOLD) then
                task.spawn(runAutoEatDrink, food, water)
            end
        end
    end
end)

-- Page actuellement sélectionnée : utilisée aussi par le système de restauration après réduction.
v7Selected = 1
HubExpanded = true
-- Taille normale définitive de la nouvelle interface.
HubFullSize = UDim2.new(0, 500, 0, 620)
MainFrame.Size = HubFullSize

-- V198 : reduction ancree exactement au point clique, puis restauration a la position d'origine.
-- Les corrections successives compensent les variations de layout/UIScale apres chaque resize.
local HubExpandedPosition = MainFrame.Position
local HubMinimizedPosition = nil
local MinimizeCursorLockToken = 0
local function keepMinimizeClickPointUnderCursor(mousePosition, clickOffset)
    MinimizeCursorLockToken += 1
    local token = MinimizeCursorLockToken
    task.spawn(function()
        -- Laisser Roblox recalculer le layout apres le changement de taille.
        RunService.Heartbeat:Wait()
        RunService.Heartbeat:Wait()
        for _ = 1, 6 do
            if token ~= MinimizeCursorLockToken or HubExpanded then return end
            if not MainFrame or not MainFrame.Parent or not CloseBtn or not CloseBtn.Parent then return end

            local buttonPosition = CloseBtn.AbsolutePosition
            local currentClickPoint = Vector2.new(
                buttonPosition.X + clickOffset.X,
                buttonPosition.Y + clickOffset.Y
            )
            local dx = mousePosition.X - currentClickPoint.X
            local dy = mousePosition.Y - currentClickPoint.Y
            if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then break end

            -- Offset en boucle fermee : si UIScale/layout absorbe une partie du deplacement,
            -- la passe suivante corrige le residu au lieu de laisser un decalage visible.
            local position = MainFrame.Position
            MainFrame.Position = UDim2.new(
                position.X.Scale, position.X.Offset + dx,
                position.Y.Scale, position.Y.Offset + dy
            )
            RunService.Heartbeat:Wait()
        end

        if token == MinimizeCursorLockToken and not HubExpanded then
            HubMinimizedPosition = MainFrame.Position
        end
    end)
end

CloseBtn.Text = "−"
CloseBtn.MouseButton1Click:Connect(function()
    local mousePosition = MovementUserInputService:GetMouseLocation()
    local buttonPositionBefore = CloseBtn.AbsolutePosition
    local clickOffset = Vector2.new(
        mousePosition.X - buttonPositionBefore.X,
        mousePosition.Y - buttonPositionBefore.Y
    )

    local v7BodyRef = MainFrame:FindFirstChild("V7Body")
    local v7SidebarRef = v7BodyRef and v7BodyRef:FindFirstChild("V7Sidebar")

    if HubExpanded then
        -- Sauvegarder la position exacte de l'interface ouverte avant de la reduire.
        HubExpandedPosition = MainFrame.Position
        HubExpanded = false
        CloseBtn.Text = "+"
        MainFrame.Size = UDim2.fromOffset(320, 44)

        -- V218 : cacher les textes secondaires en mode réduit pour éviter les chevauchements.
        -- Le titre principal reste visible ; le rappel Right Shift et le compteur de joueurs reviendront à l'ouverture.
        if RightShiftLabel and RightShiftLabel.Parent then
            RightShiftLabel.Visible = false
        end
        local minimizedTitleBar = MainFrame:FindFirstChild("TitleBar")
        local minimizedStatusPill = minimizedTitleBar and minimizedTitleBar:FindFirstChild("PRISONRP_HeaderStatus")
        if minimizedStatusPill then
            minimizedStatusPill.Visible = false
        end

        -- Mode reduit : masquer le corps; la barre de titre reste sous le curseur.
        if v7BodyRef then v7BodyRef.Visible = false end
        if Content then Content.Visible = false end
        if movementPage then movementPage.Visible = false end
        if espPage then espPage.Visible = false end
        if autresPage then autresPage.Visible = false end

        keepMinimizeClickPointUnderCursor(mousePosition, clickOffset)
    else
        -- Si la barre reduite a ete deplacee, appliquer son deplacement a la position
        -- restauree. Sans deplacement manuel, on revient exactement a la position initiale.
        local dragX, dragY = 0, 0
        if HubMinimizedPosition then
            local currentPosition = MainFrame.Position
            dragX = currentPosition.X.Offset - HubMinimizedPosition.X.Offset
            dragY = currentPosition.Y.Offset - HubMinimizedPosition.Y.Offset
        end
        HubExpandedPosition = UDim2.new(
            HubExpandedPosition.X.Scale, HubExpandedPosition.X.Offset + dragX,
            HubExpandedPosition.Y.Scale, HubExpandedPosition.Y.Offset + dragY
        )
        HubMinimizedPosition = nil

        HubExpanded = true
        CloseBtn.Text = "−"
        MainFrame.Size = HubFullSize
        MainFrame.Position = HubExpandedPosition

        -- V218 : restaurer les textes et le compteur uniquement lorsque le panneau est réouvert.
        if RightShiftLabel and RightShiftLabel.Parent then
            RightShiftLabel.Visible = true
        end
        local restoredTitleBar = MainFrame:FindFirstChild("TitleBar")
        local restoredStatusPill = restoredTitleBar and restoredTitleBar:FindFirstChild("PRISONRP_HeaderStatus")
        if restoredStatusPill then
            restoredStatusPill.Visible = true
        end

        if v7BodyRef then
            v7BodyRef.Visible = true
            -- Le contenu commence sous la barre de titre, quelle que soit la restauration.
            v7BodyRef.Position = UDim2.fromOffset(0, 52)
            v7BodyRef.Size = UDim2.new(1, 0, 1, -52)
        end

        -- Recalculer les pages apres que Roblox a applique la taille finale.
        task.defer(function()
            RunService.Heartbeat:Wait()
            RunService.Heartbeat:Wait()
            if not HubExpanded or not v7BodyRef or not v7BodyRef.Parent then return end

            local scale = math.max((MainFrameScale and MainFrameScale.Scale) or 1, 0.01)
            local bodyW = v7BodyRef.AbsoluteSize.X / scale
            local bodyH = v7BodyRef.AbsoluteSize.Y / scale
            if bodyW <= 0 or bodyH <= 0 then return end
            local sidebarOpen = v7SidebarRef and v7SidebarRef.Size.X.Offset >= 100
            local x = sidebarOpen and 155 or 57
            local width = math.max(100, bodyW - x - 10)
            local height = math.max(100, bodyH - 16)

            if v7SidebarRef then
                v7SidebarRef.Position = UDim2.fromOffset(8, 8)
                v7SidebarRef.Size = UDim2.fromOffset(sidebarOpen and 142 or 43, height)
            end

            local pages = {Content, movementPage, espPage, autresPage}
            for _, page in ipairs(pages) do
                if page then
                    page.Position = UDim2.fromOffset(x, 8)
                    page.Size = UDim2.fromOffset(width, height)
                    page.ZIndex = 91
                end
            end
            local activePage = tonumber(_G.PRISONRP_ACTIVE_UI_PAGE) or tonumber(v7Selected) or 1
            if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
                pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, activePage)
            else
                for i, page in ipairs(pages) do
                    if page then page.Visible = (i == activePage) end
                end
            end
        end)
    end
end)

--==============================================================
-- UNLOAD : confirmation obligatoire avant de désactiver le hub.
--==============================================================
UnloadConfirmOpen = false
UnloadWasExpanded = true

UnloadConfirmOverlay = Instance.new("Frame")
UnloadConfirmOverlay.Name = "UnloadConfirmOverlay"
UnloadConfirmOverlay.Size = UDim2.fromScale(1, 1)
UnloadConfirmOverlay.Position = UDim2.fromScale(0, 0)
UnloadConfirmOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
UnloadConfirmOverlay.BackgroundTransparency = 0.35
UnloadConfirmOverlay.BorderSizePixel = 0
UnloadConfirmOverlay.Visible = false
UnloadConfirmOverlay.ZIndex = 500
UnloadConfirmOverlay.Parent = MainFrame

UnloadConfirmCard = Instance.new("Frame")
UnloadConfirmCard.Name = "UnloadConfirmCard"
UnloadConfirmCard.Size = UDim2.fromOffset(280, 150)
UnloadConfirmCard.AnchorPoint = Vector2.new(0.5, 0.5)
UnloadConfirmCard.Position = UDim2.fromScale(0.5, 0.5)
UnloadConfirmCard.BackgroundColor3 = Color3.fromRGB(24, 28, 36)
UnloadConfirmCard.BorderSizePixel = 0
UnloadConfirmCard.ZIndex = 501
UnloadConfirmCard.Parent = UnloadConfirmOverlay

UnloadConfirmCorner = Instance.new("UICorner")
UnloadConfirmCorner.CornerRadius = UDim.new(0, 10)
UnloadConfirmCorner.Parent = UnloadConfirmCard

UnloadConfirmTitle = Instance.new("TextLabel")
UnloadConfirmTitle.Size = UDim2.new(1, -20, 0, 28)
UnloadConfirmTitle.Position = UDim2.fromOffset(10, 12)
UnloadConfirmTitle.BackgroundTransparency = 1
UnloadConfirmTitle.Text = "⚠ CONFIRMER UNLOAD"
UnloadConfirmTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadConfirmTitle.TextSize = 14
UnloadConfirmTitle.Font = Enum.Font.GothamBold
UnloadConfirmTitle.TextXAlignment = Enum.TextXAlignment.Center
UnloadConfirmTitle.ZIndex = 502
UnloadConfirmTitle.Parent = UnloadConfirmCard

UnloadConfirmText = Instance.new("TextLabel")
UnloadConfirmText.Size = UDim2.new(1, -24, 0, 42)
UnloadConfirmText.Position = UDim2.fromOffset(12, 43)
UnloadConfirmText.BackgroundTransparency = 1
UnloadConfirmText.Text = "Tu es sûr de vouloir désactiver le script ?"
UnloadConfirmText.TextColor3 = Color3.fromRGB(195, 200, 210)
UnloadConfirmText.TextSize = 11
UnloadConfirmText.Font = Enum.Font.GothamMedium
UnloadConfirmText.TextWrapped = true
UnloadConfirmText.TextXAlignment = Enum.TextXAlignment.Center
UnloadConfirmText.TextYAlignment = Enum.TextYAlignment.Center
UnloadConfirmText.ZIndex = 502
UnloadConfirmText.Parent = UnloadConfirmCard

UnloadNoBtn = Instance.new("TextButton")
UnloadNoBtn.Size = UDim2.fromOffset(112, 32)
UnloadNoBtn.Position = UDim2.fromOffset(14, 102)
UnloadNoBtn.BackgroundColor3 = Color3.fromRGB(55, 61, 74)
UnloadNoBtn.Text = "ANNULER"
UnloadNoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadNoBtn.TextSize = 10
UnloadNoBtn.Font = Enum.Font.GothamBold
UnloadNoBtn.AutoButtonColor = false
UnloadNoBtn.ZIndex = 502
UnloadNoBtn.Parent = UnloadConfirmCard

UnloadYesBtn = Instance.new("TextButton")
UnloadYesBtn.Size = UDim2.fromOffset(112, 32)
UnloadYesBtn.Position = UDim2.fromOffset(154, 102)
UnloadYesBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 54)
UnloadYesBtn.Text = "UNLOAD"
UnloadYesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadYesBtn.TextSize = 10
UnloadYesBtn.Font = Enum.Font.GothamBold
UnloadYesBtn.AutoButtonColor = false
UnloadYesBtn.ZIndex = 502
UnloadYesBtn.Parent = UnloadConfirmCard

for _, b in ipairs({UnloadNoBtn, UnloadYesBtn}) do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = b
end

local function closeUnloadConfirmation()
    UnloadConfirmOpen = false
    UnloadConfirmOverlay.Visible = false
    UnloadBtn.Active = true
    CloseBtn.Active = true
    if not UnloadWasExpanded then
        HubExpanded = false
        CloseBtn.Text = "+"
        MainFrame.Size = UDim2.fromOffset(320, 44)
        if HubMinimizedPosition then MainFrame.Position = HubMinimizedPosition end
        local body = MainFrame:FindFirstChild("V7Body")
        if body then body.Visible = false end
    end
end

local function openUnloadConfirmation()
    if UnloadConfirmOpen then return end
    UnloadConfirmOpen = true
    UnloadWasExpanded = HubExpanded == true

    -- Le dialogue doit rester lisible même si le hub était réduit.
    if not UnloadWasExpanded then
        HubExpanded = true
        CloseBtn.Text = "−"
        MainFrame.Size = HubFullSize
        MainFrame.Position = HubExpandedPosition
        local body = MainFrame:FindFirstChild("V7Body")
        if body then body.Visible = true end
    end

    UnloadConfirmOverlay.Visible = true
    UnloadBtn.Active = false
    CloseBtn.Active = false
end

UnloadBtn.MouseEnter:Connect(function()
    if not UnloadConfirmOpen then
        UnloadBtn.BackgroundColor3 = Color3.fromRGB(155, 52, 57)
    end
end)
UnloadBtn.MouseLeave:Connect(function()
    if not UnloadConfirmOpen then
        UnloadBtn.BackgroundColor3 = Color3.fromRGB(120, 45, 48)
    end
end)
UnloadBtn.MouseButton1Click:Connect(openUnloadConfirmation)
UnloadNoBtn.MouseButton1Click:Connect(closeUnloadConfirmation)

UnloadYesBtn.MouseButton1Click:Connect(function()
    if not UnloadConfirmOpen then return end
    UnloadConfirmOpen = false
    pcall(function()
        if type(_G.CombinedHubCleanup) == "function" then
            _G.CombinedHubCleanup()
        end
    end)
    pcall(function()
        if ScreenGui then ScreenGui.Enabled = false end
    end)
    _G.CombinedHubLoaded = false
    _G.CombinedHubCleanup = nil
end)

if _G.PRISONRP_HUB_RIGHTSHIFT_CONNECTION then
    pcall(function() _G.PRISONRP_HUB_RIGHTSHIFT_CONNECTION:Disconnect() end)
    _G.PRISONRP_HUB_RIGHTSHIFT_CONNECTION = nil
end
_G.PRISONRP_HUB_RIGHTSHIFT_CONNECTION = game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightShift and _G.CombinedHubReady == true then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

_G.CombinedHubCleanup = function()
    -- Coupe immédiatement les boucles principales du hub.
    running = false
    pcall(function()
        if _G.PRISONRP_HUB_RIGHTSHIFT_CONNECTION then
            _G.PRISONRP_HUB_RIGHTSHIFT_CONNECTION:Disconnect()
            _G.PRISONRP_HUB_RIGHTSHIFT_CONNECTION = nil
        end
        -- Évite de conserver des callbacks qui référencent l'ancienne interface.
        _G.PRISONRP_SETTINGS_SET_WALKSPEED = nil
        _G.PRISONRP_SETTINGS_SET_FLYSPEED = nil
    end)
    pcall(function()
        if type(_G.PRISONRP_ANTIAFK_STOP) == "function" then
            _G.PRISONRP_ANTIAFK_STOP()
            _G.PRISONRP_ANTIAFK_STOP = nil
        end
    end)
    AutoEatDrinkThreadRunning = false
    _G.AutoFishingEnabled = false
    _G.AutoSellEnabled = false
    AutoEatDrinkEnabled = false
    _G.AutoPushupEnabled = false
    _G.BlackMarketESP = false

    pcall(function() if stopAutoPushup then stopAutoPushup() end end)
    pcall(function() if autoMineStop then autoMineStop() end end)
    pcall(function() if type(_G.PRISONRP_SPEC_STOP) == "function" then _G.PRISONRP_SPEC_STOP() end end)
    pcall(function()
        if type(_G.PRISONRP_AUTO_ARM_WRESTLE_CLEANUP) == "function" then
            _G.PRISONRP_AUTO_ARM_WRESTLE_CLEANUP()
        elseif type(_G.PRISONRP_STOP_AUTO_ARM_WRESTLE) == "function" then
            _G.PRISONRP_STOP_AUTO_ARM_WRESTLE()
        end
        _G.PRISONRP_AUTO_ARM_WRESTLE_CLEANUP = nil
        _G.PRISONRP_START_AUTO_ARM_WRESTLE = nil
        _G.PRISONRP_STOP_AUTO_ARM_WRESTLE = nil
        _G.PRISONRP_AUTO_ARM_WRESTLE_STATE = nil
    end)
    pcall(function()
        if type(_G.PRISONRP_STAFF_GLOBAL_CLEANUP) == "function" then
            _G.PRISONRP_STAFF_GLOBAL_CLEANUP()
            _G.PRISONRP_STAFF_GLOBAL_CLEANUP = nil
        end
    end)
    -- V209 : coupe Give Money et déconnecte ses écouteurs globaux avant UNLOAD.
    pcall(function()
        if type(_G.PRISONRP_GIVE_MONEY_STOP) == "function" then
            _G.PRISONRP_GIVE_MONEY_STOP()
            _G.PRISONRP_GIVE_MONEY_STOP = nil
        end
    end)
    -- V208 : l'Auto Buy a ses propres boucles (buyRequest), indépendantes de
    -- running. L'arrêter ici évite les achats après UNLOAD et restaure la position.
    pcall(function() if type(stopRemoteBuy) == "function" then stopRemoteBuy() end end)
    pcall(function()
        if _G.PRISONRP_INVISIBLE_STOP then
            _G.PRISONRP_INVISIBLE_STOP()
            _G.PRISONRP_INVISIBLE_STOP = nil
        end
    end)

    pcall(function() if _G.PRISONRP_AIMBOT_STOP then _G.PRISONRP_AIMBOT_STOP() end end)
    -- Nettoyage volontairement sans références aux locals du hub :
    -- cela évite la limite Luau de 200 registres/upvalues.
    _G.CombinedHubLoaded = false
    _G.CombinedHubReady = false

    pcall(function()
        if _G.PRISONRP_STAFF_ESP_STOP then
            _G.PRISONRP_STAFF_ESP_STOP()
        end
    end)

    pcall(function()
        if _G.PRISONRP_HUB_ESP_CLEANUP then
            _G.PRISONRP_HUB_ESP_CLEANUP()
        end
    end)

    pcall(function()
        if _G.PRISONRP_MONEY_VIEW_STOP then
            _G.PRISONRP_MONEY_VIEW_STOP()
            _G.PRISONRP_MONEY_VIEW_STOP = nil
        end
    end)

    pcall(function()
        if _G.PRISONRP_FISHING_MOUSE_RELEASE then
            _G.PRISONRP_FISHING_MOUSE_RELEASE()
            _G.PRISONRP_FISHING_MOUSE_RELEASE = nil
        end
    end)

    pcall(function()
        UnloadConfirmOpen = false
        if UnloadConfirmOverlay then UnloadConfirmOverlay.Visible = false end
    end)

    pcall(function()
        local player = game:GetService("Players").LocalPlayer
        local pg = player and player:FindFirstChildOfClass("PlayerGui")
        local gui = pg and pg:FindFirstChild("CombinedHubUI")
        if gui then gui:Destroy() end
    end)

    pcall(function()
        if _G.PRISONRP_TP_SPEC_STOP then
            _G.PRISONRP_TP_SPEC_STOP()
            _G.PRISONRP_TP_SPEC_STOP = nil
        end
        _G.PRISONRP_SPEC_STOP = nil
        _G.PRISONRP_SET_SPEC_STATE = nil
        _G.PRISONRP_GET_SPEC_STATE = nil
        _G.PRISONRP_GET_TPSPEC_STATE = nil
        _G.PRISONRP_SET_TPSPEC_STATE = nil
    end)

    pcall(function()
        if _G.PRISONRP_MOVEMENT_CLEANUP then
            _G.PRISONRP_MOVEMENT_CLEANUP()
        end
    end)
end
-- AUTO FISH V28
-- Utilise le vrai état interne du MinigameSystem et sa logique native.
-- On ne déplace jamais directement la zone blanche et on ne modifie jamais
-- fishPos / zonePos. On pilote uniquement SetHolding(), exactement comme
-- le vrai système de pêche.

local function getFishingState()
    if not MinigameSystem or not MinigameSystem.SetHolding or not get_upvalues then
        return nil
    end

    local ok, holdingUvs = pcall(get_upvalues, MinigameSystem.SetHolding)
    if not ok or type(holdingUvs) ~= "table" then
        return nil
    end

    -- Dans MinigameSystem, SetHolding ferme sur le state u55.
    return holdingUvs[1]
end

local function autoFishApplyHolding()
    if not MinigameSystem or not MinigameSystem.SetHolding then
        return false
    end

    local state = getFishingState()
    if not state or not state.simulation then
        return false
    end

    local sim = state.simulation
    local fishPos = tonumber(sim.fishPos)
    local zonePos = tonumber(sim.zonePos)
    local zoneVel = tonumber(sim.zoneVel) or 0

    if not fishPos or not zonePos then
        return false
    end

    -- Logique native du jeu :
    -- holding = zonePos + zoneVel * 0.2 < fishPos
    local shouldHold = (zonePos + zoneVel * 0.2) < fishPos

    pcall(function()
        MinigameSystem:SetHolding(shouldHold, "autofish")
    end)

    return true
end

local function autoFishRelease()
    if MinigameSystem and MinigameSystem.SetHolding then
        pcall(function()
            MinigameSystem:SetHolding(false, "autofish")
        end)
    end
end

_G.PRISONRP_FISHING_MOUSE_RELEASE = autoFishRelease

-- Auto Fish V28 : boucle de contrôle rapide.
-- Le moteur de jeu reste responsable du déplacement de la zone blanche ;
-- nous ne faisons que maintenir / relâcher via SetHolding().
task.spawn(function()
    while running and ScreenGui and ScreenGui.Parent do
        task.wait(0.01)

        if _G.AutoFishingEnabled and MinigameSystem then
            local active, phase = false, nil

            pcall(function()
                active = MinigameSystem:IsActive()
                if active then
                    phase = MinigameSystem:GetPhase()
                end
            end)

            if active and phase == "reel" then
                autoFishApplyHolding()
            else
                autoFishRelease()
            end
        else
            autoFishRelease()
        end
    end

    autoFishRelease()
end)

-- Boucle Pêche principale
-- V208 : mémorise le dernier compteur vendu pour éviter de renvoyer
-- Inventory_SellAll à chaque cycle tant que totalCaught reste un multiple de 3.
local lastAutoSellCatchCount = 0
task.spawn(function()
    while running and ScreenGui and ScreenGui.Parent do
        task.wait(0.1)
        if _G.AutoFishingEnabled and not AutoEatDrinkBusy and MinigameSystem and SoundManager and GUIManager then

            stats.status = "Equipping Rod..."
            updateUI()
            if not ensureRodEquipped() then
                stats.status = "No Rod Found!"
                updateUI()
                task.wait(1)
                continue
            end

            local onActionBegan, onActionEnded, performCast = getActiveRodFunctions()
            if not onActionBegan or not onActionEnded or not performCast then
                stats.status = "Finding Scripts..."
                updateUI()
                task.wait(0.5)
                continue
            end

            local rodState = get_upvalues(performCast)[1]
            local miniState = getFishingState()

            stats.status = "Casting Rod..."
            updateUI()
            onActionBegan()
            task.wait(0.80)
            if AutoEatDrinkBusy then
                task.wait(0.1)
                continue
            end
            onActionEnded()

            local castTime = tick()
            local loopTimeout = 15
            -- V30 : accélère les clics de la phase de lancement / shake.
            local lastShakeClick = -math.huge
            local shakeClickInterval = 0.08
            local shouldSkip = false

            while running and _G.AutoFishingEnabled and not AutoEatDrinkBusy and (tick() - castTime < loopTimeout) do
                task.wait(0.02)
                
                if rodState and rodState.PreRolledFish and rodState.PreRolledFish.name then
                    local fishRarity = rodState.PreRolledFish.rarity
                    local currentRarityIdx = getRarityIndex(fishRarity)
                    
                    stats.lastFish = tostring(rodState.PreRolledFish.name) .. " (" .. tostring(fishRarity) .. ")"
                    
                    if currentRarityIdx < _G.MinRarityIndex then
                        stats.status = "Ignoré: " .. tostring(fishRarity)
                        updateUI()
                        shouldSkip = true
                        break
                    end
                end

                if MinigameSystem:IsActive() then
                    local phase = MinigameSystem:GetPhase()
                    if phase == "shake" then
                        stats.status = "Luring Fish..."
                        updateUI()
                        if tick() - lastShakeClick >= shakeClickInterval then
                            lastShakeClick = tick()
                            pcall(function()
                                MinigameSystem:HandleClick(SoundManager, GUIManager)
                            end)
                        end
                    elseif phase == "reel" then
                        stats.status = "Reeling..."
                        updateUI()

                        -- V28 : reproduit la décision native du moteur.
                        -- Aucun déplacement/téléport de la zone blanche.
                        autoFishApplyHolding()
                    end
                end

                if (tick() - castTime > 3.5) and rodState and (not rodState.Casted) and (not rodState.FishingInProgress) then
                    stats.totalCaught = stats.totalCaught + 1
                    stats.perfectCount = stats.perfectCount + 1
                    stats.status = "Fish Caught!"
                    updateUI()
                    break
                end
            end

            if AutoEatDrinkBusy then
                task.wait(0.1)
                continue
            end

            if shouldSkip then
                resetRod()
                task.wait(0.2)
                continue
            end

            if _G.AutoSellEnabled
                and Inventory_SellAll
                and stats.totalCaught > 0
                and stats.totalCaught % 3 == 0
                and lastAutoSellCatchCount ~= stats.totalCaught then
                local saleCallSucceeded = pcall(function()
                    Inventory_SellAll:InvokeServer()
                end)
                if saleCallSucceeded then
                    lastAutoSellCatchCount = stats.totalCaught
                end
            end

            task.wait(0.4)
        else
            if stats.status ~= "Sold All Fish!" then
                stats.status = "Idle"
            end
            updateUI()
            task.wait(0.5)
        end
    end
end)

autoFishRelease()

updateUI()

updateAutoEatDrinkUI()

--==============================================================
--==============================================================
-- OMEGA : 2 PAGES
-- PAGE 1 = hub actuel, inchangé
-- PAGE 2 = AUTRES
--==============================================================
pcall(function()
    MainFrame.Size = UDim2.new(0, 500, 0, 620)
    TitleLabel.Text = "PRISON RP FR GDP"

    Content.Size = UDim2.new(1, -145, 1, -100)
    Content.Position = UDim2.new(0, 135, 0, 55)
    Content.CanvasSize = UDim2.new(0, 0, 0, 980)

    -- Cache UNIQUEMENT les anciens contrôles de déplacement.
    -- Ils restent connectés au système mais ne sont plus visibles.
    MovementTitle.Visible = false
    MovementSpeedBox.Visible = false
    MovementFlySpeedBox.Visible = false
    MovementSpeedBtn.Visible = false
    MovementFlyBtn.Visible = false
    MovementNoclipBtn.Visible = false
    MovementHint.Visible = false

    -- BARRE DE GAUCHE
    local sidebar = Instance.new("Frame")
    sidebar.Name = "OmegaSidebar"
    sidebar.Size = UDim2.new(0, 118, 1, -44)
    sidebar.Position = UDim2.new(0, 0, 0, 44)
    sidebar.BackgroundColor3 = Color3.fromRGB(18, 18, 19)
    sidebar.BorderSizePixel = 0
    sidebar.ZIndex = 50
    sidebar.Parent = MainFrame

    local line = Instance.new("Frame")
    line.Size = UDim2.new(0, 1, 1, 0)
    line.Position = UDim2.new(1, -1, 0, 0)
    line.BackgroundColor3 = Color3.fromRGB(210, 115, 0)
    line.BorderSizePixel = 0
    line.ZIndex = 51
    line.Parent = sidebar

    local farmTab = Instance.new("TextButton")
    farmTab.Name = "OmegaFarmTab"
    farmTab.Size = UDim2.new(1, -8, 0, 42)
    farmTab.Position = UDim2.fromOffset(4, 18)
    farmTab.BackgroundColor3 = Color3.fromRGB(210, 115, 0)
    farmTab.BorderSizePixel = 0
    farmTab.Text = "FARM"
    farmTab.TextColor3 = Color3.fromRGB(255,255,255)
    farmTab.TextSize = 12
    farmTab.Font = Enum.Font.GothamMedium
    farmTab.ZIndex = 52
    farmTab.Parent = sidebar

    local othersTab = Instance.new("TextButton")
    othersTab.Name = "OmegaOthersTab"
    othersTab.Size = UDim2.new(1, -8, 0, 42)
    othersTab.Position = UDim2.fromOffset(4, 66)
    othersTab.Visible = true
    othersTab.BackgroundColor3 = Color3.fromRGB(18,18,19)
    othersTab.BorderSizePixel = 0
    othersTab.Text = "DÉPLACEMENT"
    othersTab.TextColor3 = Color3.fromRGB(160,160,160)
    othersTab.TextSize = 11
    othersTab.Font = Enum.Font.GothamMedium
    othersTab.ZIndex = 52
    othersTab.Parent = sidebar

    -- PAGE 2 (ancien DÉPLACEMENT conservé en interne mais sans onglet visible)
    local movementPage = Instance.new("Frame")
    movementPage.Name = "OmegaOthersPage"
    movementPage.Size = UDim2.new(1, -145, 1, -100)
    movementPage.Position = UDim2.new(0, 135, 0, 55)
    movementPage.BackgroundTransparency = 1
    movementPage.BorderSizePixel = 0
    movementPage.Visible = false
    movementPage.ZIndex = 11
    movementPage.Parent = MainFrame

    -- PAGE 3 : ESP — STAFF ESP / AUTO-LEAVE / BLACK MARKET
    local espTab = Instance.new("TextButton")
    espTab.Name = "OmegaESPTab"
    espTab.Size = UDim2.new(1, -8, 0, 42)
    espTab.Position = UDim2.fromOffset(4, 114)
    espTab.BackgroundColor3 = Color3.fromRGB(18,18,19)
    espTab.BorderSizePixel = 0
    espTab.Text = "ESP"
    espTab.TextColor3 = Color3.fromRGB(160,160,160)
    espTab.TextSize = 11
    espTab.Font = Enum.Font.GothamMedium
    espTab.ZIndex = 52
    espTab.Parent = sidebar

    -- PAGE 4 : AUTRES
    local autresTab = Instance.new("TextButton")
    autresTab.Name = "OmegaAutresTab"
    autresTab.Size = UDim2.new(1, -8, 0, 42)
    autresTab.Position = UDim2.fromOffset(4, 162)
    autresTab.BackgroundColor3 = Color3.fromRGB(18,18,19)
    autresTab.BorderSizePixel = 0
    autresTab.Text = "AUTRES"
    autresTab.TextColor3 = Color3.fromRGB(160,160,160)
    autresTab.TextSize = 11
    autresTab.Font = Enum.Font.GothamMedium
    autresTab.ZIndex = 52
    autresTab.Parent = sidebar

    local espPage = Instance.new("Frame")
    espPage.Name = "OmegaESPPage"
    espPage.Size = UDim2.new(1, -145, 1, -100)
    espPage.Position = UDim2.new(0, 135, 0, 55)
    espPage.BackgroundTransparency = 1
    espPage.BorderSizePixel = 0
    espPage.Visible = false
    espPage.ZIndex = 11
    espPage.Parent = MainFrame

    local autresPage = Instance.new("Frame")
    autresPage.Name = "OmegaAutresPage"
    autresPage.Size = UDim2.new(1, -145, 1, -100)
    autresPage.Position = UDim2.new(0, 135, 0, 55)
    autresPage.BackgroundTransparency = 1
    autresPage.BorderSizePixel = 0
    autresPage.Visible = false
    autresPage.ZIndex = 11
    autresPage.Parent = MainFrame

    --==============================================================
    -- TP JOUEUR + SPEC — éléments conservés en interne
    -- Compact : liste défilante avec NOM RP + @USERNAME.
    -- Le système reprend la caméra 3e personne libre du standalone.
    --==============================================================
    local TPSpecSelectedPlayer = nil
    local TPSpecEnabled = false
    local TPSpecConnection = nil
    local TPSpecLifetimeConnections = {}
    local function tpSpecTrackConnection(connection)
        if connection then
            table.insert(TPSpecLifetimeConnections, connection)
        end
        return connection
    end
    local TPSpecSavedCameraType = nil
    local TPSpecSavedCameraSubject = nil
    local TPSpecDistance = 8
    local TPSpecYaw = 0
    local TPSpecPitch = math.rad(-10)
    local TPSpecSensitivity = 0.004
    local TPSpecMinDistance = 4
    local TPSpecMaxDistance = 18
    local TPSpecRotating = false
    local TPSpecRPcache = {}
    local TPSpecPlayerButtons = {}

    local function tpSpecGetRoot(player)
        local character = player and player.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local function tpSpecCleanRPText(text, player)
        if not text then return nil end
        text = tostring(text):gsub("\r", "")
        local lines = {}
        for line in text:gmatch("[^\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then table.insert(lines, line) end
        end

        local raw = table.concat(lines, " ")
        local beforeAt = raw:match("^(.-)%s*@[%w_]+")
        if beforeAt then
            beforeAt = beforeAt:gsub("^%s+", ""):gsub("%s+$", "")
            if beforeAt ~= "" and beforeAt ~= player.Name and beforeAt ~= player.DisplayName then
                return beforeAt
            end
        end

        for i, line in ipairs(lines) do
            if line == "@" .. player.Name then
                local candidate = lines[i - 1]
                if candidate and candidate ~= "" and not candidate:find("%[")
                    and candidate ~= player.Name and candidate ~= player.DisplayName then
                    return candidate
                end
            end
        end

        for _, line in ipairs(lines) do
            local lower = line:lower()
            if line ~= player.Name
                and line ~= player.DisplayName
                and not line:find("@")
                and not line:find("%[")
                and not lower:find("vie:")
                and not lower:find("health")
                and not lower:find("distance")
                and not lower:find("dis:")
                and not lower:find("homme")
                and not lower:find("femme")
                and #line <= 40 then
                return line
            end
        end
        return nil
    end

    local function tpSpecGetRPPseudo(player)
        if not player then return "Inconnu" end
        if TPSpecRPcache[player] and TPSpecRPcache[player] ~= "" then
            return TPSpecRPcache[player]
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.DisplayName and humanoid.DisplayName ~= ""
            and humanoid.DisplayName ~= player.Name and humanoid.DisplayName ~= player.DisplayName then
            TPSpecRPcache[player] = humanoid.DisplayName
            return humanoid.DisplayName
        end

        local containers = {player, character}
        local keys = {"RPName", "RP_Name", "RoleplayName", "CharacterName", "CharName", "PseudoRP", "Pseudo_RP", "NomRP", "Nom_RP"}
        for _, container in ipairs(containers) do
            if container then
                for _, key in ipairs(keys) do
                    local attr = container:GetAttribute(key)
                    if typeof(attr) == "string" and attr ~= "" and attr ~= player.Name and attr ~= player.DisplayName then
                        TPSpecRPcache[player] = attr
                        return attr
                    end
                end
                for _, obj in ipairs(container:GetChildren()) do
                    if obj:IsA("StringValue") or obj:IsA("TextLabel") then
                        local n = obj.Name:lower()
                        if n:find("rp") or n:find("roleplay") or n:find("charactername")
                            or n:find("charname") or n:find("pseudorp") or n:find("nomrp") then
                            local value = obj:IsA("StringValue") and obj.Value or obj.Text
                            if value and value ~= "" and value ~= player.Name and value ~= player.DisplayName then
                                TPSpecRPcache[player] = value
                                return value
                            end
                        end
                    end
                end
            end
        end

        -- Dernier recours : tente de lire un texte d'ESP existant contenant le pseudo RP.
        local pg = player:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, obj in ipairs(pg:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Text and obj.Text ~= "" then
                    local candidate = tpSpecCleanRPText(obj.Text, player)
                    if candidate then
                        TPSpecRPcache[player] = candidate
                        return candidate
                    end
                end
            end
        end

        return player.DisplayName or player.Name
    end

    local tpSpecPanel = Instance.new("Frame")
    tpSpecPanel.Name = "OmegaTPSpecPanel"
    tpSpecPanel.Size = UDim2.new(1, 0, 0, 292)
    tpSpecPanel.Position = UDim2.fromOffset(0, 0)
    tpSpecPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
    tpSpecPanel.BorderSizePixel = 0
    tpSpecPanel.ZIndex = 12
    tpSpecPanel.Parent = movementPage

    local tpPanelCorner = Instance.new("UICorner")
    tpPanelCorner.CornerRadius = UDim.new(0, 7)
    tpPanelCorner.Parent = tpSpecPanel

    local tpPanelStroke = Instance.new("UIStroke")
    tpPanelStroke.Color = Color3.fromRGB(55, 55, 60)
    tpPanelStroke.Thickness = 1
    tpPanelStroke.Parent = tpSpecPanel

    local tpTitle = Instance.new("TextLabel")
    tpTitle.Size = UDim2.new(1, -12, 0, 20)
    tpTitle.Position = UDim2.fromOffset(6, 4)
    tpTitle.BackgroundTransparency = 1
    tpTitle.Text = "👁 TP / SPEC — Joueurs"
    tpTitle.TextColor3 = Color3.fromRGB(235, 235, 235)
    tpTitle.TextSize = 11
    tpTitle.Font = Enum.Font.GothamBold
    tpTitle.TextXAlignment = Enum.TextXAlignment.Left
    tpTitle.ZIndex = 13
    tpTitle.Parent = tpSpecPanel

    local tpSearchBox = Instance.new("TextBox")
    tpSearchBox.Name = "PlayerSearchBox"
    tpSearchBox.Size = UDim2.new(1, -12, 0, 24)
    tpSearchBox.Position = UDim2.fromOffset(6, 25)
    tpSearchBox.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
    tpSearchBox.BorderSizePixel = 0
    tpSearchBox.ClearTextOnFocus = false
    tpSearchBox.PlaceholderText = "🔎 Rechercher un blaze..."
    tpSearchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 126)
    tpSearchBox.Text = ""
    tpSearchBox.TextColor3 = Color3.fromRGB(235, 235, 235)
    tpSearchBox.TextSize = 9
    tpSearchBox.Font = Enum.Font.GothamMedium
    tpSearchBox.TextXAlignment = Enum.TextXAlignment.Left
    tpSearchBox.ZIndex = 15
    tpSearchBox.Parent = tpSpecPanel

    local tpSearchPad = Instance.new("UIPadding")
    tpSearchPad.PaddingLeft = UDim.new(0, 9)
    tpSearchPad.PaddingRight = UDim.new(0, 7)
    tpSearchPad.Parent = tpSearchBox

    local tpSearchCorner = Instance.new("UICorner")
    tpSearchCorner.CornerRadius = UDim.new(0, 5)
    tpSearchCorner.Parent = tpSearchBox

    local tpSearchStroke = Instance.new("UIStroke")
    tpSearchStroke.Color = Color3.fromRGB(55, 55, 60)
    tpSearchStroke.Thickness = 1
    tpSearchStroke.Parent = tpSearchBox

    local tpListFrame = Instance.new("Frame")
    tpListFrame.Size = UDim2.new(1, -12, 0, 134)
    tpListFrame.Position = UDim2.fromOffset(6, 53)
    tpListFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
    tpListFrame.BorderSizePixel = 0
    tpListFrame.ZIndex = 13
    tpListFrame.Parent = tpSpecPanel

    local tpList = Instance.new("ScrollingFrame")
    tpList.Name = "PlayerList"
    tpList.Size = UDim2.new(1, -6, 1, -6)
    tpList.Position = UDim2.fromOffset(3, 3)
    tpList.BackgroundTransparency = 1
    tpList.BorderSizePixel = 0
    tpList.ScrollBarThickness = 3
    tpList.ScrollBarImageColor3 = Color3.fromRGB(210, 115, 0)
    tpList.CanvasSize = UDim2.new(0, 0, 0, 0)
    tpList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    tpList.ScrollingDirection = Enum.ScrollingDirection.Y
    tpList.ZIndex = 14
    tpList.Parent = tpListFrame

    local tpListLayout = Instance.new("UIListLayout")
    tpListLayout.Padding = UDim.new(0, 2)
    tpListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tpListLayout.Parent = tpList

    local tpSelected = Instance.new("TextLabel")
    tpSelected.Size = UDim2.new(1, -12, 0, 18)
    tpSelected.Position = UDim2.fromOffset(6, 190)
    tpSelected.BackgroundTransparency = 1
    tpSelected.Text = "Sélection : aucune"
    tpSelected.TextColor3 = Color3.fromRGB(185, 185, 190)
    tpSelected.TextSize = 8
    tpSelected.Font = Enum.Font.GothamMedium
    tpSelected.TextXAlignment = Enum.TextXAlignment.Left
    tpSelected.TextTruncate = Enum.TextTruncate.AtEnd
    tpSelected.ZIndex = 13
    tpSelected.Parent = tpSpecPanel

    local tpButton = Instance.new("TextButton")
    tpButton.Size = UDim2.new(1, -12, 0, 30)
    tpButton.Position = UDim2.fromOffset(6, 247)
    tpButton.BackgroundTransparency = 1
    tpButton.BorderSizePixel = 0
    tpButton.Active = true
    tpButton.Text = "📍 TP"
    tpButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    tpButton.TextSize = 9
    tpButton.Font = Enum.Font.GothamBold
    tpButton.ZIndex = 13
    tpButton.Parent = tpSpecPanel

    local tpSpecButton = Instance.new("TextButton")
    tpSpecButton.Size = UDim2.new(1, -12, 0, 30)
    tpSpecButton.Position = UDim2.fromOffset(6, 211)
    tpSpecButton.BackgroundTransparency = 1
    tpSpecButton.BorderSizePixel = 0
    tpSpecButton.AutoButtonColor = false
    tpSpecButton.Active = false
    tpSpecButton.Selectable = false
    tpSpecButton.Text = "🎥 SPEC"
    tpSpecButton.TextColor3 = Color3.fromRGB(235, 235, 235)
    tpSpecButton.TextSize = 9
    tpSpecButton.Font = Enum.Font.GothamBold
    tpSpecButton.TextXAlignment = Enum.TextXAlignment.Center
    tpSpecButton.ZIndex = 13
    tpSpecButton.Parent = tpSpecPanel

    -- V9 : ancien switch SPEC inline désactivé.
    -- Le seul switch visible est recréé plus bas, APRÈS la carte SPEC.
    local tpSpecSwitch = Instance.new("TextButton")
    tpSpecSwitch.Name = "LegacySpecSwitch_REMOVED"
    tpSpecSwitch.Size = UDim2.fromOffset(1, 1)
    tpSpecSwitch.Position = UDim2.fromOffset(0, 0)
    tpSpecSwitch.BackgroundTransparency = 1
    tpSpecSwitch.BorderSizePixel = 0
    tpSpecSwitch.Text = ""
    tpSpecSwitch.Visible = false
    tpSpecSwitch.Active = false
    tpSpecSwitch.Parent = nil

    local tpSpecKnob = nil
    local tpSpecSwitch = nil
    local TweenService = game:GetService("TweenService")
    local tpSpecSwitchTween = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    local function updateTpSpecSwitch(animated)
        if not tpSpecSwitch or not tpSpecKnob or not tpSpecKnob.Parent then return end
        local target = TPSpecEnabled and UDim2.new(1, -19, 0, 3) or UDim2.fromOffset(3, 3)
        local targetColor = TPSpecEnabled and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(70, 80, 94)
        if animated then
            TweenService:Create(tpSpecKnob, tpSpecSwitchTween, {Position = target}):Play()
            TweenService:Create(tpSpecSwitch, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = targetColor}):Play()
        else
            tpSpecKnob.Position = target
            tpSpecSwitch.BackgroundColor3 = targetColor
        end
    end

    local function tpSpecFindEmitter(player)
        local character = player and player.Character
        if character then
            local emitter = character:FindFirstChildOfClass("AudioEmitter")
            if emitter then return emitter end
            for _, obj in ipairs(character:GetDescendants()) do
                if obj:IsA("AudioEmitter") then return obj end
            end
        end
        return nil
    end

    local function tpSpecVoiceStatus(targetRoot, listener)
        local parts = {}
        local emitter = tpSpecFindEmitter(TPSpecSelectedPlayer)
        local voiceEnabled = nil
        if TPSpecSelectedPlayer then
            pcall(function()
                local VoiceChatService = game:GetService("VoiceChatService")
                voiceEnabled = VoiceChatService:IsVoiceEnabledForUserIdAsync(TPSpecSelectedPlayer.UserId)
            end)
        end
        local listenerFound = listener ~= nil
        local output = nil
        pcall(function()
            local SoundService = game:GetService("SoundService")
            output = SoundService:FindFirstChildOfClass("AudioDeviceOutput")
        end)
        table.insert(parts, "Voice=" .. (voiceEnabled == true and "ON" or voiceEnabled == false and "OFF" or "?"))
        table.insert(parts, "Emitter=" .. (emitter and "OK" or "NON"))
        table.insert(parts, "Listener=" .. (listenerFound and "OK" or "NON"))
        table.insert(parts, "Output=" .. (output and "OK" or "NON"))
        if listener then
            local count = 0
            pcall(function() count = #listener:GetInteractingEmitters() end)
            table.insert(parts, "Audible=" .. tostring(count))
        end
        return table.concat(parts, " | ")
    end

    -- SPEC VOICE :
    -- Roblox peut avoir plusieurs AudioListener actifs (par exemple un listener
    -- sous le personnage ET un listener sous la caméra). Si on ne désactive pas
    -- les autres, on continue d'entendre les gens autour de notre personnage.
    -- On garde donc un seul listener actif, positionné sur le joueur observé,
    -- tout en conservant son AudioInteractionGroup natif pour entendre ce qui
    -- l'entoure normalement.
    local TPSpecVoiceSavedListeners = {}
    local TPSpecVoiceActiveListener = nil
    local TPSpecVoiceCreatedListener = false
    local TPSpecVoiceCreatedOutput = false
    local TPSpecVoiceCreatedWire = nil
    local TPSpecVoiceMuteGroup = nil

    local function tpSpecFindBestListener()
        local camera = workspace.CurrentCamera
        if camera then
            local listener = camera:FindFirstChildOfClass("AudioListener")
            if listener then return listener end
        end

        local char = LocalPlayer and LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local listener = root:FindFirstChildOfClass("AudioListener")
            if listener then return listener end
        end

        local soundService = game:GetService("SoundService")
        return soundService:FindFirstChildOfClass("AudioListener")
    end

    local function tpSpecEnsureVoiceOutput(listener)
        if not listener then return end
        pcall(function()
            local SoundService = game:GetService("SoundService")
            local output = SoundService:FindFirstChildOfClass("AudioDeviceOutput")
            if not output then
                output = Instance.new("AudioDeviceOutput")
                output.Name = "OmegaTP_VoiceOutput"
                output.Parent = SoundService
                TPSpecVoiceCreatedOutput = true
            end

            local connected = false
            for _, child in ipairs(listener:GetChildren()) do
                if child:IsA("Wire") and child.SourceInstance == listener and child.TargetInstance == output then
                    connected = true
                    break
                end
            end

            if not connected then
                local wire = Instance.new("Wire")
                wire.Name = "OmegaTP_VoiceWire"
                wire.SourceInstance = listener
                wire.TargetInstance = output
                wire.Parent = listener
                TPSpecVoiceCreatedWire = wire
            end
        end)
    end

    local function tpSpecSetVoiceListener(targetRoot)
        local camera = workspace.CurrentCamera
        if not camera or not targetRoot then return end

        -- Toujours utiliser le listener principal de la caméra pour garder
        -- le flux audio connecté à la sortie Roblox.
        local listener = camera:FindFirstChildOfClass("AudioListener")
        if not listener then
            listener = tpSpecFindBestListener()
        end

        if not listener then
            local ok, created = pcall(function()
                local newListener = Instance.new("AudioListener")
                newListener.Name = "OmegaTP_VoiceListener"
                newListener.Parent = camera
                return newListener
            end)
            if not ok or not created then return end
            listener = created
            TPSpecVoiceCreatedListener = true
        end

        -- Sauvegarde de tous les listeners existants une seule fois.
        if next(TPSpecVoiceSavedListeners) == nil then
            for _, item in ipairs(game:GetDescendants()) do
                if item:IsA("AudioListener") then
                    local saved = {
                        Parent = item.Parent,
                        PositionType = nil,
                        PositionInstance = nil,
                        AudioInteractionGroup = nil,
                    }
                    pcall(function() saved.PositionType = item.PositionType end)
                    pcall(function() saved.PositionInstance = item.PositionInstance end)
                    pcall(function() saved.AudioInteractionGroup = item.AudioInteractionGroup end)
                    TPSpecVoiceSavedListeners[item] = saved
                end
            end
            TPSpecVoiceMuteGroup = "PrisonRP_SPEC_MUTE_" .. tostring(LocalPlayer and LocalPlayer.UserId or 0)
        end

        TPSpecVoiceActiveListener = listener

        -- Le point d'écoute devient le joueur choisi, sans déplacer le listener.
        pcall(function()
            listener.PositionType = Enum.ListenerPositionType.Instance
            listener.PositionInstance = targetRoot
        end)

        -- Le chat vocal Roblox utilise la paire AudioEmitter/AudioListener et
        -- leur AudioInteractionGroup. On reprend explicitement le groupe de
        -- l'emitter du joueur choisi afin que sa voix soit réellement audible.
        local targetEmitter = tpSpecFindEmitter(TPSpecSelectedPlayer)
        local targetGroup = nil
        if targetEmitter then
            pcall(function() targetGroup = targetEmitter.AudioInteractionGroup end)
        end

        if targetGroup ~= nil then
            pcall(function() listener.AudioInteractionGroup = targetGroup end)
        else
            local saved = TPSpecVoiceSavedListeners[listener]
            if saved then
                pcall(function() listener.AudioInteractionGroup = saved.AudioInteractionGroup or "" end)
            end
        end

        -- Désactive les autres listeners : aucune écoute autour de notre propre
        -- personnage pendant le SPEC.
        for other, _ in pairs(TPSpecVoiceSavedListeners) do
            if other ~= listener and other.Parent then
                pcall(function()
                    other.AudioInteractionGroup = TPSpecVoiceMuteGroup
                end)
            end
        end

        -- S'assure que le listener actif possède bien une sortie audio.
        tpSpecEnsureVoiceOutput(listener)
    end

    local function tpSpecRestoreVoice()
        for listener, saved in pairs(TPSpecVoiceSavedListeners) do
            if listener and listener.Parent then
                pcall(function()
                    if saved.Parent and saved.Parent.Parent then
                        listener.Parent = saved.Parent
                    end
                    if saved.PositionType ~= nil then
                        listener.PositionType = saved.PositionType
                    end
                    listener.PositionInstance = saved.PositionInstance
                    listener.AudioInteractionGroup = saved.AudioInteractionGroup or ""
                end)
            end
        end

        pcall(function()
            if TPSpecVoiceCreatedWire and TPSpecVoiceCreatedWire.Parent then
                TPSpecVoiceCreatedWire:Destroy()
            end
        end)
        pcall(function()
            if TPSpecVoiceCreatedListener and TPSpecVoiceActiveListener and TPSpecVoiceActiveListener.Parent then
                TPSpecVoiceActiveListener:Destroy()
            end
        end)
        pcall(function()
            if TPSpecVoiceCreatedOutput and game:GetService("SoundService"):FindFirstChild("OmegaTP_VoiceOutput") then
                game:GetService("SoundService").OmegaTP_VoiceOutput:Destroy()
            end
        end)

        TPSpecVoiceSavedListeners = {}
        TPSpecVoiceActiveListener = nil
        TPSpecVoiceCreatedListener = false
        TPSpecVoiceCreatedOutput = false
        TPSpecVoiceCreatedWire = nil
        TPSpecVoiceMuteGroup = nil
    end

    local function tpSpecStop()
        TPSpecEnabled = false
        TPSpecRotating = false
        MovementUserInputService.MouseBehavior = Enum.MouseBehavior.Default
        if TPSpecConnection then
            TPSpecConnection:Disconnect()
            TPSpecConnection = nil
        end
        tpSpecRestoreVoice()
        local camera = workspace.CurrentCamera
        if camera then
            camera.CameraType = TPSpecSavedCameraType or Enum.CameraType.Custom
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            camera.CameraSubject = TPSpecSavedCameraSubject or humanoid
        end
        tpSpecButton.Text = "🎥 SPEC"
        updateTpSpecSwitch(true)
        tpSpecUpdateInfo()
    end

    local function tpSpecStart()
        local selected = TPSpecSelectedPlayer
        if not selected or selected == LocalPlayer then
            return
        end
        local character = selected.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local head = character and character:FindFirstChild("Head")
        local focusPart = head or root
        if not focusPart then
            return
        end
        local camera = workspace.CurrentCamera
        if not camera then return end

        TPSpecSavedCameraType = camera.CameraType
        TPSpecSavedCameraSubject = camera.CameraSubject
        TPSpecEnabled = true
        TPSpecYaw = 0
        TPSpecPitch = math.rad(-10)
        TPSpecDistance = 8
        camera.CameraType = Enum.CameraType.Scriptable

        TPSpecConnection = RunService.RenderStepped:Connect(function()
            if not TPSpecEnabled then return end
            if not TPSpecSelectedPlayer or not TPSpecSelectedPlayer.Parent then
                tpSpecStop()
                return
            end
            local char = TPSpecSelectedPlayer.Character
            if not char then
                tpSpecStop()
                return
            end
            local rootNow = char:FindFirstChild("HumanoidRootPart")
            local part = char:FindFirstChild("Head") or rootNow
            if not part or not part.Parent then
                tpSpecStop()
                return
            end

            -- Déplace l'écouteur audio sur le joueur observé.
            -- Les voix autour du joueur observé restent audibles selon la spatialisation native.
            tpSpecSetVoiceListener(rootNow or part)

            -- La caméra suit la POSITION du joueur, pas son orientation.
            local focus = (rootNow or part).Position + Vector3.new(0, 1.5, 0)
            local rotation = CFrame.fromEulerAnglesYXZ(TPSpecPitch, TPSpecYaw, 0)
            local offset = rotation:VectorToWorldSpace(Vector3.new(0, 0, TPSpecDistance))
            local cameraPosition = focus + offset
            camera.CFrame = CFrame.lookAt(cameraPosition, focus)
            camera.Focus = CFrame.new(focus)
            tpSpecUpdateInfo()
        end)

        tpSpecButton.Text = "🎥 SPEC"
        updateTpSpecSwitch(true)
        tpSpecUpdateInfo()
    end

    local function tpSpecSearchMatches(player, query)
        query = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if query == "" then return true end
        local rp = tostring(tpSpecGetRPPseudo(player) or ""):lower()
        local username = tostring(player.Name or ""):lower()
        local display = tostring(player.DisplayName or ""):lower()
        return rp:find(query, 1, true) ~= nil
            or username:find(query, 1, true) ~= nil
            or display:find(query, 1, true) ~= nil
    end

    local function tpSpecRefresh()
        for _, child in ipairs(tpList:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        TPSpecPlayerButtons = {}

        local players = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then table.insert(players, player) end
        end
        table.sort(players, function(a, b)
            return string.lower(tpSpecGetRPPseudo(a)) < string.lower(tpSpecGetRPPseudo(b))
        end)

        local query = tpSearchBox and tpSearchBox.Text or ""
        for _, player in ipairs(players) do
            if tpSpecSearchMatches(player, query) then
                local button = Instance.new("TextButton")
            button.Size = UDim2.new(1, -2, 0, 30)
            button.BackgroundTransparency = 0
            button.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
            button.BorderSizePixel = 0
            button.AutoButtonColor = false
            button.Active = true
            button.Text = "  " .. tpSpecGetRPPseudo(player) .. "\n  @" .. player.Name
            button.TextColor3 = Color3.fromRGB(225, 225, 225)
            button.TextSize = 8
            button.Font = Enum.Font.GothamMedium
            button.TextXAlignment = Enum.TextXAlignment.Left
            button.TextTruncate = Enum.TextTruncate.AtEnd
            button.ZIndex = 15
            button.Parent = tpList
            TPSpecPlayerButtons[player] = button

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 4)
            corner.Parent = button

                button.Activated:Connect(function()
                    if TPSpecEnabled then tpSpecStop() end
                    TPSpecSelectedPlayer = player
                    for _, b in pairs(TPSpecPlayerButtons) do
                        if b and b.Parent then
                            b.BackgroundTransparency = 0
                            b.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
                        end
                    end
                    button.BackgroundTransparency = 0
                    button.BackgroundColor3 = Color3.fromRGB(210, 115, 0)
                    tpSelected.Text = "Sélection : " .. tpSpecGetRPPseudo(player) .. "  @" .. player.Name
                    tpSpecUpdateInfo()
                end)
            end
        end
        task.defer(function()
            tpList.CanvasSize = UDim2.fromOffset(0, tpListLayout.AbsoluteContentSize.Y + 3)
        end)
    end

    tpButton.Activated:Connect(function()
        local player = TPSpecSelectedPlayer
        if not player then
            tpSelected.Text = "Sélection : aucune"
            return
        end
        local localRoot = tpSpecGetRoot(LocalPlayer)
        local targetRoot = tpSpecGetRoot(player)
        if not localRoot then
            tpSelected.Text = "Erreur : ton personnage est introuvable"
            return
        end
        if not targetRoot then
            tpSelected.Text = "Erreur : personnage non chargé"
            return
        end
        pcall(function()
            localRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 4)
            localRoot.AssemblyLinearVelocity = Vector3.zero
            localRoot.AssemblyAngularVelocity = Vector3.zero
        end)
        tpSelected.Text = "TP → " .. tpSpecGetRPPseudo(player) .. "  @" .. player.Name
    end)

    tpSpecTrackConnection(MovementUserInputService.InputBegan:Connect(function(input, processed)
        if processed or not TPSpecEnabled then return end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            TPSpecRotating = true
            MovementUserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        end
    end))

    tpSpecTrackConnection(MovementUserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            TPSpecRotating = false
            if TPSpecEnabled then
                MovementUserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
        end
    end))

    tpSpecTrackConnection(MovementUserInputService.InputChanged:Connect(function(input)
        if not TPSpecEnabled then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement and TPSpecRotating then
            TPSpecYaw = TPSpecYaw - input.Delta.X * TPSpecSensitivity
            TPSpecPitch = math.clamp(
                TPSpecPitch - input.Delta.Y * TPSpecSensitivity,
                math.rad(-75), math.rad(75)
            )
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            TPSpecDistance = math.clamp(
                TPSpecDistance - input.Position.Z * 1.5,
                TPSpecMinDistance, TPSpecMaxDistance
            )
        end
    end))

    tpSpecTrackConnection(Players.PlayerAdded:Connect(function(player)
        TPSpecRPcache[player] = nil
        task.wait(0.2)
        if tpSpecPanel and tpSpecPanel.Parent then
            tpSpecRefresh()
        end
    end))

    tpSpecTrackConnection(Players.PlayerRemoving:Connect(function(player)
        TPSpecRPcache[player] = nil
        TPSpecPlayerButtons[player] = nil
        if player == TPSpecSelectedPlayer then
            if TPSpecEnabled then tpSpecStop() end
            TPSpecSelectedPlayer = nil
            if tpSelected and tpSelected.Parent then
                tpSelected.Text = "Sélection : aucune"
            end
            tpSpecUpdateInfo()
        end
        task.defer(function()
            if tpSpecPanel and tpSpecPanel.Parent then tpSpecRefresh() end
        end)
    end))

    _G.PRISONRP_TP_SPEC_STOP = function()
        if TPSpecEnabled then pcall(tpSpecStop) end
        TPSpecRotating = false
        pcall(function() MovementUserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        for i = #TPSpecLifetimeConnections, 1, -1 do
            local connection = TPSpecLifetimeConnections[i]
            pcall(function() connection:Disconnect() end)
            TPSpecLifetimeConnections[i] = nil
        end
        TPSpecSelectedPlayer = nil
        TPSpecRPcache = {}
    end

    tpSpecRefresh()

    if tpSearchBox then
        tpSpecTrackConnection(tpSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
            if tpSpecPanel and tpSpecPanel.Parent then tpSpecRefresh() end
        end))
    end

    --==============================================================
    -- MONEY VIEW INTÉGRÉ À L'ONGLET ESP
    -- Affiche l'argent détecté au-dessus des autres joueurs.
    -- Aucun RemoteEvent d'achat/modification d'argent n'est utilisé.
    --==============================================================
    -- Affiche l'argent détecté au-dessus des autres joueurs.
    -- Aucun RemoteEvent d'achat/modification d'argent n'est utilisé.
    --==============================================================
    local MoneyViewEnabled = false
    _G.MoneyViewEnabledValue = false
    MoneyViewMaxDistance = 125
    local MoneyViewLabels = {}
    local MoneyViewConnections = {}
    local MoneyViewCharacterConnections = {}
    local MoneyViewUIConnections = {}

    MoneyViewBtn = Instance.new("TextButton")
    MoneyViewBtn.Name = "MoneyViewBtn"
    MoneyViewBtn.Size = UDim2.new(1, 0, 0, 32)
    MoneyViewBtn.Position = UDim2.fromOffset(0, 264)
    MoneyViewBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
    MoneyViewBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    MoneyViewBtn.TextSize = 11
    MoneyViewBtn.Font = Enum.Font.GothamBold
    MoneyViewBtn.Text = "💰 MONEY VIEW : OFF"
    MoneyViewBtn.Parent = espPage

    local MoneyViewCorner = Instance.new("UICorner")
    MoneyViewCorner.CornerRadius = UDim.new(0, 6)
    MoneyViewCorner.Parent = MoneyViewBtn

    local function createMouseSlider(parent, y, labelText, minValue, maxValue, initialValue, onChanged)
        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 22)
        title.Position = UDim2.fromOffset(0, y)
        title.BackgroundTransparency = 1
        title.TextColor3 = Color3.fromRGB(200, 200, 200)
        title.TextSize = 11
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = labelText .. " : " .. tostring(initialValue)
        title.ZIndex = 12
        title.Parent = parent

        local track = Instance.new("Frame")
        track.Size = UDim2.new(1, 0, 0, 8)
        track.Position = UDim2.fromOffset(0, y + 27)
        track.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
        track.BorderSizePixel = 0
        track.ZIndex = 12
        track.Active = true
        track.Parent = parent

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(1, 0)
        trackCorner.Parent = track

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(210, 115, 0)
        fill.BorderSizePixel = 0
        fill.ZIndex = 13
        fill.Parent = track

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(1, 0)
        fillCorner.Parent = fill

        local knob = Instance.new("TextButton")
        knob.Size = UDim2.fromOffset(16, 16)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
        knob.BorderSizePixel = 0
        knob.Text = ""
        knob.AutoButtonColor = false
        knob.ZIndex = 14
        knob.Parent = track

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent = knob

        local dragging = false
        local value = math.clamp(tonumber(initialValue) or minValue, minValue, maxValue)

        local function setValue(newValue, fire)
            value = math.clamp(math.floor(tonumber(newValue) or minValue + 0.5), minValue, maxValue)
            local ratio = (value - minValue) / (maxValue - minValue)
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            knob.Position = UDim2.new(ratio, 0, 0.5, 0)
            title.Text = labelText .. " : " .. tostring(value)
            if fire and onChanged then
                onChanged(value)
            end
        end

        local function updateFromMouse(x)
            local left = track.AbsolutePosition.X
            local width = track.AbsoluteSize.X
            if width <= 0 then return end
            local ratio = math.clamp((x - left) / width, 0, 1)
            setValue(minValue + ratio * (maxValue - minValue), true)
        end

        MoneyViewUIConnections[#MoneyViewUIConnections + 1] = track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                updateFromMouse(input.Position.X)
            end
        end)

        MoneyViewUIConnections[#MoneyViewUIConnections + 1] = knob.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
            end
        end)

        MoneyViewUIConnections[#MoneyViewUIConnections + 1] = MovementUserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateFromMouse(input.Position.X)
            end
        end)

        MoneyViewUIConnections[#MoneyViewUIConnections + 1] = MovementUserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)

        setValue(value, true)
        return {
            Set = function(v) setValue(v, true) end,
            Get = function() return value end,
            Track = track,
            Label = title
        }
    end

    local MoneyViewDistanceSlider = createMouseSlider(
        espPage, 214, "Distance Money View", 10, 1000, MoneyViewMaxDistance,
        function(value)
            MoneyViewMaxDistance = value
            for _, bill in pairs(MoneyViewLabels) do
                bill.MaxDistance = MoneyViewMaxDistance
            end
        end
    )

    local function moneyViewSetDistance(value)
        value = math.clamp(math.floor(tonumber(value) or MoneyViewMaxDistance), 10, 1000)
        MoneyViewMaxDistance = value
        MoneyViewDistanceSlider.Set(value)
        for _, bill in pairs(MoneyViewLabels) do
            bill.MaxDistance = MoneyViewMaxDistance
        end
    end

    _G.PRISONRP_SETTINGS_SET_MONEY_DISTANCE = function(value)
        moneyViewSetDistance(value)
    end

    local function moneyViewRemoveLabel(player)
        if MoneyViewLabels[player] then
            pcall(function() MoneyViewLabels[player]:Destroy() end)
            MoneyViewLabels[player] = nil
        end
    end

    local function moneyViewFindValue(player)
        local exactPaths = {
            {"Stats", "Value"},
            {"leaderstats", "Cash"},
            {"leaderstats", "Money"},
            {"Cash"},
            {"Money"},
        }

        local function readValue(obj)
            if obj and obj:IsA("ValueBase") then
                return obj.Value
            end
            return nil
        end

        for _, path in ipairs(exactPaths) do
            local obj = player
            for _, name in ipairs(path) do
                obj = obj and obj:FindFirstChild(name)
            end
            local value = readValue(obj)
            if value ~= nil then
                return value
            end
        end

        local roots = {
            player:FindFirstChild("Stats"),
            player:FindFirstChild("leaderstats"),
            player
        }

        local names = {
            money = true, cash = true, currency = true,
            coins = true, balance = true, wallet = true,
            value = true
        }

        for _, root in ipairs(roots) do
            if root then
                for _, obj in ipairs(root:GetDescendants()) do
                    if obj:IsA("ValueBase") and names[string.lower(obj.Name)] then
                        return obj.Value
                    end
                end
            end
        end

        return nil
    end

    local function moneyViewCreateLabel(player)
        if MoneyViewLabels[player] then
            return MoneyViewLabels[player]
        end

        local bill = Instance.new("BillboardGui")
        bill.Name = "MoneyView_" .. player.Name
        bill.Size = UDim2.fromOffset(180, 34)
        bill.StudsOffset = Vector3.new(0, 4.5, 0)
        bill.AlwaysOnTop = true
        bill.MaxDistance = MoneyViewMaxDistance
        bill.Parent = ScreenGui

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextStrokeTransparency = 0
        label.TextScaled = false
        label.TextSize = 12
        label.Font = Enum.Font.GothamBold
        label.Text = player.Name .. " | $?"
        label.TextColor3 = Color3.fromRGB(120, 255, 120)
        label.Parent = bill

        MoneyViewLabels[player] = bill
        return bill
    end

    local function moneyViewUpdatePlayer(player)
        if player == LocalPlayer or not MoneyViewEnabled then
            moneyViewRemoveLabel(player)
            return
        end

        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local myCharacter = LocalPlayer.Character
        local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")

        if not root or not myRoot then
            moneyViewRemoveLabel(player)
            return
        end

        if (root.Position - myRoot.Position).Magnitude > MoneyViewMaxDistance then
            moneyViewRemoveLabel(player)
            return
        end

        local value = moneyViewFindValue(player)
        if value == nil then
            moneyViewRemoveLabel(player)
            return
        end

        local bill = moneyViewCreateLabel(player)
        bill.Adornee = root
        bill.Enabled = true
        bill.MaxDistance = MoneyViewMaxDistance

        local label = bill:FindFirstChildOfClass("TextLabel")
        if label then
            label.Text = "$" .. tostring(value)
            label.TextColor3 = Color3.fromRGB(120, 255, 120)
        end
    end

    local function moneyViewSetEnabled(state)
        MoneyViewEnabled = state and true or false
        _G.MoneyViewEnabledValue = MoneyViewEnabled
        MoneyViewBtn.Text = MoneyViewEnabled and "💰 MONEY VIEW : ON" or "💰 MONEY VIEW : OFF"
        MoneyViewBtn.BackgroundColor3 = MoneyViewEnabled and Color3.fromRGB(45, 110, 65) or Color3.fromRGB(45, 48, 62)

        if not MoneyViewEnabled then
            for player in pairs(MoneyViewLabels) do
                moneyViewRemoveLabel(player)
            end
        end
    end

    MoneyViewBtn.MouseButton1Click:Connect(function()
        moneyViewSetEnabled(not MoneyViewEnabled)
    end)

    MoneyViewConnections[#MoneyViewConnections + 1] = Players.PlayerRemoving:Connect(function(player)
        moneyViewRemoveLabel(player)
        local characterConnection = MoneyViewCharacterConnections[player]
        if characterConnection then
            pcall(function() characterConnection:Disconnect() end)
            MoneyViewCharacterConnections[player] = nil
        end
    end)

    MoneyViewConnections[#MoneyViewConnections + 1] = Players.PlayerAdded:Connect(function(player)
        local characterConnection = player.CharacterAdded:Connect(function()
            task.wait(0.2)
            if MoneyViewEnabled then
                moneyViewUpdatePlayer(player)
            end
        end)
        MoneyViewCharacterConnections[player] = characterConnection
    end)

    MoneyViewConnections[#MoneyViewConnections + 1] = RunService.Heartbeat:Connect(function()
        if not MoneyViewEnabled then return end
        for _, player in ipairs(Players:GetPlayers()) do
            moneyViewUpdatePlayer(player)
        end
    end)

    _G.MoneyViewEnabled = function(state)
        moneyViewSetEnabled(state)
    end

    _G.MoneyViewSetRadius = function(radius)
        moneyViewSetDistance(radius)
    end

    _G.PRISONRP_MONEY_VIEW_STOP = function()
        MoneyViewEnabled = false
        for _, connection in ipairs(MoneyViewConnections) do
            pcall(function() connection:Disconnect() end)
        end
        for _, connection in ipairs(MoneyViewUIConnections) do
            pcall(function() connection:Disconnect() end)
        end
        MoneyViewUIConnections = {}
        for player, connection in pairs(MoneyViewCharacterConnections) do
            pcall(function() connection:Disconnect() end)
            MoneyViewCharacterConnections[player] = nil
        end
        for player in pairs(MoneyViewLabels) do
            moneyViewRemoveLabel(player)
        end
        MoneyViewLabels = {}
        MoneyViewConnections = {}
        pcall(function() MoneyViewBtn:Destroy() end)
    end

    -- TP BLACK MARKET + ESP BLACK MARKET sont maintenant dans AUTRES.
    BlackMarketBtn.Parent = autresPage
    BlackMarketBtn.Position = UDim2.fromOffset(145, 126)

    ESPToggleBtn.Parent = autresPage
    ESPToggleBtn.Position = UDim2.fromOffset(145, 174)

    StaffTitle.Parent = espPage
    StaffTitle.Position = UDim2.fromOffset(0, 68)

    StaffESPBtn.Parent = espPage
    StaffESPBtn.Position = UDim2.new(0, 0, 0, 68)

    StaffAutoLeaveBtn.Parent = espPage
    StaffAutoLeaveBtn.Position = UDim2.new(0.51, 0, 0, 68)

    StaffListTitle.Parent = StaffList

    StaffList.Parent = espPage
    StaffList.Position = UDim2.fromOffset(0, 126)
    StaffList.Size = UDim2.new(1, 0, 0, 62)

    StaffHint.Parent = espPage
    StaffHint.Position = UDim2.fromOffset(0, 192)

    local movementTitle = Instance.new("TextLabel")
    movementTitle.Size = UDim2.new(1, 0, 0, 30)
    movementTitle.Position = UDim2.fromOffset(0, 224)
    movementTitle.BackgroundColor3 = Color3.fromRGB(28, 38, 45)
    movementTitle.Text = "⚡ DÉPLACEMENT"
    movementTitle.TextColor3 = Color3.fromRGB(100, 210, 255)
    movementTitle.TextSize = 13
    movementTitle.Font = Enum.Font.GothamBold
    movementTitle.ZIndex = 12
    movementTitle.Parent = movementPage

    local speedSlider = createMouseSlider(
        movementPage, 259, "WalkSpeed", 1, 250, MovementWalkSpeed,
        function(value)
            MovementWalkSpeed = value
            MovementSpeedBox.Text = tostring(value)
            if MovementWalkSpeedEnabled then
                movementApplyWalkSpeed()
            end
        end
    )

    local flySpeedSlider = createMouseSlider(
        movementPage, 329, "Fly Speed", 10, 500, MovementFlySpeed,
        function(value)
            MovementFlySpeed = value
            MovementFlySpeedBox.Text = tostring(value)
        end
    )

    _G.PRISONRP_SETTINGS_SET_WALKSPEED = function(value)
        value = math.clamp(math.floor(tonumber(value) or MovementWalkSpeed), 1, 250)
        MovementWalkSpeed = value
        MovementSpeedBox.Text = tostring(value)
        if speedSlider then speedSlider.Set(value) end
        if MovementWalkSpeedEnabled then
            movementApplyWalkSpeed()
        end
    end

    _G.PRISONRP_SETTINGS_SET_FLYSPEED = function(value)
        value = math.clamp(math.floor(tonumber(value) or MovementFlySpeed), 10, 500)
        MovementFlySpeed = value
        MovementFlySpeedBox.Text = tostring(value)
        if flySpeedSlider then flySpeedSlider.Set(value) end
        -- La boucle Heartbeat lit MovementFlySpeed à chaque frame : aucun
        -- redémarrage n'est nécessaire et cela évite de couper le Noclip ou
        -- de réorienter le personnage lors d'un simple changement de vitesse.
    end

    -- WalkSpeed : carte visuelle + switch unique cliquable.
    speedBtn = Instance.new("TextButton")
    speedBtn.Size = UDim2.new(1, -281, 0, 34)
    speedBtn.Position = UDim2.new(0, 0, 0, 389)
    speedBtn.BackgroundColor3 = Color3.fromRGB(45,48,62)
    speedBtn.Text = ""
    speedBtn.TextColor3 = Color3.fromRGB(255,255,255)
    speedBtn.TextSize = 11
    speedBtn.Font = Enum.Font.GothamBold
    speedBtn.AutoButtonColor = false
    speedBtn.Active = false
    speedBtn.Selectable = false
    speedBtn.ZIndex = 12
    speedBtn.Parent = movementPage

    local speedBtnCorner = Instance.new("UICorner")
    speedBtnCorner.CornerRadius = UDim.new(0, 9)
    speedBtnCorner.Parent = speedBtn

    local speedLabel = Instance.new("TextLabel")
    speedLabel.Size = UDim2.new(1, 0, 1, 0)
    speedLabel.Position = UDim2.fromOffset(0, 0)
    speedLabel.BackgroundTransparency = 1
    speedLabel.Text = "🏃 SPEEDHACK"
    speedLabel.TextColor3 = Color3.fromRGB(235,235,235)
    speedLabel.TextSize = 11
    speedLabel.Font = Enum.Font.GothamBold
    speedLabel.TextXAlignment = Enum.TextXAlignment.Center
    speedLabel.TextYAlignment = Enum.TextYAlignment.Center
    speedLabel.ZIndex = 13
    speedLabel.Parent = speedBtn

    local walkSwitch = Instance.new("TextButton")
    walkSwitch.Name = "WalkSpeedSwitch"
    walkSwitch.Size = UDim2.fromOffset(42, 22)
    walkSwitch.Position = UDim2.new(1, -52, 0.5, -11)
    walkSwitch.BackgroundColor3 = Color3.fromRGB(75, 78, 95)
    walkSwitch.BorderSizePixel = 0
    walkSwitch.AutoButtonColor = false
    walkSwitch.Text = ""
    walkSwitch.Active = true
    walkSwitch.Selectable = true
    walkSwitch.ZIndex = 50
    walkSwitch.Parent = speedBtn

    local walkSwitchCorner = Instance.new("UICorner")
    walkSwitchCorner.CornerRadius = UDim.new(1, 0)
    walkSwitchCorner.Parent = walkSwitch

    local walkKnob = Instance.new("Frame")
    walkKnob.Name = "Knob"
    walkKnob.Size = UDim2.fromOffset(16, 16)
    walkKnob.Position = UDim2.fromOffset(3, 3)
    walkKnob.BackgroundColor3 = Color3.fromRGB(235,235,235)
    walkKnob.BorderSizePixel = 0
    walkKnob.ZIndex = 51
    walkKnob.Active = false
    walkKnob.Parent = walkSwitch

    local walkKnobCorner = Instance.new("UICorner")
    walkKnobCorner.CornerRadius = UDim.new(1, 0)
    walkKnobCorner.Parent = walkKnob

    local TweenService = game:GetService("TweenService")
    local walkSwitchTweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function updateWalkSpeedSwitch(animated)
        local enabled = MovementWalkSpeedEnabled == true
        local targetColor = enabled and Color3.fromRGB(60,200,100) or Color3.fromRGB(75,78,95)
        local targetPosition = enabled and UDim2.new(1,-19,0,3) or UDim2.fromOffset(3,3)

        if animated then
            TweenService:Create(walkSwitch, walkSwitchTweenInfo, {BackgroundColor3 = targetColor}):Play()
            TweenService:Create(walkKnob, walkSwitchTweenInfo, {Position = targetPosition}):Play()
        else
            walkSwitch.BackgroundColor3 = targetColor
            walkKnob.Position = targetPosition
        end
    end

    -- Seul le switch reçoit le clic.
    walkSwitch.MouseButton1Click:Connect(function()
        MovementWalkSpeedEnabled = not MovementWalkSpeedEnabled
        movementApplyWalkSpeed()
        updateWalkSpeedSwitch(true)
    end)

    updateWalkSpeedSwitch(false)

    flyBtn = Instance.new("TextButton")
    flyBtn.Size = UDim2.new(1, -281, 0, 34)
    flyBtn.Position = UDim2.new(0.51, 0, 0, 389)
    flyBtn.BackgroundColor3 = Color3.fromRGB(45,48,62)
    flyBtn.Text = "✈ FLY"
    flyBtn.TextColor3 = Color3.fromRGB(200,200,200)
    flyBtn.TextSize = 11
    flyBtn.Font = Enum.Font.GothamBold
    flyBtn.ZIndex = 12
    flyBtn.Parent = movementPage

    noclipBtn = Instance.new("TextButton")
    noclipBtn.Size = UDim2.new(1, -281, 0, 34)
    noclipBtn.Position = UDim2.new(0, 0, 0, 431)
    noclipBtn.BackgroundColor3 = Color3.fromRGB(45,48,62)
    noclipBtn.Text = "👻 NOCLIP : OFF"
    noclipBtn.TextColor3 = Color3.fromRGB(200,200,200)
    noclipBtn.TextSize = 11
    noclipBtn.Font = Enum.Font.GothamBold
    noclipBtn.ZIndex = 12
    noclipBtn.Parent = movementPage

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, 0, 0, 40)
    hint.Position = UDim2.fromOffset(290, 472)
    hint.BackgroundTransparency = 1
    hint.Text = "Fly : WASD • Espace = monter • Ctrl = descendre"
    hint.TextColor3 = Color3.fromRGB(130,140,155)
    hint.TextSize = 9
    hint.Font = Enum.Font.GothamMedium
    hint.ZIndex = 12
    hint.Parent = movementPage

    -- Les NOUVEAUX boutons utilisent exactement les mêmes variables/fonctions
    -- que les boutons d'origine.

    flyBtn.MouseButton1Click:Connect(function()
        MovementFlyEnabled = not MovementFlyEnabled

        if MovementFlyEnabled then
            movementStartFly()
        else
            movementStopFly()
        end

        flyBtn.Text = "✈ FLY"
        flyBtn.BackgroundColor3 = MovementFlyEnabled
            and Color3.fromRGB(40,150,80)
            or Color3.fromRGB(45,48,62)
    end)

    noclipBtn.MouseButton1Click:Connect(function()
        movementSetNoclip(not MovementNoclipEnabled)

        noclipBtn.Text = MovementNoclipEnabled and "👻 NOCLIP : ON" or "👻 NOCLIP : OFF"
        noclipBtn.BackgroundColor3 = MovementNoclipEnabled
            and Color3.fromRGB(40,150,80)
            or Color3.fromRGB(45,48,62)
    end)

    local function selectPage(page)
        page = math.clamp(math.floor(tonumber(page) or 1), 1, 4)
        _G.PRISONRP_ACTIVE_UI_PAGE = page
        Content.Visible = page == 1
        movementPage.Visible = page == 2
        espPage.Visible = page == 3
        autresPage.Visible = page == 4
        if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
            pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, page)
        end

        -- Les couleurs des onglets sont gérées par gdpRefreshTabs plus bas.
        -- On ne référence pas C ici : cette fonction est déclarée avant le
        -- C local de la nouvelle interface. Cela évite l'erreur au clic qui
        -- empêchait les onglets 2/3/4 de mettre à jour leur couleur.
    end

    farmTab.MouseButton1Click:Connect(function()
        selectPage(1)
    end)

    othersTab.MouseButton1Click:Connect(function()
        selectPage(2)
    end)

    espTab.MouseButton1Click:Connect(function()
        selectPage(3)
    end)

    autresTab.MouseButton1Click:Connect(function()
        selectPage(4)
    end)

    --==============================================================
    -- GDP FRESH UI : nouvelle couche visuelle complète
    -- On repart de la structure fonctionnelle existante, mais toute
    -- l'interface visible est reconstruite : cartes, onglets, switches,
    -- typographie et espacements. Aucune logique de fonctionnalité n'est
    -- remplacée ici.
    --==============================================================
    -- V96 : palette plus propre et plus contrastée.
    local C = {
        bg = Color3.fromRGB(16, 19, 25),
        panel = Color3.fromRGB(22, 27, 35),
        card = Color3.fromRGB(31, 38, 48),
        card2 = Color3.fromRGB(38, 46, 58),
        border = Color3.fromRGB(62, 73, 88),
        accent = Color3.fromRGB(38, 135, 235),
        accent2 = Color3.fromRGB(0, 190, 255),
        white = Color3.fromRGB(255, 255, 255),
        soft = Color3.fromRGB(238, 241, 245),
        muted = Color3.fromRGB(165, 174, 188),
        off = Color3.fromRGB(70, 80, 94),
    }

    MainFrame.Size = UDim2.fromOffset(720, 480)
    HubFullSize = UDim2.fromOffset(720, 480)
    MainFrame.ClipsDescendants = true
    MainFrame.BackgroundColor3 = C.bg
    MainFrame.BorderSizePixel = 0
    local mainStroke = MainFrame:FindFirstChildOfClass('UIStroke')
    if mainStroke then
        mainStroke.Color = C.accent
        mainStroke.Thickness = 1.2
        mainStroke.Transparency = 0.18
    end

    TitleBar.Size = UDim2.new(1, 0, 0, 52)
    TitleBar.BackgroundColor3 = C.panel
    TitleLabel.Text = 'PRISON RP FR GDP'

    local titleAccent = TitleBar:FindFirstChild('V96TitleAccent')
    if not titleAccent then
        titleAccent = Instance.new('Frame')
        titleAccent.Name = 'V96TitleAccent'
        titleAccent.Parent = TitleBar
    end
    titleAccent.Size = UDim2.new(1, -20, 0, 2)
    titleAccent.Position = UDim2.fromOffset(10, 50)
    titleAccent.BackgroundColor3 = C.accent
    titleAccent.BorderSizePixel = 0
    titleAccent.ZIndex = TitleBar.ZIndex + 1

    -- V220 : supprimer tous les anciens badges de version en haut à gauche,
    -- y compris d'éventuels doublons laissés par des rechargements précédents.
    for _, oldVersionLabel in ipairs(MainFrame:GetDescendants()) do
        if oldVersionLabel.Name == 'HubVersionLabel' then
            oldVersionLabel:Destroy()
        end
    end
    TitleLabel.Position = UDim2.fromOffset(14, 11)
    TitleLabel.Size = UDim2.new(0, 220, 0, 34)
    TitleLabel.TextColor3 = C.white
    TitleLabel.Font = Enum.Font.GothamMedium
    TitleLabel.TextSize = 15
    RightShiftLabel.Text = 'RightShift : afficher / masquer'
    RightShiftLabel.TextColor3 = C.muted
    RightShiftLabel.TextSize = 9
    RightShiftLabel.Font = Enum.Font.GothamMedium
    RightShiftLabel.Position = UDim2.fromOffset(145, 0)
    RightShiftLabel.Size = UDim2.fromOffset(250, 52)
    CloseBtn.BackgroundColor3 = C.card
    CloseBtn.TextColor3 = C.white
    CloseBtn.Font = Enum.Font.GothamMedium

    local function textClean(o, size, color)
        if not o then return end
        o.Font = Enum.Font.GothamMedium
        o.TextColor3 = color or C.white
        o.TextSize = size or 11
        o.TextStrokeTransparency = 1
        o.TextTransparency = 0
    end

    local function round(o, r)
        local u = o:FindFirstChildOfClass('UICorner')
        if not u then
            u = Instance.new('UICorner')
            u.Parent = o
        end
        u.CornerRadius = UDim.new(0, r or 8)
    end

    local function border(o, color, transparency)
        local s = o:FindFirstChild('GDPBorder')
        if not s then
            s = Instance.new('UIStroke')
            s.Name = 'GDPBorder'
            s.Parent = o
        end
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Color = color or C.border
        s.Thickness = 1
        s.Transparency = transparency or 0.25
    end

    local function buttonStyle(o, size, bg)
        o.BackgroundColor3 = bg or C.card
        o.BorderSizePixel = 0
        o.AutoButtonColor = false
        textClean(o, size or 11, C.white)
        round(o, 7)
        border(o, C.border, 0.18)
    end

    -- Sidebar rebuilt visually.
    local sidebar = MainFrame:FindFirstChild('OmegaSidebar')
    if sidebar then
        -- La hauteur suit toujours le MainFrame pour ne jamais dépasser
        -- après une réduction puis une restauration de l'interface.
        sidebar.Size = UDim2.new(0, 126, 1, -52)
        sidebar.Position = UDim2.fromOffset(0, 52)
        sidebar.BackgroundColor3 = C.panel
        sidebar.ZIndex = 50
        local line = sidebar:FindFirstChildWhichIsA('Frame')
        if line then
            line.BackgroundColor3 = C.accent
            line.BackgroundTransparency = 0.55
        end
    end

    local function styleTab(tab, active)
        if not tab then return end
        tab.Size = UDim2.new(1, -18, 0, 44)
        tab.BackgroundColor3 = active and C.accent or C.card
        tab.TextColor3 = active and C.white or C.muted
        tab.TextSize = 11
        tab.Font = active and Enum.Font.GothamBold or Enum.Font.GothamMedium
        tab.BorderSizePixel = 0
        round(tab, 8)
        border(tab, active and C.accent2 or C.border, active and 0.05 or 0.30)

        local marker = tab:FindFirstChild('V96ActiveMarker')
        if not marker then
            marker = Instance.new('Frame')
            marker.Name = 'V96ActiveMarker'
            marker.Parent = tab
            marker.Size = UDim2.fromOffset(3, 24)
            marker.Position = UDim2.new(0, 5, 0.5, -12)
            marker.BorderSizePixel = 0
            marker.ZIndex = tab.ZIndex + 1
        end
        marker.BackgroundColor3 = C.accent2
        marker.Visible = active
        round(marker, 2)
    end
    styleTab(farmTab, true)
    styleTab(othersTab, false)
    styleTab(espTab, false)
    styleTab(autresTab, false)
    farmTab.Position = UDim2.fromOffset(9, 16)
    othersTab.Position = UDim2.fromOffset(9, 68)
    espTab.Position = UDim2.fromOffset(9, 120)
    autresTab.Position = UDim2.fromOffset(9, 172)

    Content.Size = UDim2.new(1, 0, 1, 0)
    Content.Position = UDim2.fromOffset(138, 62)
    Content.BackgroundTransparency = 1
    Content.ScrollBarThickness = 4
    Content.ScrollBarImageColor3 = C.accent
    Content.CanvasSize = UDim2.fromOffset(0, 420)

    local function section(parent, y, title)
        local l = Instance.new('TextLabel')
        l.Size = UDim2.new(1, 0, 0, 20)
        l.Position = UDim2.fromOffset(0, y)
        l.BackgroundTransparency = 1
        l.Text = title
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.ZIndex = 20
        textClean(l, 11, C.soft)
        l.Parent = parent

        local line = Instance.new('Frame')
        line.Name = 'V96SectionLine'
        line.Size = UDim2.new(1, 0, 0, 1)
        line.Position = UDim2.fromOffset(0, y + 20)
        line.BackgroundColor3 = C.border
        line.BackgroundTransparency = 0.45
        line.BorderSizePixel = 0
        line.ZIndex = 20
        line.Parent = parent

        return l
    end

    local function prep(o, x, y, w, h, parent)
        o.Parent = parent
        if parent == Content or parent == movementPage then
            -- Two responsive columns: 49% + 49%, with 2% free gap.
            -- This prevents overlap both when the sidebar is collapsed and
            -- when it expands on mouse-over.
            if x == 0 then
                o.Position = UDim2.new(0, 0, 0, y)
                o.Size = UDim2.new(0.49, 0, 0, h)
            else
                o.Position = UDim2.new(0.51, 0, 0, y)
                o.Size = UDim2.new(0.49, 0, 0, h)
            end
        else
            o.Position = UDim2.fromOffset(x, y)
            o.Size = UDim2.new(0, w, 0, h)
        end
        o.ZIndex = 21
        buttonStyle(o, 10, C.card)
    end

    -- Remove the 3 old Farm separators completely.
    for _, n in ipairs({'Separator1','Separator2','Separator3'}) do
        local o = Content:FindFirstChild(n)
        if o then o:Destroy() end
    end
    if MovementTitle then MovementTitle.Visible = false end
    if MovementSpeedBox then MovementSpeedBox.Visible = false end
    if MovementFlySpeedBox then MovementFlySpeedBox.Visible = false end
    if MovementSpeedBtn then MovementSpeedBtn.Visible = false end
    if MovementFlyBtn then MovementFlyBtn.Visible = false end
    if MovementNoclipBtn then MovementNoclipBtn.Visible = false end
    if MovementHint then MovementHint.Visible = false end

    -- FARM page : Pêche & automatisation compactée, sans espace vide.
    section(Content, 0, 'PÊCHE & AUTOMATISATION')

    -- Statut / prises / dernier poisson en tête de page.
    StatusLabel.Parent=Content; StatusLabel.Position=UDim2.new(0.005,0,0,28); StatusLabel.Size=UDim2.new(0.323,0,0,34); StatusLabel.ZIndex=21
    StatsLabel.Parent=Content; StatsLabel.Position=UDim2.new(0.338,0,0,28); StatsLabel.Size=UDim2.new(0.323,0,0,34); StatsLabel.ZIndex=21
    LastFishLabel.Parent=Content; LastFishLabel.Position=UDim2.new(0.672,0,0,28); LastFishLabel.Size=UDim2.new(0.323,0,0,34); LastFishLabel.ZIndex=21
    for _,o in ipairs({StatusLabel,StatsLabel,LastFishLabel}) do
        o.BackgroundColor3=C.panel
        textClean(o,9,C.white)
        round(o,7)
        border(o,C.border,0.22)
    end
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Center
    StatsLabel.TextXAlignment = Enum.TextXAlignment.Center
    LastFishLabel.TextXAlignment = Enum.TextXAlignment.Center

    prep(ToggleFishBtn, 0, 76, 271, 38, Content)
    prep(RarityBtn, 280, 76, 271, 38, Content)
    prep(TeleportBtn, 0, 124, 271, 34, Content)
    prep(AutoSellBtn, 280, 124, 271, 34, Content)
    prep(SellNowBtn, 0, 166, 271, 34, Content)

    section(Content, 174, 'BESOINS')
    prep(AutoEatDrinkBtn, 0, 202, 271, 38, Content)
    prep(StartBtn, 280, 202, 271, 38, Content)
    -- ============================================================
    -- BESOINS : Nourriture / Boisson
    -- Une seule case fixe par besoin + remplissage horizontal animé.
    -- Le remplissage couvre toute la hauteur de la case.
    -- ============================================================

    local function createNeedBar(name, x, fillColor, emoji, label)
        local box = Instance.new("Frame")
        box.Name = name
        box.Parent = Content
        box.Position = UDim2.new(x == 0 and 0 or 0.51, 0, 0, 250)
        box.Size = UDim2.new(0.49, 0, 0, 38)
        box.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
        box.BorderSizePixel = 0
        box.ZIndex = 20
        round(box, 8)
        border(box)

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Parent = box
        fill.Position = UDim2.fromScale(0, 0)
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = fillColor
        fill.BorderSizePixel = 0
        fill.ZIndex = 21
        round(fill, 8)

        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "Text"
        textLabel.Parent = box
        textLabel.BackgroundTransparency = 1
        textLabel.Position = UDim2.fromScale(0, 0)
        textLabel.Size = UDim2.fromScale(1, 1)
        textLabel.Font = Enum.Font.GothamMedium
        textLabel.TextSize = 11
        textLabel.TextColor3 = C.white
        textLabel.TextStrokeTransparency = 1
        textLabel.TextXAlignment = Enum.TextXAlignment.Center
        textLabel.TextYAlignment = Enum.TextYAlignment.Center
        textLabel.Text = emoji .. " " .. label .. " : ? / 100"
        textLabel.ZIndex = 22

        return box, fill, textLabel
    end

    FoodStatus, FoodFill, FoodText = createNeedBar(
        "FoodNeedBox",
        0,
        Color3.fromRGB(230, 135, 35),
        "🥖",
        "Nourriture"
    )

    DrinkStatus, DrinkFill, DrinkText = createNeedBar(
        "DrinkNeedBox",
        280,
        Color3.fromRGB(45, 125, 235),
        "🥤",
        "Boisson"
    )

    -- Première lecture immédiate pour éviter une case vide au démarrage.
    do
        local initialFood, initialWater = readNeedValues()

        if FoodText then
            FoodText.Text = initialFood ~= nil
                and string.format("🥖 Nourriture : %d / 100", math.floor(initialFood + 0.5))
                or "🥖 Nourriture : ? / 100"
        end

        if DrinkText then
            DrinkText.Text = initialWater ~= nil
                and string.format("🥤 Boisson : %d / 100", math.floor(initialWater + 0.5))
                or "🥤 Boisson : ? / 100"
        end

        if FoodFill and initialFood ~= nil then
            FoodFill.Size = UDim2.new(math.clamp(initialFood / 100, 0, 1), 0, 1, 0)
        end

        if DrinkFill and initialWater ~= nil then
            DrinkFill.Size = UDim2.new(math.clamp(initialWater / 100, 0, 1), 0, 1, 0)
        end
    end

    section(Content, 302, 'MINAGE')
    prep(AutoMineBtn, 0, 330, 271, 42, Content)
    prep(AutoMineSellerBtn, 280, 330, 271, 42, Content)
    AutoMineStatus.Parent = Content; AutoMineStatus.Position = UDim2.new(0,0,0,380); AutoMineStatus.Size=UDim2.new(1,0,0,22); AutoMineStatus.ZIndex=21
    AutoMineStatus.BackgroundTransparency=1; textClean(AutoMineStatus,9,C.muted)

    -- Auto-Pompes est placé dans AUTRES.
    AutoPushupBtn.Parent = autresPage

    --==============================================================
    -- AUTO BRAS DE FER
    -- Détection directe du début de match via ArmWrestlingEvent.
    -- La switch arme la fonction ; la macro ne tourne que pendant que E est maintenue.
    -- Ensuite : une seule touche à la fois, Q -> E -> Q -> E...
    --==============================================================
    if type(_G.PRISONRP_STOP_AUTO_ARM_WRESTLE) == "function" then
        pcall(_G.PRISONRP_STOP_AUTO_ARM_WRESTLE)
    end

    local AutoArmWrestleState = {
        Btn = nil,
        Enabled = false,
        Running = false,
        WarningShown = false,
        KeySender = nil,
        MatchActive = false,
        NextKey = "Q",
        StartAt = 0,
        MatchConnection = nil,
    }
    _G.PRISONRP_AUTO_ARM_WRESTLE_STATE = AutoArmWrestleState

    do
        local vim = game:GetService("VirtualInputManager")
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
        local armEvent = remotes and remotes:FindFirstChild("ArmWrestlingEvent")

        local function tapWithExecutor(keyName, keyCodeNumber)
            if type(keytap) == "function" then
                local ok = pcall(keytap, keyCodeNumber)
                if ok then return true end
                ok = pcall(keytap, string.lower(keyName))
                if ok then return true end
            end

            if type(keypress) == "function" and type(keyrelease) == "function" then
                local ok = pcall(function()
                    keypress(keyCodeNumber)
                    keyrelease(keyCodeNumber)
                end)
                if ok then return true end
            end

            if vim and type(vim.SendKeyEvent) == "function" then
                local enumKey = (keyName == "Q") and Enum.KeyCode.Q or Enum.KeyCode.E
                local ok = pcall(function()
                    vim:SendKeyEvent(true, enumKey, false, game)
                    vim:SendKeyEvent(false, enumKey, false, game)
                end)
                if ok then return true end
            end

            return false
        end

        AutoArmWrestleState.KeySender = function(keyName)
            return tapWithExecutor(keyName, keyName == "Q" and 0x51 or 0x45)
        end

        -- Le jeu envoie BeginMatch lorsque le mini-jeu démarre.
        -- On utilise cet événement comme déclencheur fiable.
        if armEvent then
            AutoArmWrestleState.MatchConnection = armEvent.OnClientEvent:Connect(function(action)
                if type(action) ~= "string" then return end

                if action == "BeginMatch" then
                    AutoArmWrestleState.MatchActive = true
                    AutoArmWrestleState.NextKey = "Q"
                    AutoArmWrestleState.StartAt = os.clock() + 0.01
                    AutoArmWrestleState.WarningShown = false
                    return
                end

                local lower = string.lower(action)
                if string.find(lower, "end")
                    or string.find(lower, "win")
                    or string.find(lower, "lose")
                    or string.find(lower, "loss")
                    or string.find(lower, "cancel")
                    or string.find(lower, "quit") then
                    AutoArmWrestleState.MatchActive = false
                    AutoArmWrestleState.NextKey = "Q"
                    AutoArmWrestleState.StartAt = 0
                end
            end)
        end
    end

    local function autoArmGetGui()
        local player = game:GetService("Players").LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        local staticGui = playerGui and playerGui:FindFirstChild("StaticGui")
        return staticGui and staticGui:FindFirstChild("ArmWrestling")
    end

    local function autoArmGuiVisible(armGui)
        if not armGui then return false end
        if armGui:IsA("ScreenGui") then
            return armGui.Enabled
        end
        if armGui:IsA("GuiObject") then
            return armGui.Visible
        end
        return true
    end

    local function stopAutoArmWrestle()
        AutoArmWrestleState.Enabled = false
        AutoArmWrestleState.Running = false
        AutoArmWrestleState.MatchActive = false
        AutoArmWrestleState.NextKey = "Q"
        AutoArmWrestleState.StartAt = 0
        AutoArmWrestleState.WarningShown = false
    end

    local function startAutoArmWrestle()
        if AutoArmWrestleState.Running then return end
        AutoArmWrestleState.Enabled = true
        AutoArmWrestleState.Running = true

        task.spawn(function()
            while AutoArmWrestleState.Enabled do
                local armGui = autoArmGetGui()
                local guiVisible = autoArmGuiVisible(armGui)

                -- Permet aussi d'activer la switch alors qu'un match est déjà ouvert.
                if guiVisible then
                    AutoArmWrestleState.MatchActive = true
                    if AutoArmWrestleState.StartAt <= 0 then
                        AutoArmWrestleState.StartAt = os.clock() + 0.005
                    end
                end

                if not game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.E) then
                    -- La switch arme la fonction, mais la macro ne tourne que
                    -- tant que la touche E physique est maintenue.
                    task.wait()
                elseif AutoArmWrestleState.MatchActive then
                    if AutoArmWrestleState.StartAt > os.clock() then
                        task.wait()
                    else
                        local key = AutoArmWrestleState.NextKey
                        local sender = AutoArmWrestleState.KeySender
                        local sent = sender and sender(key) or false

                        if sent then
                            AutoArmWrestleState.NextKey = (key == "Q") and "E" or "Q"
                        elseif not AutoArmWrestleState.WarningShown then
                            AutoArmWrestleState.WarningShown = true
                            warn("[Auto Bras de Fer] Impossible d'envoyer " .. tostring(key) .. ".")
                        end

                        -- Une pression à la fois : Q -> E -> Q -> E...
                        task.wait()
                    end
                else
                    task.wait()
                end
            end

            AutoArmWrestleState.Running = false
            AutoArmWrestleState.MatchActive = false
            AutoArmWrestleState.NextKey = "Q"
            AutoArmWrestleState.StartAt = 0
            AutoArmWrestleState.WarningShown = false
        end)
    end

    _G.PRISONRP_STOP_AUTO_ARM_WRESTLE = stopAutoArmWrestle
    _G.PRISONRP_START_AUTO_ARM_WRESTLE = startAutoArmWrestle
    _G.PRISONRP_AUTO_ARM_WRESTLE_CLEANUP = function()
        stopAutoArmWrestle()
        if AutoArmWrestleState.MatchConnection then
            pcall(function() AutoArmWrestleState.MatchConnection:Disconnect() end)
            AutoArmWrestleState.MatchConnection = nil
        end
    end

    AutoArmWrestleState.Btn = Instance.new("TextButton")
    AutoArmWrestleState.Btn.Name = "AutoArmWrestleBtn"
    AutoArmWrestleState.Btn.Parent = autresPage
    -- Maintenir E après activation de la switch pour lancer la macro.
    AutoArmWrestleState.Btn.Text = "💪 AUTO BRAS DE FER"
    AutoArmWrestleState.Btn.AutoButtonColor = false
    AutoArmWrestleState.Btn.BackgroundColor3 = C.card
    AutoArmWrestleState.Btn.TextColor3 = C.white
    AutoArmWrestleState.Btn.TextSize = 15
    AutoArmWrestleState.Btn.Font = Enum.Font.GothamBold
    AutoArmWrestleState.Btn.TextXAlignment = Enum.TextXAlignment.Center
    AutoArmWrestleState.Btn.TextYAlignment = Enum.TextYAlignment.Center
    AutoArmWrestleState.Btn.BorderSizePixel = 0
    AutoArmWrestleState.Btn.ZIndex = 22
    round(AutoArmWrestleState.Btn, 8)
    border(AutoArmWrestleState.Btn, C.border, 0.25)

    -- Les automatismes utilisent le switch GDP centralisé.
    local function addSwitch(btn, getOn)
        if not btn then return end
        local old = btn:FindFirstChild('GDPSwitch')
        if old then old:Destroy() end
        local track = Instance.new('Frame')
        track.Name='GDPSwitch'
        track.Size=UDim2.fromOffset(42,22)
        track.Position=UDim2.new(1,-52,0.5,-11)
        track.BorderSizePixel=0
        track.ZIndex=btn.ZIndex+1
        track.Parent=btn
        round(track,11)
        local knob=Instance.new('Frame')
        knob.Name='Knob'; knob.Size=UDim2.fromOffset(16,16); knob.Position=UDim2.fromOffset(3,3)
        knob.BorderSizePixel=0; knob.ZIndex=track.ZIndex+1; knob.Parent=track; round(knob,8)
        local TweenService = game:GetService('TweenService')
        local moveInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local colorInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local animating = false
        local function refresh(animated)
            local on = getOn and getOn() or (string.find(string.upper(btn.Text),'ON',1,true) ~= nil)
            local targetPos = on and UDim2.new(1,-19,0,3) or UDim2.fromOffset(3,3)
            local targetColor = on and C.accent or C.off
            if animated then
                if animating then return end
                animating = true
                local move = TweenService:Create(knob, moveInfo, {Position = targetPos})
                local color = TweenService:Create(track, colorInfo, {BackgroundColor3 = targetColor})
                move:Play(); color:Play()
                move.Completed:Connect(function() animating = false end)
            else
                knob.Position = targetPos
                track.BackgroundColor3 = targetColor
            end
            knob.BackgroundColor3 = C.white
            if isAutoFish then
                -- Auto-Fish : carte grise à l'arrêt, verte en fonctionnement.
                btn.BackgroundColor3 = on and Color3.fromRGB(40, 150, 80) or Color3.fromRGB(38, 43, 50)
            else
                btn.BackgroundColor3 = C.card
            end
            btn.TextColor3 = C.white
        end
        btn:GetPropertyChangedSignal('Text'):Connect(function() refresh(true) end)
        refresh(false)
    end

    -- Auto-Fish utilise uniquement le switch GDPCheckbox ci-dessous.
    addSwitch(AutoEatDrinkBtn, function() return AutoEatDrinkEnabled == true end)
    addSwitch(AutoMineBtn, function() return AutoMineRunning == true end)
    addSwitch(AutoSellBtn, function() return _G.AutoSellEnabled == true end)


    -- TP / Spec movement page.
    movementPage.Size = UDim2.new(1,-150,1,-70)
    movementPage.Position = UDim2.fromOffset(138,62)
    local tpPanel = movementPage:FindFirstChild('OmegaTPSpecPanel')
    if tpPanel then
        tpPanel.Position=UDim2.fromOffset(0,0); tpPanel.Size=UDim2.new(1,0,0,238); tpPanel.BackgroundColor3=C.panel
        round(tpPanel,10); border(tpPanel,C.border,0.2)
        local title=tpPanel:FindFirstChild('TextLabel'); if title then textClean(title,12,C.white) end
        local list=tpPanel:FindFirstChild('PlayerList',true); if list then list.ScrollBarImageColor3=C.accent end
    end
    if tpButton then prep(tpButton,8,181,260,28,tpPanel) end
    -- Spec quitte le panneau TP et devient une carte de déplacement identique à WalkSpeed.
    if tpSpecButton then tpSpecButton.Parent=movementPage end

    -- Page DÉPLACEMENT : organisation fixe et sans conflit.
    -- Ligne 1 : WalkSpeed | FLY
    -- Ligne 2 : Noclip   | Spec
    if movementTitle then
        movementTitle.Visible=true
        movementTitle.Position=UDim2.fromOffset(0,224)
        movementTitle.Size=UDim2.new(1,0,0,30)
        movementTitle.Text='⚡ DÉPLACEMENT'
    end

    if speedSlider then
        speedSlider.Label.Visible=true
        speedSlider.Track.Visible=true
        speedSlider.Label.Position=UDim2.fromOffset(0,259)
        speedSlider.Track.Position=UDim2.fromOffset(0,286)
        speedSlider.Track.Size=UDim2.new(1,0,0,8)
        textClean(speedSlider.Label,10,C.white)
    end

    if flySpeedSlider then
        flySpeedSlider.Label.Visible=true
        flySpeedSlider.Track.Visible=true
        flySpeedSlider.Label.Position=UDim2.fromOffset(0,316)
        flySpeedSlider.Track.Position=UDim2.fromOffset(0,344)
        flySpeedSlider.Track.Size=UDim2.new(1,0,0,8)
        textClean(flySpeedSlider.Label,10,C.white)
    end

    --==============================================================
    -- DÉPLACEMENT : nouvelle organisation visuelle claire
    -- 2 colonnes de cartes à gauche + réglages à gauche + panneau
    -- joueurs/spec à droite. Les fonctions existantes sont conservées.
    --==============================================================
    -- V20 : disposition calquée sur la maquette fournie.
    -- Colonne gauche : SPEEDHACK, FLY, NOCLIP, puis FREECAM.
    -- Colonne droite : réglages WalkSpeed/Fly Speed puis panneau TP/SPEC.
    -- NOCLIP est remis dans l'interface avec le même style de carte et de switch.
    if movementTitle then
        movementTitle.Visible = false
        movementTitle.Size = UDim2.fromOffset(0, 0)
    end

    -- En-tête de la page DÉPLACEMENT : titre + petite barre, puis les cartes.
    local movementHeader = movementPage:FindFirstChild('V7MovementHeader')
    if movementHeader then movementHeader:Destroy() end

    movementHeader = Instance.new('TextLabel')
    movementHeader.Name = 'V7MovementHeader'
    movementHeader.Parent = movementPage
    movementHeader.Position = UDim2.fromOffset(0, 0)
    movementHeader.Size = UDim2.new(1, 0, 0, 20)
    movementHeader.BackgroundTransparency = 1
    movementHeader.Text = 'DÉPLACEMENT'
    movementHeader.TextColor3 = C.white
    movementHeader.TextSize = 11
    movementHeader.Font = Enum.Font.GothamBold
    movementHeader.TextXAlignment = Enum.TextXAlignment.Left
    movementHeader.ZIndex = 30

    local movementHeaderLine = Instance.new('Frame')
    movementHeaderLine.Name = 'V7MovementHeaderLine'
    movementHeaderLine.Parent = movementPage
    movementHeaderLine.Position = UDim2.fromOffset(0, 24)
    movementHeaderLine.Size = UDim2.new(1, 0, 0, 1)
    movementHeaderLine.BackgroundColor3 = C.border
    movementHeaderLine.BackgroundTransparency = 0.25
    movementHeaderLine.BorderSizePixel = 0
    movementHeaderLine.ZIndex = 30

    -- Cartes de déplacement à gauche, sous le titre.
    prep(speedBtn, 0, 36, 271, 48, movementPage)
    prep(flyBtn, 280, 36, 271, 48, movementPage)
    if noclipBtn then
        prep(noclipBtn, 0, 90, 271, 48, movementPage)
        noclipBtn.Visible = true
        noclipBtn.Text = '👻 NOCLIP'
    end

    -- Le switch WalkSpeed intégré dans l'ancienne carte reste désactivé :
    -- le switch GDP installé sur speedBtn est le contrôle visible.
    if walkSwitch then
        walkSwitch.Visible = false
    end
    if speedLabel then
        speedLabel.Size = UDim2.new(1, 0, 1, 0)
        speedLabel.Position = UDim2.fromOffset(0, 0)
        speedLabel.TextXAlignment = Enum.TextXAlignment.Center
        speedLabel.TextYAlignment = Enum.TextYAlignment.Center
    end

    -- Réglages à droite, comme sur la maquette.
    if speedSlider and speedSlider.Label and speedSlider.Track then
        speedSlider.Label.Position = UDim2.new(0.51,0,0,36)
        speedSlider.Label.Size = UDim2.new(0.49,0,0,22)
        speedSlider.Track.Position = UDim2.new(0.51,0,0,63)
        speedSlider.Track.Size = UDim2.new(0.49,0,0,8)
        speedSlider.Label.TextColor3 = C.white
        speedSlider.Label.Font = Enum.Font.GothamMedium
    end

    if flySpeedSlider and flySpeedSlider.Label and flySpeedSlider.Track then
        flySpeedSlider.Label.Position = UDim2.new(0.51,0,0,90)
        flySpeedSlider.Label.Size = UDim2.new(0.49,0,0,22)
        flySpeedSlider.Track.Position = UDim2.new(0.51,0,0,117)
        flySpeedSlider.Track.Size = UDim2.new(0.49,0,0,8)
        flySpeedSlider.Label.TextColor3 = C.white
        flySpeedSlider.Label.Font = Enum.Font.GothamMedium
    end

    -- Panneau TP/SPEC à droite, sous les deux réglages.
    if tpSpecPanel then
        tpSpecPanel.Parent = movementPage
        tpSpecPanel.Position = UDim2.new(1, -271, 0, 144)
        tpSpecPanel.Size = UDim2.new(0.49,0,0,292)
        tpSpecPanel.ZIndex = 12
    end

    -- V30 : SPEC au-dessus et TP en dessous, même police et écart uniforme.
    -- Les deux boutons gardent exactement la même taille et sont centrés.
    if tpSpecButton and tpSpecPanel then
        tpSpecButton.Parent = tpSpecPanel
        tpSpecButton.Position = UDim2.fromOffset(6, 211)
        tpSpecButton.Size = UDim2.new(1, -12, 0, 30)
        tpSpecButton.TextXAlignment = Enum.TextXAlignment.Center
        tpSpecButton.TextYAlignment = Enum.TextYAlignment.Center
    end

    if tpButton and tpSpecPanel then
        tpButton.Parent = tpSpecPanel
        tpButton.Position = UDim2.fromOffset(6, 247)
        tpButton.Size = UDim2.new(1, -12, 0, 30)
        tpButton.TextXAlignment = Enum.TextXAlignment.Center
        tpButton.TextYAlignment = Enum.TextYAlignment.Center
    end

    -- La carte INVISIBLE est créée directement dans le layout final.
    if SpecCard then
        SpecCard.Parent = movementPage
        SpecCard.Size = UDim2.new(1, -281, 0, 48)
        SpecCard.Position = UDim2.new(0,0,0,198)
        SpecCard.TextXAlignment = Enum.TextXAlignment.Center
        SpecCard.TextYAlignment = Enum.TextYAlignment.Center
        SpecCard.ZIndex = 22
    end

    if hint then
        hint.Parent = movementPage
        hint.Position = UDim2.new(0.51,0,0,128)
        hint.Size = UDim2.new(1, -281, 0, 28)
        hint.Text = "Fly : WASD • Espace = monter • Ctrl = descendre"
        hint.TextColor3 = C.muted
        hint.TextSize = 9
        hint.Font = Enum.Font.GothamMedium
        hint.TextWrapped = true
        hint.TextXAlignment = Enum.TextXAlignment.Left
        hint.TextYAlignment = Enum.TextYAlignment.Top
        hint.ZIndex = 21
    end

    -- Auto-Pompes est maintenant dans AUTRES.
    section(autresPage, 0, 'AUTRES')
    prep(AutoPushupBtn, 145, 30, 260, 40, autresPage)
    addSwitch(AutoPushupBtn, function() return _G.AutoPushupEnabled == true end)

    -- BLACK MARKET + ESP BLACK MARKET sont maintenant dans AUTRES.
    BlackMarketBtn.Parent = autresPage
    BlackMarketBtn.Position = UDim2.fromOffset(145, 126)
    BlackMarketBtn.Size = UDim2.fromOffset(260, 40)
    BlackMarketBtn.ZIndex = 21

    ESPToggleBtn.Parent = autresPage
    ESPToggleBtn.Position = UDim2.fromOffset(145, 174)
    ESPToggleBtn.Size = UDim2.fromOffset(260, 40)
    ESPToggleBtn.ZIndex = 21

    -- ESP page : disposition demandée.
    -- À gauche : STAFF ESP -> AUTO-LEAVE -> MONEY VIEW -> distance.
    -- À droite : panneau vertical des staffs détectés.
    espPage.Size=UDim2.new(1,-150,1,-70)
    espPage.Position=UDim2.fromOffset(138,62)
    -- Titre de section conservé : ESP & SURVEILLANCE + ligne dessous.
    section(espPage, 0, 'ESP & SURVEILLANCE')

    if StaffESPBtn then StaffESPBtn.Visible = false end

    prep(StaffAutoLeaveBtn,0,84,271,38,espPage)
    addSwitch(StaffAutoLeaveBtn,function() return _G.PRISONRP_STAFF_AUTOLEAVE==true end)

    if MoneyViewBtn then
        MoneyViewBtn.Visible = false
    end

    if MoneyViewDistanceSlider then
        MoneyViewDistanceSlider.Label.Parent=espPage
        MoneyViewDistanceSlider.Label.Position=UDim2.fromOffset(0,176)
        MoneyViewDistanceSlider.Label.Size=UDim2.fromOffset(270,22)
        MoneyViewDistanceSlider.Track.Parent=espPage
        MoneyViewDistanceSlider.Track.Position=UDim2.fromOffset(0,203)
        MoneyViewDistanceSlider.Track.Size=UDim2.fromOffset(270,8)
        textClean(MoneyViewDistanceSlider.Label,10,C.white)
    end

    -- Panneau STAFF DÉTECTER à droite : vertical, et non plus une barre horizontale.
    if StaffListTitle then
        StaffListTitle.Parent = StaffList
        StaffListTitle.Visible = true
        StaffListTitle.Position = UDim2.fromOffset(8, 7)
        StaffListTitle.Size = UDim2.fromOffset(254, 26)
        StaffListTitle.Text = "🛡 STAFF DÉTECTER"
        StaffListTitle.TextXAlignment = Enum.TextXAlignment.Center
        StaffListTitle.TextYAlignment = Enum.TextYAlignment.Center
        textClean(StaffListTitle,10,C.white)
        StaffListTitle.BackgroundColor3 = C.bg
        StaffListTitle.BackgroundTransparency = 0
        round(StaffListTitle,8)
        border(StaffListTitle,C.border,0.35)
    end

    if StaffList then
        StaffList.Parent=espPage
        StaffList.Position = UDim2.fromOffset(280, 38)
        StaffList.Size=UDim2.fromOffset(270,245)
        StaffList.BackgroundColor3=C.panel
        StaffList.TextXAlignment=Enum.TextXAlignment.Left
        StaffList.TextYAlignment=Enum.TextYAlignment.Top
        StaffList.TextWrapped=true
        textClean(StaffList,10,StaffESPColor)
        round(StaffList,8)
        border(StaffList,C.border,0.35)
    end

    if StaffHint then StaffHint.Visible=false end

    -- Final clean typography pass: white, regular, no stroke.
    for _, root in ipairs({MainFrame, Content, movementPage, espPage}) do
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA('TextLabel') or obj:IsA('TextButton') or obj:IsA('TextBox') then
                obj.Font=Enum.Font.GothamMedium
                obj.TextColor3=C.white
                obj.TextStrokeTransparency=1
                obj.TextTransparency=0
            end
        end
    end

    -- START AUTO-FISH + boutons demandés :
    -- même rendu texte : GothamBold, taille 16, centré.
    for _, obj in ipairs({
        ToggleFishBtn,
        RarityBtn,
        TeleportBtn,
        AutoSellBtn,
        SellNowBtn,
    }) do
        if obj then
            obj.Font = Enum.Font.GothamBold
            obj.TextSize = 16
            obj.TextColor3 = C.white
            obj.TextStrokeTransparency = 1
            obj.TextXAlignment = Enum.TextXAlignment.Center
            obj.TextYAlignment = Enum.TextYAlignment.Center
        end
    end

    -- Autres éléments qui gardent le style général.
    for _, obj in ipairs({
        BlackMarketBtn,
        speedBtn,
        FoodText,
        DrinkText,
        StartBtn,
        AutoMineSellerBtn,
    }) do
        if obj then
            obj.Font = Enum.Font.GothamMedium
            obj.TextSize = 16
            obj.TextColor3 = C.white
            obj.TextStrokeTransparency = 1
            obj.TextXAlignment = Enum.TextXAlignment.Center
            obj.TextYAlignment = Enum.TextYAlignment.Center
        end
    end

    -- Make tabs remain the only strong blue UI elements.
    styleTab(farmTab,true); styleTab(othersTab,false); styleTab(espTab,false); styleTab(autresTab,false)


    -- GDP FIX34 : coche seule cliquable
    -- On conserve une référence à chaque rafraîchisseur visuel pour pouvoir
    -- resynchroniser les switches après une restauration complète.
    local GDPRefreshers = {}

    local function gdpCheckbox(btn, getOn, onToggle)
        if not btn then return end

        local old = btn:FindFirstChild("GDPSwitch")
        if old then old:Destroy() end
        local oldBox = btn:FindFirstChild("GDPCheckbox")
        if oldBox then oldBox:Destroy() end

        -- Le reste de la carte est bloqué : seul le switch est cliquable.
        local blocker = btn:FindFirstChild("GDPClickBlocker")
        if not blocker then
            blocker = Instance.new("TextButton")
            blocker.Name = "GDPClickBlocker"
            blocker.Text = ""
            blocker.AutoButtonColor = false
            blocker.BackgroundTransparency = 1
            blocker.BorderSizePixel = 0
            blocker.Size = UDim2.fromScale(1, 1)
            blocker.Position = UDim2.fromScale(0, 0)
            blocker.ZIndex = btn.ZIndex + 1
            blocker.Parent = btn
        end

        -- Ancien style : interrupteur arrondi avec bouton rond qui coulisse
        -- légèrement avec un petit effet de bascule à l'activation.
        local switch = Instance.new("TextButton")
        switch.Name = "GDPCheckbox"
        switch.Size = UDim2.fromOffset(42, 22)
        switch.Position = UDim2.new(1, -52, 0.5, -11)
        switch.Text = ""
        switch.AutoButtonColor = false
        switch.BackgroundColor3 = C.off
        switch.BorderSizePixel = 0
        switch.ZIndex = btn.ZIndex + 3
        switch.Parent = btn
        round(switch, 12)
        border(switch, C.border, 0.18)

        local knob = Instance.new("Frame")
        knob.Name = "Knob"
        knob.Size = UDim2.fromOffset(16, 16)
        knob.Position = UDim2.fromOffset(3, 3)
        knob.BackgroundColor3 = C.white
        knob.BorderSizePixel = 0
        knob.ZIndex = switch.ZIndex + 1
        knob.Parent = switch
        round(knob, 9)

        local TweenService = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        local colorInfo = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        -- On garde les tweens en cours pour pouvoir les annuler proprement.
        -- Cela évite le désynchronisation visuelle quand on clique très vite.
        local activeMoveTween = nil
        local activeColorTween = nil
        local activeKnobTween = nil
        local switchClickLocked = false
        local SWITCH_CLICK_COOLDOWN = 0.22

        local function refresh(animated)
            local on = getOn and getOn() == true or false
            local targetPos = on and UDim2.new(1, -19, 0, 3) or UDim2.fromOffset(3, 3)
            -- État visible et cohérent : gris à l'arrêt, vert en marche.
            -- Le fond de la carte reste neutre pour tous les automatismes.
            local targetColor = on and Color3.fromRGB(40, 150, 80) or C.off
            local knobColor = C.white

            -- Chaque nouvel état prend immédiatement le dessus sur le tween
            -- précédent. Ainsi 10 clics rapides finissent toujours sur le bon état.
            if activeMoveTween then activeMoveTween:Cancel(); activeMoveTween = nil end
            if activeColorTween then activeColorTween:Cancel(); activeColorTween = nil end
            if activeKnobTween then activeKnobTween:Cancel(); activeKnobTween = nil end

            if animated then
                activeMoveTween = TweenService:Create(knob, tweenInfo, {Position = targetPos})
                activeColorTween = TweenService:Create(switch, colorInfo, {BackgroundColor3 = targetColor})
                activeKnobTween = TweenService:Create(knob, colorInfo, {BackgroundColor3 = knobColor})
                activeMoveTween:Play()
                activeColorTween:Play()
                activeKnobTween:Play()
            else
                knob.Position = targetPos
                switch.BackgroundColor3 = targetColor
                knob.BackgroundColor3 = knobColor
            end

            -- Toutes les cartes gardent le même fond, qu'elles soient ON ou OFF.
            -- L'état actif est indiqué par la piste verte et la position du curseur.
            btn.BackgroundColor3 = C.card
            -- Même police/taille que le FLY que tu préfères, pour toutes les cases.
            -- Le switch indique déjà l'état : on retire donc ON/OFF du texte.
            local cleanText = btn.Text
            cleanText = cleanText:gsub(" : ON", "")
            cleanText = cleanText:gsub(" : OFF", "")
            cleanText = cleanText:gsub(": ON", "")
            cleanText = cleanText:gsub(": OFF", "")
            btn.Text = cleanText
            btn.TextColor3 = C.white

            -- STYLE START AUTO-FISH : appliqué aussi aux cases demandées.
            -- Même police, taille, couleur, sans contour et texte centré.
            local startAutoFishStyle = (
                btn == ToggleFishBtn
                or btn == speedBtn
                or btn == flyBtn
                or btn == noclipBtn
                or btn == SpecCard
                or btn == tpSpecButton
                or btn == tpButton
                or btn == AutoPushupBtn
                or btn == BlackMarketBtn
                or btn == ESPToggleBtn
                or btn == StaffAutoLeaveBtn
            )

            if startAutoFishStyle then
                btn.Font = Enum.Font.GothamBold
                btn.TextSize = 15
                btn.TextColor3 = C.white
                btn.TextStrokeTransparency = 1
                btn.TextXAlignment = Enum.TextXAlignment.Center
                btn.TextYAlignment = Enum.TextYAlignment.Center
            else
                btn.Font = Enum.Font.GothamMedium
                btn.TextSize = 16
                btn.TextXAlignment = Enum.TextXAlignment.Center
                btn.TextYAlignment = Enum.TextYAlignment.Center
            end
        end

        switch.Activated:Connect(function()
            -- Anti-double-clic : un clic très rapide ne peut plus lancer deux
            -- changements d'état pendant que le précédent est encore en cours.
            if switchClickLocked then
                return
            end

            switchClickLocked = true

            if onToggle then
                onToggle()
            end

            refresh(true)

            task.delay(SWITCH_CLICK_COOLDOWN, function()
                switchClickLocked = false
            end)
        end)

        -- Ne pas rafraîchir sur chaque changement de texte : plusieurs fonctions
        -- changent leur label pendant le toggle, ce qui cassait l'animation.
        refresh(false)

        -- Exposé uniquement en interne afin de pouvoir resynchroniser
        -- l'affichage après une restauration de paramètres.
        GDPRefreshers[btn] = refresh
    end


    --==============================================================
    -- SPEC / FREECAM STANDALONE
    -- Caméra libre indépendante : F pour basculer, WASD pour bouger,
    -- Espace/Ctrl pour monter/descendre, Shift pour accélérer.
    -- Le personnage reste complètement immobile pendant la SPEC.
    --==============================================================
    local Spec = {
        Enabled = false,
        Armed = false,
        RightMouseHeld = false,
        Keys = {},
        Speed = 45,
        FastSpeed = 80,
        SavedCameraType = nil,
        SavedCameraSubject = nil,
        SavedCameraCFrame = nil,
        SavedMouseBehavior = nil,
        SavedMouseIconEnabled = nil,
        SavedHumanoid = nil,
        SavedRoot = nil,
        SavedWalkSpeed = nil,
        SavedJumpPower = nil,
        SavedJumpHeight = nil,
        SavedAutoRotate = nil,
        SavedAnchored = nil,
        SavedAudioListener = nil,
        CreatedAudioListener = false,
        Yaw = 0,
        Pitch = 0,
        RenderConnection = nil,
        InputBeganConnection = nil,
        InputEndedConnection = nil,
        InputChangedConnection = nil,
        CharacterConnection = nil,
        BlockAction = "PrisonRP_Spec_BlockCharacter",
    }

    local SpecUIS = game:GetService("UserInputService")
    local SpecCAS = game:GetService("ContextActionService")
    local SpecRun = game:GetService("RunService")
    local SpecCamera = workspace.CurrentCamera

    local SpecBlockedKeys = {
        [Enum.KeyCode.W] = true,
        [Enum.KeyCode.A] = true,
        [Enum.KeyCode.S] = true,
        [Enum.KeyCode.D] = true,
        [Enum.KeyCode.Space] = true,
        [Enum.KeyCode.LeftControl] = true,
        [Enum.KeyCode.RightControl] = true,
    }

    local function specBlockCharacterInput(_, inputState, inputObject)
        if not Spec.Enabled then
            return Enum.ContextActionResult.Pass
        end
        if inputObject and SpecBlockedKeys[inputObject.KeyCode] then
            return Enum.ContextActionResult.Sink
        end
        return Enum.ContextActionResult.Pass
    end

    local function specGetCharacter()
        return LocalPlayer and LocalPlayer.Character
    end

    local function specFreezeCharacter()
        local char = specGetCharacter()
        if not char then return end

        local hum = char:FindFirstChildOfClass("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart")

        Spec.SavedHumanoid = hum
        Spec.SavedRoot = root

        if hum then
            Spec.SavedWalkSpeed = hum.WalkSpeed
            Spec.SavedJumpPower = hum.JumpPower
            Spec.SavedJumpHeight = hum.JumpHeight
            Spec.SavedAutoRotate = hum.AutoRotate

            pcall(function() hum.WalkSpeed = 0 end)
            pcall(function() hum.JumpPower = 0 end)
            pcall(function() hum.JumpHeight = 0 end)
            pcall(function() hum.AutoRotate = false end)
        end

        if root then
            Spec.SavedAnchored = root.Anchored
            pcall(function() root.Anchored = true end)
            pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)
            pcall(function() root.AssemblyAngularVelocity = Vector3.zero end)
        end
    end

    local function specUnfreezeCharacter()
        local hum = Spec.SavedHumanoid
        local root = Spec.SavedRoot

        -- FREECAM doit toujours laisser le personnage réellement contrôlable.
        -- Même si une restauration précédente était incomplète, on force la sortie
        -- des états qui peuvent laisser le joueur bloqué après la désactivation.
        if hum and hum.Parent then
            pcall(function() hum.WalkSpeed = Spec.SavedWalkSpeed or 16 end)
            pcall(function() hum.JumpPower = Spec.SavedJumpPower or 50 end)
            pcall(function() hum.JumpHeight = Spec.SavedJumpHeight or 7.2 end)
            pcall(function() hum.AutoRotate = Spec.SavedAutoRotate ~= false end)
            pcall(function() hum.PlatformStand = false end)
            pcall(function() hum.AutoRotate = Spec.SavedAutoRotate ~= false end)
        end

        if root and root.Parent then
            -- Ne jamais laisser l'HumanoidRootPart ancré après FREECAM.
            pcall(function() root.Anchored = false end)
            pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)
            pcall(function() root.AssemblyAngularVelocity = Vector3.zero end)
        end

        Spec.SavedHumanoid = nil
        Spec.SavedRoot = nil
    end

    local function specGetAngles(cf)
        local look = cf.LookVector
        local pitch = math.asin(math.clamp(look.Y, -1, 1))
        local yaw = math.atan2(-look.X, -look.Z)
        return yaw, pitch
    end

    local function specDisconnect(name)
        local connection = Spec[name]
        if connection then
            pcall(function() connection:Disconnect() end)
            Spec[name] = nil
        end
    end

    -- AUDIO FREECAM :
    -- Même principe que le SPEC joueur : s'il existe plusieurs AudioListener,
    -- le listener du personnage local peut continuer à faire entendre les gens
    -- autour du vrai personnage. On n'en garde donc qu'un actif, positionné sur
    -- la caméra Freecam, et on restaure tous les autres à la sortie.
    local SpecAudioListener = nil
    local SpecAudioCreatedListener = false
    local SpecAudioCreatedOutput = false
    local SpecAudioCreatedWire = nil
    local SpecAudioSavedListeners = {}
    local SpecAudioMuteGroup = nil

    local function specFindAudioListener()
        local camera = workspace.CurrentCamera
        if camera then
            local listener = camera:FindFirstChildOfClass("AudioListener")
            if listener then return listener end
        end

        local char = specGetCharacter()
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local listener = root:FindFirstChildOfClass("AudioListener")
            if listener then return listener end
        end

        local soundService = game:GetService("SoundService")
        return soundService:FindFirstChildOfClass("AudioListener")
    end

    local function specRestoreAudio()
        for listener, saved in pairs(SpecAudioSavedListeners) do
            if listener and listener.Parent then
                pcall(function()
                    if saved.PositionType ~= nil then
                        listener.PositionType = saved.PositionType
                    end
                    listener.PositionInstance = saved.PositionInstance
                    listener.AudioInteractionGroup = saved.AudioInteractionGroup or ""
                end)
            end
        end

        pcall(function()
            if SpecAudioCreatedWire and SpecAudioCreatedWire.Parent then
                SpecAudioCreatedWire:Destroy()
            end
        end)
        pcall(function()
            if SpecAudioCreatedListener and SpecAudioListener and SpecAudioListener.Parent then
                SpecAudioListener:Destroy()
            end
        end)
        pcall(function()
            if SpecAudioCreatedOutput and game:GetService("SoundService"):FindFirstChild("PrisonRP_FreecamVoiceOutput") then
                game:GetService("SoundService").PrisonRP_FreecamVoiceOutput:Destroy()
            end
        end)

        SpecAudioListener = nil
        SpecAudioCreatedListener = false
        SpecAudioCreatedOutput = false
        SpecAudioCreatedWire = nil
        SpecAudioSavedListeners = {}
        SpecAudioMuteGroup = nil
    end

    local function specEnsureAudio()
        local camera = workspace.CurrentCamera
        if not camera then return end

        pcall(function()
            local listener = specFindAudioListener()

            if not listener then
                listener = Instance.new("AudioListener")
                listener.Name = "PrisonRP_FreecamVoiceListener"
                listener.Parent = camera
                SpecAudioCreatedListener = true
            end

            if next(SpecAudioSavedListeners) == nil then
                SpecAudioMuteGroup = "PrisonRP_FREECAM_MUTE_" .. tostring(LocalPlayer and LocalPlayer.UserId or 0)

                for _, obj in ipairs(game:GetDescendants()) do
                    if obj:IsA("AudioListener") then
                        local saved = {
                            PositionType = nil,
                            PositionInstance = nil,
                            AudioInteractionGroup = nil,
                        }
                        pcall(function() saved.PositionType = obj.PositionType end)
                        pcall(function() saved.PositionInstance = obj.PositionInstance end)
                        pcall(function() saved.AudioInteractionGroup = obj.AudioInteractionGroup end)
                        SpecAudioSavedListeners[obj] = saved
                    end
                end
            end

            SpecAudioListener = listener

            -- Point d'écoute = caméra Freecam.
            listener.PositionType = Enum.ListenerPositionType.Instance
            listener.PositionInstance = camera

            -- Coupe les autres listeners (notamment celui du personnage local)
            -- sans toucher aux AudioEmitter des joueurs.
            for other, _ in pairs(SpecAudioSavedListeners) do
                if other ~= listener and other.Parent then
                    pcall(function()
                        other.AudioInteractionGroup = SpecAudioMuteGroup
                    end)
                end
            end

            local saved = SpecAudioSavedListeners[listener]
            if saved then
                pcall(function()
                    listener.AudioInteractionGroup = saved.AudioInteractionGroup or ""
                end)
            end

            if SpecAudioCreatedListener then
                local output = game:GetService("SoundService"):FindFirstChildOfClass("AudioDeviceOutput")

                if not output then
                    output = Instance.new("AudioDeviceOutput")
                    output.Name = "PrisonRP_FreecamVoiceOutput"
                    output.Parent = game:GetService("SoundService")
                    SpecAudioCreatedOutput = true
                end

                local wire = Instance.new("Wire")
                wire.Name = "PrisonRP_FreecamVoiceWire"
                wire.SourceInstance = listener
                wire.TargetInstance = output
                wire.Parent = listener
                SpecAudioCreatedWire = wire
            end
        end)
    end

    local function specDisable()
        if not Spec.Enabled then return end
        Spec.Enabled = false

        specDisconnect("RenderConnection")
        specDisconnect("InputBeganConnection")
        specDisconnect("InputEndedConnection")
        specDisconnect("InputChangedConnection")
        specDisconnect("CharacterConnection")

        pcall(function()
            SpecCAS:UnbindAction(Spec.BlockAction)
        end)

        -- Nettoyage des états clavier/mouse AVANT de rendre le personnage.
        Spec.Keys = {}
        Spec.RightMouseHeld = false
        pcall(function() SpecUIS.MouseBehavior = Enum.MouseBehavior.Default end)
        pcall(function() SpecUIS.MouseIconEnabled = true end)

        specUnfreezeCharacter()
        specRestoreAudio()

        SpecCamera = workspace.CurrentCamera
        if SpecCamera then
            pcall(function()
                SpecCamera.CameraType = Spec.SavedCameraType or Enum.CameraType.Custom
                SpecCamera.CameraSubject = Spec.SavedCameraSubject
                if Spec.SavedCameraCFrame then
                    SpecCamera.CFrame = Spec.SavedCameraCFrame
                end
            end)

            -- Roblox peut réappliquer le CameraSubject/état Humanoid une frame plus tard.
            -- On resynchronise une seconde fois au frame suivant pour garantir le retour
            -- au contrôle normal du personnage.
            task.defer(function()
                pcall(function()
                    local char = LocalPlayer and LocalPlayer.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if hum then
                        hum.PlatformStand = false
                        hum.AutoRotate = Spec.SavedAutoRotate ~= false
                        hum.WalkSpeed = Spec.SavedWalkSpeed or 16
                    end
                    if root then
                        root.Anchored = false
                        root.AssemblyLinearVelocity = Vector3.zero
                        root.AssemblyAngularVelocity = Vector3.zero
                    end
                    if workspace.CurrentCamera then
                        workspace.CurrentCamera.CameraType = Spec.SavedCameraType or Enum.CameraType.Custom
                        workspace.CurrentCamera.CameraSubject = hum or Spec.SavedCameraSubject
                    end
                end)
            end)
        end

        Spec.SavedCameraType = nil
        Spec.SavedCameraSubject = nil
        Spec.SavedCameraCFrame = nil
        if Spec.SavedMouseBehavior ~= nil then
            pcall(function() SpecUIS.MouseBehavior = Spec.SavedMouseBehavior end)
        else
            pcall(function() SpecUIS.MouseBehavior = Enum.MouseBehavior.Default end)
        end
        if Spec.SavedMouseIconEnabled ~= nil then
            pcall(function() SpecUIS.MouseIconEnabled = Spec.SavedMouseIconEnabled end)
        end
        Spec.SavedMouseBehavior = nil
        Spec.SavedMouseIconEnabled = nil
        Spec.Keys = {}
    end

    local function specEnable()
        if Spec.Enabled then return end

        SpecCamera = workspace.CurrentCamera
        if not SpecCamera then return end

        Spec.Enabled = true
        Spec.SavedCameraType = SpecCamera.CameraType
        Spec.SavedCameraSubject = SpecCamera.CameraSubject
        Spec.SavedCameraCFrame = SpecCamera.CFrame
        Spec.SavedMouseBehavior = SpecUIS.MouseBehavior
        Spec.SavedMouseIconEnabled = SpecUIS.MouseIconEnabled

        -- La souris reste libre tant que le clic droit n'est pas maintenu.
        pcall(function()
            SpecUIS.MouseBehavior = Enum.MouseBehavior.Default
            SpecUIS.MouseIconEnabled = true
        end)

        Spec.Yaw, Spec.Pitch = specGetAngles(SpecCamera.CFrame)
        Spec.Keys = {}

        specFreezeCharacter()

        pcall(function()
            SpecCAS:BindActionAtPriority(
                Spec.BlockAction,
                specBlockCharacterInput,
                false,
                Enum.ContextActionPriority.High.Value,
                Enum.KeyCode.W,
                Enum.KeyCode.A,
                Enum.KeyCode.S,
                Enum.KeyCode.D,
                Enum.KeyCode.Space,
                Enum.KeyCode.LeftControl,
                Enum.KeyCode.RightControl
            )
        end)

        SpecCamera.CameraType = Enum.CameraType.Scriptable
        specEnsureAudio()

        Spec.InputBeganConnection = SpecUIS.InputBegan:Connect(function(input, processed)
            if not Spec.Enabled then return end
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                Spec.RightMouseHeld = true
                pcall(function()
                    SpecUIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
                    SpecUIS.MouseIconEnabled = true
                end)
                return
            end

            if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
                Spec.Keys.Shift = true
            elseif input.KeyCode ~= Enum.KeyCode.Unknown then
                Spec.Keys[input.KeyCode] = true
            end
        end)

        Spec.InputEndedConnection = SpecUIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                Spec.RightMouseHeld = false
                pcall(function()
                    SpecUIS.MouseBehavior = Enum.MouseBehavior.Default
                    SpecUIS.MouseIconEnabled = true
                end)
                return
            end
            if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
                Spec.Keys.Shift = false
            else
                Spec.Keys[input.KeyCode] = false
            end
        end)

        Spec.InputChangedConnection = SpecUIS.InputChanged:Connect(function(input)
            if not Spec.Enabled then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement and Spec.RightMouseHeld then
                local delta = input.Delta
                Spec.Yaw -= delta.X * 0.0045
                Spec.Pitch = math.clamp(Spec.Pitch - delta.Y * 0.0045, math.rad(-89), math.rad(89))
            end
        end)

        Spec.RenderConnection = SpecRun.RenderStepped:Connect(function(dt)
            if not Spec.Enabled then return end

            SpecCamera = workspace.CurrentCamera
            if not SpecCamera then return end

            local rotation = CFrame.fromEulerAnglesYXZ(Spec.Pitch, Spec.Yaw, 0)
            local direction = Vector3.zero

            if Spec.Keys[Enum.KeyCode.W] then direction += rotation.LookVector end
            if Spec.Keys[Enum.KeyCode.S] then direction -= rotation.LookVector end
            if Spec.Keys[Enum.KeyCode.D] then direction += rotation.RightVector end
            if Spec.Keys[Enum.KeyCode.A] then direction -= rotation.RightVector end
            if Spec.Keys[Enum.KeyCode.Space] then direction += Vector3.yAxis end
            if Spec.Keys[Enum.KeyCode.LeftControl] or Spec.Keys[Enum.KeyCode.RightControl] then
                direction -= Vector3.yAxis
            end

            local speed = Spec.Keys.Shift and Spec.FastSpeed or Spec.Speed
            if direction.Magnitude > 0 then
                direction = direction.Unit
                SpecCamera.CFrame = SpecCamera.CFrame + direction * speed * math.max(dt, 1 / 240)
            end

            SpecCamera.CFrame = CFrame.new(SpecCamera.CFrame.Position) * rotation

            -- Le personnage reste figé même si le jeu essaie de modifier sa vitesse.
            local root = Spec.SavedRoot
            if root and root.Parent then
                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end)

        Spec.CharacterConnection = LocalPlayer.CharacterAdded:Connect(function()
            if Spec.Enabled then
                task.wait(0.2)
                specFreezeCharacter()
            end
        end)
    end

    local function specToggle()
        -- F ne fonctionne que si la carte FREECAM a été activée.
        if not Spec.Armed then return end
        if Spec.Enabled then
            specDisable()
        else
            specEnable()
        end
    end

    local function specSetArmed(value)
        Spec.Armed = value == true
        if not Spec.Armed and Spec.Enabled then
            specDisable()
        end
    end

    --==============================================================
    -- INVISIBLE V4
    -- Intègre le mécanisme original fourni par l'utilisateur tel quel.
    -- Seule l'interface autonome du script est retirée : le switch du Hub
    -- pilote exactement le même état / même moteur.
    --==============================================================
repeat task.wait() until game.Players.LocalPlayer

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Character
local Humanoid
local RootPart

local IsInvisible = false
local BodyParts = {}
local SavedTransparency = {}
local StatusButton

local CycleRunning = false
local DisableQueued = false
local LastRealCFrame = nil
local LastRealCameraOffset = nil

-- Très petit déplacement uniquement pour réveiller la réplication.
-- Il est immédiatement restauré.
local WAKE_DISTANCE = 0.01

--==============================================================
-- CHARACTER
--==============================================================

local function SetupCharacter()
    Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    Humanoid = Character:WaitForChild("Humanoid")
    RootPart = Character:WaitForChild("HumanoidRootPart")

    BodyParts = {}
    SavedTransparency = {}

    for _, obj in ipairs(Character:GetDescendants()) do
        if obj:IsA("BasePart") then
            BodyParts[#BodyParts + 1] = obj
            SavedTransparency[obj] = obj.Transparency
        end
    end

    CycleRunning = false
    DisableQueued = false
    LastRealCFrame = nil
    LastRealCameraOffset = nil
end

local function ApplyVisual()
    for _, part in ipairs(BodyParts) do
        if part and part.Parent then
            local old = SavedTransparency[part]
            if old ~= nil then
                pcall(function()
                    part.Transparency = IsInvisible and 0.5 or old
                end)
            end
        end
    end
end

--==============================================================
-- FORCER LA SYNCHRONISATION DE LA POSITION APRÈS DÉSACTIVATION
--==============================================================

local function ForceVisibleSync()
    if not RootPart or not RootPart.Parent then
        return
    end

    local targetCFrame = LastRealCFrame or RootPart.CFrame
    local targetCameraOffset = LastRealCameraOffset or Vector3.zero

    -- On crée volontairement une variation minuscule de CFrame.
    -- Le but est de provoquer une vraie mise à jour du mouvement/network,
    -- puis de remettre exactement la position réelle.
    local pulseCFrame = targetCFrame * CFrame.new(0, 0, 0.03)

    pcall(function()
        RootPart.CFrame = pulseCFrame
        RootPart.AssemblyLinearVelocity = Vector3.zero
        RootPart.AssemblyAngularVelocity = Vector3.zero
    end)

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.CameraOffset = targetCameraOffset
            Humanoid:Move(Vector3.zero, false)
        end)
    end

    -- Deux étapes de frame pour laisser le moteur enregistrer le pulse.
    RunService.Heartbeat:Wait()

    if not RootPart or not RootPart.Parent then
        return
    end

    pcall(function()
        RootPart.CFrame = targetCFrame
        RootPart.AssemblyLinearVelocity = Vector3.zero
        RootPart.AssemblyAngularVelocity = Vector3.zero
    end)

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.CameraOffset = targetCameraOffset
            Humanoid:Move(Vector3.zero, false)
        end)
    end

    -- Dernière restauration locale pour éviter de garder le CFrame du pulse.
    RunService.RenderStepped:Wait()

    if RootPart and RootPart.Parent then
        pcall(function()
            RootPart.CFrame = targetCFrame
        end)
    end

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.CameraOffset = targetCameraOffset
        end)
    end
end

function RunInvisibleCycle()
    if CycleRunning then
        return
    end

    if not IsInvisible or not RootPart or not RootPart.Parent then
        return
    end

    if not Humanoid or not Humanoid.Parent then
        return
    end

    CycleRunning = true

    local currentCFrame = RootPart.CFrame
    local originalCamOffset = Humanoid.CameraOffset

    -- Position réelle de référence : utilisée pour une désactivation
    -- instantanée même si un cycle est encore en cours.
    LastRealCFrame = currentCFrame
    LastRealCameraOffset = originalCamOffset

    local hiddenCFrame =
        currentCFrame * CFrame.new(0, -200000, 0)

    local hiddenCameraOffset =
        hiddenCFrame:ToObjectSpace(
            CFrame.new(currentCFrame.Position)
        ).Position

    -- Même mécanisme que l'ancien script.
    pcall(function()
        RootPart.CFrame = hiddenCFrame
        Humanoid.CameraOffset = hiddenCameraOffset
    end)

    -- Important : on attend le rendu, comme le script d'origine.
    RunService.RenderStepped:Wait()

    -- TOUJOURS restaurer la position prise au début du cycle.
    -- Cela évite le TP vers une ancienne position.
    if RootPart and RootPart.Parent then
        pcall(function()
            RootPart.CFrame = currentCFrame
        end)
    end

    if Humanoid and Humanoid.Parent then
        pcall(function()
            Humanoid.CameraOffset = originalCamOffset
        end)
    end

    CycleRunning = false

    -- Si l'utilisateur a désactivé pendant le cycle,
    -- la restauration est déjà terminée ici.
    if DisableQueued and not IsInvisible then
        ApplyVisual()

        task.spawn(function()
            ForceVisibleSync()
            DisableQueued = false
        end)
    else
        DisableQueued = false
    end
end

local connections = {}

-- Initialisation du moteur V4 au chargement du Hub.
-- Sans cela, RootPart/Humanoid restent nil jusqu’au respawn.
SetupCharacter()
ApplyVisual()

-- Le moteur Invisible V4 est désormais piloté uniquement par le switch du Hub.
-- Aucun raccourci clavier G n'est installé.

connections[2] = RunService.Heartbeat:Connect(function()
    if IsInvisible and not CycleRunning then
        RunInvisibleCycle()
    end
end)

--==============================================================
-- RESPAWN
--==============================================================

connections[3] = LocalPlayer.CharacterAdded:Connect(function()
    IsInvisible = false
    CycleRunning = false
    DisableQueued = false

    if StatusButton then
        StatusButton.Text = "Invisible: OFF"
        StatusButton.BackgroundColor3 = Color3.fromRGB(255, 85, 85)
        StatusButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    task.wait(0.25)

    SetupCharacter()
    ApplyVisual()
end)

    -- API pour l'onglet Settings / UNLOAD du Hub.
    -- Le moteur ci-dessus reste inchangé ; ces fonctions ne font que relayer son état.
    _G.PRISONRP_GET_INVISIBLE_STATE = function()
        return IsInvisible == true
    end

    local function setInvisibleStateFromHub(value)
        local targetState = value == true
        if targetState == IsInvisible then
            ApplyVisual()
            return
        end

        IsInvisible = targetState
        ApplyVisual()

        if IsInvisible then
            task.spawn(function()
                if RootPart and RootPart.Parent then
                    local p = RootPart.CFrame
                    pcall(function()
                        RootPart.CFrame = p * CFrame.new(0, 0, WAKE_DISTANCE)
                        RunService.Heartbeat:Wait()
                        if RootPart and RootPart.Parent then
                            RootPart.CFrame = p
                        end
                    end)
                end

                if IsInvisible then
                    RunInvisibleCycle()
                end
            end)
        else
            DisableQueued = true
            ApplyVisual()
            task.spawn(function()
                ForceVisibleSync()
                DisableQueued = false
            end)
        end
    end

    _G.PRISONRP_SET_INVISIBLE_STATE = setInvisibleStateFromHub

    _G.PRISONRP_INVISIBLE_STOP = function()
        IsInvisible = false
        DisableQueued = false
        ApplyVisual()
        for _, c in pairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        _G.PRISONRP_GET_INVISIBLE_STATE = nil
        _G.PRISONRP_SET_INVISIBLE_STATE = nil
    end

    -- Switch du Hub : même dimensions / même style que FREECAM.
    InvisibleCard = Instance.new("TextButton")
    InvisibleCard.Name = "InvisibleCard"
    InvisibleCard.Size = UDim2.new(1, -281, 0, 48)
    InvisibleCard.Position = UDim2.fromOffset(0, 252)
    InvisibleCard.BackgroundColor3 = C.card
    InvisibleCard.Text = "🫥 INVISIBLE"
    InvisibleCard.TextColor3 = C.white
    InvisibleCard.TextSize = 16
    InvisibleCard.Font = Enum.Font.GothamMedium
    InvisibleCard.TextXAlignment = Enum.TextXAlignment.Center
    InvisibleCard.TextYAlignment = Enum.TextYAlignment.Center
    InvisibleCard.AutoButtonColor = false
    InvisibleCard.ZIndex = 22
    InvisibleCard.Parent = movementPage
    round(InvisibleCard, 8)
    border(InvisibleCard, C.border, 0.25)

    gdpCheckbox(InvisibleCard,
        function()
            return IsInvisible == true
        end,
        function()
            setInvisibleStateFromHub(not IsInvisible)
        end
    )

    -- Snapshot séparé : FREECAM et INVISIBLE gardent chacun leur propre état.
    _G.PRISONRP_GET_SPEC_STATE = function()
        return {
            Armed = Spec.Armed == true,
            Enabled = Spec.Enabled == true,
        }
    end
    _G.PRISONRP_SET_SPEC_STATE = function(data)
        if type(data) == "table" and data.Armed ~= nil then
            local want = data.Armed == true
            specSetArmed(want)
            if want and not Spec.Enabled then
                specEnable()
            elseif not want and Spec.Enabled then
                specDisable()
            end
        end
    end
    _G.PRISONRP_SPEC_STOP = function()
        pcall(function()
            if Spec.Enabled then specDisable() end
            specSetArmed(false)
            Spec.Keys = {}
            Spec.RightMouseHeld = false
        end)
    end

    _G.PRISONRP_GET_TPSPEC_STATE = function()
        return { Enabled = TPSpecEnabled == true }
    end
    _G.PRISONRP_SET_TPSPEC_STATE = function(data)
        if type(data) == "table" and data.Enabled ~= nil then
            local want = data.Enabled == true
            if want and not TPSpecEnabled then
                pcall(tpSpecStart)
            elseif not want and TPSpecEnabled then
                pcall(tpSpecStop)
            end
        end
    end

    -- Carte FREECAM en bas à gauche de l'onglet Déplacement.
    SpecCard = Instance.new("TextButton")
    SpecCard.Name = "SpecCard"
    SpecCard.Size = UDim2.new(1, -281, 0, 48)
    SpecCard.Position = UDim2.fromOffset(0, 198)
    SpecCard.BackgroundColor3 = C.card
    SpecCard.Text = "🎥 FREECAM"
    SpecCard.TextColor3 = C.white
    SpecCard.TextSize = 16
    SpecCard.Font = Enum.Font.GothamMedium
    SpecCard.TextXAlignment = Enum.TextXAlignment.Center
    SpecCard.TextYAlignment = Enum.TextYAlignment.Center
    SpecCard.AutoButtonColor = false
    SpecCard.ZIndex = 22
    SpecCard.Parent = movementPage
    round(SpecCard, 8)
    border(SpecCard, C.border, 0.25)

    gdpCheckbox(SpecCard,
        function()
            return Spec.Armed == true
        end,
        function()
            local want = not Spec.Armed
            specSetArmed(want)
            if want then
                specEnable()
            else
                specDisable()
            end
        end
    )

    -- Les boutons suivants gardent leur logique existante, mais seule
    -- la coche déclenche maintenant l'action.
    gdpCheckbox(ToggleFishBtn,
        function() return _G.AutoFishingEnabled == true end,
        function()
            _G.AutoFishingEnabled = not _G.AutoFishingEnabled
            stats.status = _G.AutoFishingEnabled and "Running..." or "Stopped"
            updateUI()
        end
    )

    gdpCheckbox(AutoEatDrinkBtn,
        function() return AutoEatDrinkEnabled == true end,
        function()
            AutoEatDrinkEnabled = not AutoEatDrinkEnabled
            _G.AutoEatDrinkEnabled = AutoEatDrinkEnabled
            updateAutoEatDrinkUI()
            stats.status = AutoEatDrinkEnabled and "Auto Eat / Drink : ON (seuil 50)" or (_G.AutoFishingEnabled and "Running..." or "Stopped")
            updateUI()
        end
    )

    -- Centre le texte du bouton Auto Eat / Drink.
    AutoEatDrinkBtn.TextXAlignment = Enum.TextXAlignment.Center
    AutoEatDrinkBtn.TextYAlignment = Enum.TextYAlignment.Center
    local oldPad = AutoEatDrinkBtn:FindFirstChild("AutoEatDrinkTextPadding")
    if oldPad then oldPad:Destroy() end

    gdpCheckbox(AutoPushupBtn,
        function() return _G.AutoPushupEnabled == true end,
        function()
            if _G.AutoPushupEnabled then
                stopAutoPushup()
            else
                startAutoPushup()
            end
        end
    )

    gdpCheckbox(AutoArmWrestleState.Btn,
        function() return AutoArmWrestleState.Enabled == true end,
        function()
            if AutoArmWrestleState.Enabled then
                stopAutoArmWrestle()
            else
                startAutoArmWrestle()
            end
        end
    )

    gdpCheckbox(AutoMineBtn,
        function() return AutoMineRunning == true end,
        function()
            if AutoMineRunning then
                autoMineStop()
            else
                autoMineStart()
            end
        end
    )

    gdpCheckbox(speedBtn,
        function() return MovementWalkSpeedEnabled == true end,
        function()
            MovementWalkSpeedEnabled = not MovementWalkSpeedEnabled
            movementApplyWalkSpeed()
            MovementSpeedBtn.Text = MovementWalkSpeedEnabled and ("🏃 SPEEDHACK : ON (" .. MovementWalkSpeed .. ")") or "🏃 SPEEDHACK : OFF"
        end
    )

    gdpCheckbox(flyBtn,
        function() return MovementFlyEnabled == true end,
        function()
            MovementFlyEnabled = not MovementFlyEnabled
            if MovementFlyEnabled then movementStartFly() else movementStopFly() end
            MovementFlyBtn.Text = "✈ FLY"
        end
    )

    -- Force l'affichage de l'emoji Fly sur la carte, même après l'installation du switch.
    flyBtn.Text = "✈ FLY"
    flyBtn.Font = Enum.Font.GothamMedium
    flyBtn.TextSize = 16
    flyBtn.TextXAlignment = Enum.TextXAlignment.Center
    flyBtn.TextYAlignment = Enum.TextYAlignment.Center
    flyBtn.TextColor3 = C.white

    -- SPEC V6 : reprendre exactement l'apparence visuelle de la carte FLY.
    -- On conserve la position du SPEC, mais sa carte, son fond et son switch
    -- utilisent les mêmes valeurs visuelles que FLY.
    if SpecCard and flyBtn then
        SpecCard.Size = UDim2.new(1, -281, 0, 48)
        SpecCard.Position = UDim2.fromOffset(0, 198)
        SpecCard.BackgroundColor3 = flyBtn.BackgroundColor3
        SpecCard.BackgroundTransparency = flyBtn.BackgroundTransparency
        SpecCard.BorderSizePixel = flyBtn.BorderSizePixel
        SpecCard.TextColor3 = flyBtn.TextColor3
        SpecCard.TextSize = flyBtn.TextSize
        SpecCard.Font = flyBtn.Font
        SpecCard.TextXAlignment = flyBtn.TextXAlignment
        SpecCard.TextYAlignment = flyBtn.TextYAlignment
        SpecCard.AutoButtonColor = flyBtn.AutoButtonColor
        SpecCard.ZIndex = 100

        -- Supprime toute ancienne copie éventuelle du switch SPEC.
        local specSwitches = {}
        for _, child in ipairs(SpecCard:GetChildren()) do
            if child.Name == "GDPCheckbox" or child.Name == "GDPSwitch" or child.Name == "WalkSpeedSwitch" then
                table.insert(specSwitches, child)
            end
        end
        -- Le gdpCheckbox vient d'être installé sur SpecCard : on garde uniquement
        -- son switch officiel et on supprime les éventuels doublons.
        local officialSpecSwitch = SpecCard:FindFirstChild("GDPCheckbox")
        local kept = false
        for _, child in ipairs(specSwitches) do
            if child ~= officialSpecSwitch then
                pcall(function() child:Destroy() end)
            elseif not kept then
                kept = true
            end
        end

        local flySwitch = flyBtn:FindFirstChild("GDPCheckbox")
        if officialSpecSwitch and flySwitch then
            officialSpecSwitch.Size = flySwitch.Size
            officialSpecSwitch.Position = flySwitch.Position
            officialSpecSwitch.BackgroundColor3 = flySwitch.BackgroundColor3
            officialSpecSwitch.BackgroundTransparency = flySwitch.BackgroundTransparency
            officialSpecSwitch.BorderSizePixel = flySwitch.BorderSizePixel
            officialSpecSwitch.ZIndex = flyBtn.ZIndex + 3

            local specKnob = officialSpecSwitch:FindFirstChild("Knob")
            local flyKnob = flySwitch:FindFirstChild("Knob")
            if specKnob and flyKnob then
                specKnob.Size = flyKnob.Size
                specKnob.BackgroundColor3 = flyKnob.BackgroundColor3
                specKnob.BackgroundTransparency = flyKnob.BackgroundTransparency
                specKnob.BorderSizePixel = flyKnob.BorderSizePixel
            end
        end
    end

    -- SPEEDHACK : copie EXACTEMENT la typographie finale de FLY.
    -- Seul le texte change : FLY -> SPEEDHACK.
    speedLabel.Text = "🏃 SPEEDHACK"
    speedLabel.Font = flyBtn.Font
    speedLabel.TextSize = flyBtn.TextSize
    speedLabel.TextXAlignment = flyBtn.TextXAlignment
    speedLabel.TextYAlignment = flyBtn.TextYAlignment
    speedLabel.TextColor3 = flyBtn.TextColor3

    gdpCheckbox(noclipBtn,
        function() return MovementNoclipEnabled == true end,
        function()
            movementSetNoclip(not MovementNoclipEnabled)
            noclipBtn.Text = MovementNoclipEnabled and "👻 NOCLIP : ON" or "👻 NOCLIP : OFF"
        end
    )

    -- V22 : SPEC est une VRAIE COPIE DIRECTE de la carte FLY.
    -- On détruit l’ancienne carte SPEC et on clone FLY, puis on ne change
    -- que le texte/emoji et l’action du switch.
    if tpSpecButton and flyBtn and tpSpecPanel then
        local oldSpecButton = tpSpecButton

        local specClone = flyBtn:Clone()
        specClone.Name = "tpSpecButton"
        specClone.Parent = tpSpecPanel
        specClone.Position = UDim2.fromOffset(6, 181)
        specClone.Size = UDim2.new(1, -12, 0, 27)
        specClone.ZIndex = flyBtn.ZIndex
        specClone.Text = "🎥 SPEC"
        specClone.TextXAlignment = flyBtn.TextXAlignment
        specClone.TextYAlignment = flyBtn.TextYAlignment
        specClone.AutoButtonColor = flyBtn.AutoButtonColor
        specClone.Active = true
        specClone.Selectable = false

        if oldSpecButton and oldSpecButton ~= specClone then
            pcall(function() oldSpecButton:Destroy() end)
        end

        tpSpecButton = specClone

        -- Le switch est celui du clone de FLY.
        tpSpecSwitch = tpSpecButton:FindFirstChild("GDPCheckbox")
        tpSpecKnob = tpSpecSwitch and tpSpecSwitch:FindFirstChild("Knob") or nil

        if tpSpecSwitch then
            tpSpecSwitch.Activated:Connect(function()
                if TPSpecEnabled then
                    tpSpecStop()
                else
                    tpSpecStart()
                end
                task.defer(function()
                    updateTpSpecSwitch(true)
                end)
            end)
            updateTpSpecSwitch(false)
        end
    end

    -- Garantie finale V30 : SPEC en haut, TP en bas, même police et écart uniforme.
    if tpSpecButton and tpSpecPanel then
        tpSpecButton.Parent = tpSpecPanel
        tpSpecButton.Position = UDim2.fromOffset(6, 211)
        tpSpecButton.Size = UDim2.new(1, -12, 0, 30)
        tpSpecButton.TextXAlignment = Enum.TextXAlignment.Center
        tpSpecButton.TextYAlignment = Enum.TextYAlignment.Center
    end
    if tpButton and tpSpecPanel then
        tpButton.Parent = tpSpecPanel
        tpButton.Position = UDim2.fromOffset(6, 247)
        tpButton.Size = UDim2.new(1, -12, 0, 30)
        tpButton.TextXAlignment = Enum.TextXAlignment.Center
        tpButton.TextYAlignment = Enum.TextYAlignment.Center
        -- TP reprend exactement la police et la taille de texte de SPEC.
        if tpSpecButton then
            tpButton.Font = tpSpecButton.Font
            tpButton.TextSize = tpSpecButton.TextSize
        end
    end

    gdpCheckbox(StaffESPBtn,
        function() return _G.PRISONRP_V128_ESP_STAFF_ENABLED == true end,
        function()
            local newState = not (_G.PRISONRP_V128_ESP_STAFF_ENABLED == true)
            _G.PRISONRP_V128_ESP_STAFF_ENABLED = newState

            -- Synchronise aussi le vrai état local du moteur V128.
            if type(_G.PRISONRP_SET_ESP_STATE) == "function" then
                pcall(function()
                    _G.PRISONRP_SET_ESP_STATE({StaffDetection = newState})
                end)
            end

            -- On garde l'ancien moteur uniquement pour la détection / Auto-Leave.
            StaffESPEnabled = false

            if not newState then
                for player in pairs(StaffESPData) do
                    destroyStaffESP(player)
                end
            end

            if StaffESPBtn then
                StaffESPBtn.Text = newState
                    and "🛡️ ESP STAFF : ON"
                    or "🛡️ ESP STAFF : OFF"
            end
        end
    )

    gdpCheckbox(StaffAutoLeaveBtn,
        function() return StaffAutoLeaveEnabled == true end,
        function()
            StaffAutoLeaveEnabled = not StaffAutoLeaveEnabled
            StaffAutoLeaveBtn.Text = StaffAutoLeaveEnabled and "🚪 AUTO-LEAVE : ON" or "🚪 AUTO-LEAVE : OFF"
        end
    )

    gdpCheckbox(ESPToggleBtn,
        function() return _G.BlackMarketESP == true end,
        function()
            _G.BlackMarketESP = not _G.BlackMarketESP
            toggleBlackMarketESP()
            updateUI()
        end
    )

    -- Auto-Sell utilise maintenant le même switch sécurisé que les autres
    -- automatismes. Le bouton garde exactement sa logique existante :
    -- seule l'interface de contrôle est uniformisée.
    gdpCheckbox(AutoSellBtn,
        function() return _G.AutoSellEnabled == true end,
        function()
            _G.AutoSellEnabled = not _G.AutoSellEnabled
            if typeof(updateAutoSellUI) == "function" then
                pcall(updateAutoSellUI)
            end
        end
    )

    gdpCheckbox(MoneyViewBtn,
        function() return MoneyViewEnabled == true end,
        function()
            moneyViewSetEnabled(not MoneyViewEnabled)
        end
    )

    -- État des onglets : une seule couleur active à la fois.
    local function gdpRefreshTabs(page)
        local tabs = {
            [1] = farmTab,
            [2] = othersTab,
            [3] = espTab,
            [4] = autresTab,
        }
        for index, tab in pairs(tabs) do
            if tab then
                local active = index == page
                tab.BackgroundColor3 = active and C.accent or C.card
                tab.TextColor3 = active and C.white or C.muted

                -- V98 : l'indicateur suit l'onglet actuellement sélectionné.
                local marker = tab:FindFirstChild("V96ActiveMarker")
                if marker then
                    marker.Visible = active
                    marker.BackgroundColor3 = C.accent2
                end

                local st = tab:FindFirstChild("GDPBorder")
                if st then
                    st.Color = active and C.accent2 or C.border
                    st.Transparency = active and 0.05 or 0.35
                end
            end
        end
    end

    -- On conserve le comportement existant de selectPage et on synchronise
    -- immédiatement son apparence après chaque changement.
    local oldSelectPage = selectPage
    selectPage = function(page)
        oldSelectPage(page)
        gdpRefreshTabs(page)
    end
    gdpRefreshTabs(1)

    -- SUPPRESSION DÉFINITIVE DES ANCIENNES BARRES ÉPAISSES DE FARM.
    -- Certaines étaient créées très tôt dans le script et peuvent avoir
    -- été déplacées/recréées avant le nettoyage visuel. On les retire
    -- directement depuis Content, quel que soit leur emplacement.
    for _, obj in ipairs(Content:GetDescendants()) do
        if obj.Name == "Separator1"
            or obj.Name == "Separator2"
            or obj.Name == "Separator3" then
            obj:Destroy()
        elseif obj:IsA("Frame") then
            local size = obj.Size
            local color = obj.BackgroundColor3
            if size.X.Scale == 1 and size.X.Offset == 0
                and size.Y.Scale == 0 and size.Y.Offset == 2
                and color == Color3.fromRGB(45, 48, 62) then
                obj:Destroy()
            end
        end
    end


    -- FINAL ESP BLACK MARKET STYLE : exactement le même rendu de carte
    -- que les autres cases d'AUTRES (même fond, arrondi et bordure).
    if ESPToggleBtn then
        ESPToggleBtn.BackgroundColor3 = C.card
        ESPToggleBtn.BorderSizePixel = 0
        round(ESPToggleBtn, 7)
        border(ESPToggleBtn, C.border, 0.18)
        ESPToggleBtn.TextColor3 = C.white
        ESPToggleBtn.TextStrokeTransparency = 1
        ESPToggleBtn.TextXAlignment = Enum.TextXAlignment.Center
        ESPToggleBtn.TextYAlignment = Enum.TextYAlignment.Center
    end


    -- =============================================================
    -- V7 FINAL SIDEBAR
    -- On garde 100% des pages/fonctions du V102, mais on remplace
    -- uniquement la navigation par la sidebar du V7.
    -- Les anciens boutons du V102 restent cachés et ne servent plus.
    -- =============================================================

    -- Nettoyage définitif : l’ancienne sidebar Omega n’est plus utilisée.
    -- On la détruit au lieu de simplement la cacher pour éviter toute
    -- superposition ou ancien élément qui pourrait réapparaître après
    -- une réduction/restauration de l’interface.
    local oldV102Sidebar = MainFrame:FindFirstChild("OmegaSidebar")
    if oldV102Sidebar then
        oldV102Sidebar:Destroy()
    end

    -- Format du hub inspiré directement du V7.
    MainFrame.Size = UDim2.fromOffset(770, 515)
    HubFullSize = UDim2.fromOffset(770, 515)

    local V7Body = MainFrame:FindFirstChild("V7Body")
    if V7Body then V7Body:Destroy() end
    V7Body = Instance.new("Frame")
    V7Body.Name = "V7Body"
    V7Body.Parent = MainFrame
    -- V174 : toute l'interface fonctionnelle commence exactement sous la barre du haut (52 px).
    V7Body.Position = UDim2.fromOffset(0, 52)
    V7Body.Size = UDim2.new(1, 0, 1, -52)
    V7Body.BackgroundTransparency = 1
    V7Body.ZIndex = 90

    local V7Sidebar = Instance.new("Frame")
    V7Sidebar.Name = "V7Sidebar"
    V7Sidebar.Parent = V7Body
    V7Sidebar.Position = UDim2.fromOffset(8, 8)
    V7Sidebar.Size = UDim2.fromOffset(43, (V7Body.AbsoluteSize.Y / MainFrameScale.Scale) - 16)
    V7Sidebar.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
    V7Sidebar.BackgroundTransparency = 0.02
    V7Sidebar.BorderSizePixel = 0
    V7Sidebar.ZIndex = 100
    V7Sidebar.ClipsDescendants = false

    local v7Corner = Instance.new("UICorner")
    v7Corner.CornerRadius = UDim.new(0, 6)
    v7Corner.Parent = V7Sidebar

    local v7Stroke = Instance.new("UIStroke")
    v7Stroke.Color = Color3.fromRGB(35, 39, 47)
    v7Stroke.Transparency = 0.55
    v7Stroke.Thickness = 1
    v7Stroke.Parent = V7Sidebar

    local v7Line = Instance.new("Frame")
    v7Line.Parent = V7Sidebar
    v7Line.Position = UDim2.new(1, -1, 0, 4)
    v7Line.Size = UDim2.new(0, 1, 1, -8)
    v7Line.BackgroundColor3 = Color3.fromRGB(31, 34, 42)
    v7Line.BorderSizePixel = 0
    v7Line.ZIndex = 101

    local V7Collapsed = 43
    local V7Expanded = 142
    local v7Expanded = false
    local v7Token = 0
    -- V199 : transition douce au survol, avec annulation automatique du tween précédent
    -- si la souris entre/sort rapidement de la barre.
    local v7ExpandTweenInfo = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    local v7Categories = {
        {"🎣", "FARM"},
        {"🏃", "DÉPLACEMENT"},
        {"👁", "ESP"},
        {"⚙", "AUTRES"},
    }

    local v7Buttons = {}
    v7Selected = v7Selected or 1

    local v7Marker = Instance.new("Frame")
    v7Marker.Parent = V7Sidebar
    v7Marker.Position = UDim2.fromOffset(0, 10)
    v7Marker.Size = UDim2.fromOffset(2, 22)
    v7Marker.BackgroundColor3 = Color3.fromRGB(79, 142, 255)
    v7Marker.BorderSizePixel = 0
    v7Marker.ZIndex = 104

    local v7MarkerCorner = Instance.new("UICorner")
    v7MarkerCorner.CornerRadius = UDim.new(0, 2)
    v7MarkerCorner.Parent = v7Marker

    local v7Glow = Instance.new("Frame")
    v7Glow.Parent = V7Sidebar
    v7Glow.Position = UDim2.fromOffset(0, 10)
    v7Glow.Size = UDim2.fromOffset(2, 22)
    v7Glow.BackgroundColor3 = Color3.fromRGB(79, 142, 255)
    v7Glow.BackgroundTransparency = 0.78
    v7Glow.BorderSizePixel = 0
    v7Glow.ZIndex = 103

    local v7GlowCorner = Instance.new("UICorner")
    v7GlowCorner.CornerRadius = UDim.new(0, 3)
    v7GlowCorner.Parent = v7Glow

    local function v7Tween(obj, info, props)
        pcall(function()
            game:GetService("TweenService"):Create(obj, info, props):Play()
        end)
    end

    local function v7SetExpanded(value)
        if v7Expanded == value then return end
        v7Expanded = value
        v7Token = v7Token + 1

        -- V199 : largeur de la sidebar, boutons et libellés s'animent graduellement.
        -- La largeur des pages est animée dans v7ResizePages ci-dessous.
        local scale = math.max((MainFrameScale and MainFrameScale.Scale) or 1, 0.01)
        local sidebarHeight = math.max(100, (V7Body.AbsoluteSize.Y / scale) - 16)
        v7Tween(V7Sidebar, v7ExpandTweenInfo, {
            Size = UDim2.fromOffset(value and V7Expanded or V7Collapsed, sidebarHeight)
        })

        for _, b in ipairs(v7Buttons) do
            v7Tween(b, v7ExpandTweenInfo, {
                Size = UDim2.fromOffset(value and (V7Expanded - 12) or 31, 27)
            })
            local label = b:FindFirstChild("V7Label")
            if label then
                v7Tween(label, v7ExpandTweenInfo, {TextTransparency = value and 0 or 1})
            end
        end
    end

    local function v7Select(page)
        v7Selected = page
        _G.PRISONRP_ACTIVE_UI_PAGE = page

        -- C'est la vraie fonction de navigation du V102.
        -- On l'appelle directement depuis cette nouvelle sidebar.
        pcall(function() selectPage(page) end)
        if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
            pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, page)
        end

        local b = v7Buttons[page]
        if b then
            v7Tween(v7Marker, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = UDim2.fromOffset(0, b.Position.Y.Offset + 5)
            })
            v7Tween(v7Glow, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = UDim2.fromOffset(0, b.Position.Y.Offset + 5)
            })
        end

        for i, button in ipairs(v7Buttons) do
            local active = i == page
            -- Le fond de l'onglet ne s'affiche que lorsque la sidebar est ouverte.
            -- En mode compact, il reste limité à la zone de l'emoji.
            button.BackgroundTransparency = (v7Expanded and active) and 0.72 or 1
            button.BackgroundColor3 = Color3.fromRGB(25, 29, 37)
            local icon = button:FindFirstChild("V7Icon")
            if icon then
                icon.TextColor3 = active and Color3.fromRGB(132, 165, 230) or Color3.fromRGB(92, 97, 108)
            end
        end
    end

    for i, data in ipairs(v7Categories) do
        local button = Instance.new("TextButton")
        button.Name = "V7Tab_" .. tostring(i)
        button.Parent = V7Sidebar
        button.Position = UDim2.fromOffset(6, 5 + (i - 1) * 31)
        button.Size = UDim2.fromOffset(31, 27)
        button.BackgroundColor3 = Color3.fromRGB(25, 29, 37)
        button.BackgroundTransparency = 1
        button.BorderSizePixel = 0
        button.AutoButtonColor = false
        button.Text = ""
        button.ZIndex = 102

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 4)
        bc.Parent = button

        local icon = Instance.new("TextLabel")
        icon.Name = "V7Icon"
        icon.Parent = button
        icon.Position = UDim2.fromOffset(0, -2)
        icon.Size = UDim2.fromOffset(31, 31)
        icon.BackgroundTransparency = 1
        icon.Text = data[1]
        icon.TextColor3 = Color3.fromRGB(92, 97, 108)
        icon.Font = Enum.Font.GothamBold
        icon.TextSize = 18
        icon.TextXAlignment = Enum.TextXAlignment.Center
        icon.TextYAlignment = Enum.TextYAlignment.Center
        icon.ZIndex = 103

        local label = Instance.new("TextLabel")
        label.Name = "V7Label"
        label.Parent = button
        label.Position = UDim2.fromOffset(36, 0)
        label.Size = UDim2.new(1, -40, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = data[2]
        label.TextColor3 = Color3.fromRGB(116, 121, 132)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextTransparency = 1
        label.ZIndex = 103

        v7Buttons[i] = button

        button.MouseEnter:Connect(function()
            v7Token = v7Token + 1
            v7SetExpanded(true)
        end)

        button.MouseButton1Click:Connect(function()
            v7Select(i)
        end)
    end

    V7Sidebar.MouseEnter:Connect(function()
        v7Token = v7Token + 1
        v7SetExpanded(true)
    end)

    V7Sidebar.MouseLeave:Connect(function()
        local token = v7Token + 1
        v7Token = token
        task.delay(0.12, function()
            if v7Token == token then
                v7SetExpanded(false)
            end
        end)
    end)

    -- Les pages fonctionnelles du V102 occupent maintenant le côté droit.
    Content.Parent = V7Body
    Content.Position = UDim2.fromOffset(57, 8)
    Content.Size = UDim2.new(1, -67, 1, -16)
    Content.ZIndex = 91

    movementPage.Parent = V7Body
    movementPage.Position = UDim2.fromOffset(57, 8)
    movementPage.Size = UDim2.new(1, -67, 1, -16)
    movementPage.ZIndex = 91

    espPage.Parent = V7Body
    espPage.Position = UDim2.fromOffset(57, 8)
    espPage.Size = UDim2.new(1, -67, 1, -16)
    espPage.ZIndex = 91

    autresPage.Parent = V7Body
    autresPage.Position = UDim2.fromOffset(57, 8)
    autresPage.Size = UDim2.new(1, -67, 1, -16)
    autresPage.ZIndex = 91

    -- V196 : layout deterministe. Les pages changent de taille immediatement au lieu
    -- d'utiliser des tweens concurrents, qui pouvaient garder une ancienne largeur
    -- quand le menu etait reduit pendant l'animation.
    local function v7ResizePages(open)
        if not V7Body or not V7Body.Parent then return end
        local scale = math.max((MainFrameScale and MainFrameScale.Scale) or 1, 0.01)
        local bodyW = V7Body.AbsoluteSize.X / scale
        local bodyH = V7Body.AbsoluteSize.Y / scale
        if bodyW <= 0 or bodyH <= 0 then return end

        local x = open and 155 or 57
        local width = math.max(100, bodyW - x - 10)
        local height = math.max(100, bodyH - 16)
        local activePage = tonumber(_G.PRISONRP_ACTIVE_UI_PAGE) or tonumber(v7Selected) or 1
        for i, page in ipairs({Content, movementPage, espPage, autresPage}) do
            if page then
                -- V199 : déplacer et redimensionner les pages avec la barre, pas par à-coups.
                v7Tween(page, v7ExpandTweenInfo, {
                    Position = UDim2.fromOffset(x, 8),
                    Size = UDim2.fromOffset(width, height),
                })
                page.ZIndex = 91
                page.Visible = (i == activePage)
            end
        end
        if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
            pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, activePage)
        end
    end

    local oldV7SetExpanded = v7SetExpanded
    v7SetExpanded = function(value)
        oldV7SetExpanded(value)
        v7ResizePages(value)
    end
    _G.PRISONRP_V7_SET_EXPANDED = function(value)
        pcall(function() v7SetExpanded(value == true) end)
    end

    -- Reflow commun pour les changements de taille et de UIScale.
    -- Il conserve toujours une seule page visible et garde la sidebar sous la barre de titre.
    local function v7ReflowLayout()
        if not V7Body or not V7Body.Parent then return end
        if not HubExpanded then
            V7Body.Visible = false
            return
        end

        local scale = math.max((MainFrameScale and MainFrameScale.Scale) or 1, 0.01)
        V7Body.Visible = true
        V7Body.Position = UDim2.fromOffset(0, 52)
        V7Body.Size = UDim2.new(1, 0, 1, -52)

        local bodyW = V7Body.AbsoluteSize.X / scale
        local bodyH = V7Body.AbsoluteSize.Y / scale
        if bodyW <= 0 or bodyH <= 0 then return end

        local x = v7Expanded and 155 or 57
        local width = math.max(100, bodyW - x - 10)
        local height = math.max(100, bodyH - 16)
        V7Sidebar.Position = UDim2.fromOffset(8, 8)
        V7Sidebar.Size = UDim2.fromOffset(v7Expanded and V7Expanded or V7Collapsed, height)

        local pages = {Content, movementPage, espPage, autresPage}
        local activePage = tonumber(_G.PRISONRP_ACTIVE_UI_PAGE) or tonumber(v7Selected) or 1
        for i, page in ipairs(pages) do
            if page then
                page.Position = UDim2.fromOffset(x, 8)
                page.Size = UDim2.fromOffset(width, height)
                page.ZIndex = 91
                page.Visible = (i == activePage)
            end
        end
        if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
            pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, activePage)
        end
    end

    -- Première page visible et indicateur correctement positionné.
    Content.Visible = true
    movementPage.Visible = false
    espPage.Visible = false
    autresPage.Visible = false
    v7Select(1)

    -- V196 : recalcule tout le layout à chaque redimensionnement.
    -- Le recalcul attend un frame pour laisser AbsoluteSize se stabiliser, afin
    -- d'éviter les anciennes tailles résiduelles et la superposition des pages.
    local v7ReflowQueued = false
    local function queueV7Reflow()
        if v7ReflowQueued then return end
        v7ReflowQueued = true
        task.defer(function()
            RunService.Heartbeat:Wait()
            RunService.Heartbeat:Wait()
            v7ReflowQueued = false
            if not V7Body or not V7Body.Parent then return end
            v7ReflowLayout()
        end)
    end

    MainFrame:GetPropertyChangedSignal("Size"):Connect(queueV7Reflow)
    V7Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueV7Reflow)
    -- Ne pas écouter V7Sidebar.Size ici : pendant le tween de survol, ce signal
    -- relançait un reflow immédiat à chaque image et annulait l'effet progressif.
    if MainFrameScale then
        MainFrameScale:GetPropertyChangedSignal("Scale"):Connect(queueV7Reflow)
    end

    -- =============================================================
    -- FIN V7 FINAL SIDEBAR
    -- =============================================================

    -- V115 : grille FARM corrigée.
    -- IMPORTANT : ne pas mettre toutes les cartes en largeur 100%.
    -- La page utilise une grille responsive inspirée exactement de la capture :
    -- 2 colonnes pour les grosses cartes, 3 colonnes pour TP/SELL.
    local function v108Set(obj, xScale, widthScale, y, h)
        if not obj then return end
        obj.Position = UDim2.new(xScale, 0, 0, y)
        obj.Size = UDim2.new(widthScale, 0, 0, h)
    end

    if Content then
        -- Ligne 1 : AUTO-FISH / RARITY
        v108Set(ToggleFishBtn, 0.005, 0.49, 76, 38)
        v108Set(RarityBtn, 0.505, 0.49, 76, 38)

        -- Ligne 2 : TP SHORE / AUTO-SELL / VENDRE TOUT
        v108Set(TeleportBtn, 0.005, 0.323, 124, 34)
        v108Set(AutoSellBtn, 0.338, 0.323, 124, 34)
        v108Set(SellNowBtn, 0.672, 0.323, 124, 34)

        -- Ligne BESOINS : deux colonnes
        v108Set(AutoEatDrinkBtn, 0.005, 0.49, 202, 38)
        v108Set(StartBtn, 0.505, 0.49, 202, 38)

        -- Barres nourriture / boisson : deux colonnes
        local foodBox = Content:FindFirstChild("FoodNeedBox")
        local drinkBox = Content:FindFirstChild("DrinkNeedBox")
        v108Set(foodBox, 0.005, 0.49, 250, 38)
        v108Set(drinkBox, 0.505, 0.49, 250, 38)

        -- MINAGE : deux colonnes + bouton TP MINE dessous
        v108Set(AutoMineBtn, 0.005, 0.49, 330, 42)
        v108Set(AutoMineSellerBtn, 0.505, 0.49, 330, 42)

        if AutoMineTpMineBtn then
            v108Set(AutoMineTpMineBtn, 0.005, 0.49, 380, 42)
            AutoMineTpMineBtn.Visible = true
            AutoMineTpMineBtn.ZIndex = 22
        end

        if AutoMineStatus then
            AutoMineStatus.Position = UDim2.new(0, 0, 0, 428)
            AutoMineStatus.Size = UDim2.new(1, 0, 0, 20)
            AutoMineStatus.TextSize = 9
            AutoMineStatus.ZIndex = 21
        end
    end

    -- DÉPLACEMENT V115 : 4 cartes empilées, même largeur que SPEC.
    -- Elles s'arrêtent à 49% de la page : aucune carte ne prend toute
    -- la largeur disponible.
    if movementPage then
        speedBtn.Position = UDim2.new(0, 0, 0, 36)
        speedBtn.Size = UDim2.new(1, -281, 0, 48)
        flyBtn.Position = UDim2.new(0, 0, 0, 90)
        flyBtn.Size = UDim2.new(1, -281, 0, 48)
        noclipBtn.Position = UDim2.new(0, 0, 0, 144)
        noclipBtn.Size = UDim2.new(1, -281, 0, 48)

        if InvisibleCard then
            InvisibleCard.Position = UDim2.new(0, 0, 0, 252)
            InvisibleCard.Size = UDim2.new(1, -281, 0, 48)
        end
        if SpecCard then
            SpecCard.Position = UDim2.new(0, 0, 0, 198)
            SpecCard.Size = UDim2.new(1, -281, 0, 48)
        end

        -- Les anciens curseurs séparés ne doivent pas se superposer aux cartes.
        if speedSlider then
            if speedSlider.Label then speedSlider.Label.Visible = false end
            if speedSlider.Track then speedSlider.Track.Visible = false end
        end
        if flySpeedSlider then
            if flySpeedSlider.Label then flySpeedSlider.Label.Visible = false end
            if flySpeedSlider.Track then flySpeedSlider.Track.Visible = false end
        end

        if hint then
            hint.Position = UDim2.new(0, 0, 0, 306)
            hint.Size = UDim2.new(1, -281, 0, 28)
            hint.TextXAlignment = Enum.TextXAlignment.Left
        end
    end

    -- TP / SPEC : le panneau reste à droite et prend exactement sa colonne.
    if tpSpecPanel then
        tpSpecPanel.Position = UDim2.new(1, -271, 0, 144)
        tpSpecPanel.Size = UDim2.fromOffset(271, 292)
    end
    if tpSearchBox and tpSpecPanel then
        tpSearchBox.Position = UDim2.fromOffset(6, 25)
        tpSearchBox.Size = UDim2.new(1, -12, 0, 24)
    end
    if tpListFrame and tpSpecPanel then
        tpListFrame.Position = UDim2.fromOffset(6, 53)
        tpListFrame.Size = UDim2.new(1, -12, 0, 134)
    end
    if tpSelected and tpSpecPanel then
        tpSelected.Position = UDim2.fromOffset(6, 190)
    end

    -- V115 FINAL MOVEMENT LAYOUT
    -- TP/SPEC is fixed to the right; the four movement cards use the
    -- remaining left-side width. Sidebar hover cannot change TP/SPEC size.
    if movementPage then
        if speedBtn then
            speedBtn.Position = UDim2.new(0, 0, 0, 36)
            speedBtn.Size = UDim2.new(1, -281, 0, 48)
        end
        if flyBtn then
            flyBtn.Position = UDim2.new(0, 0, 0, 90)
            flyBtn.Size = UDim2.new(1, -281, 0, 48)
        end
        if noclipBtn then
            noclipBtn.Position = UDim2.new(0, 0, 0, 144)
            noclipBtn.Size = UDim2.new(1, -281, 0, 48)
        end
        if InvisibleCard then
            InvisibleCard.Position = UDim2.new(0, 0, 0, 252)
            InvisibleCard.Size = UDim2.new(1, -281, 0, 48)
        end
        if SpecCard then
            SpecCard.Position = UDim2.new(0, 0, 0, 198)
            SpecCard.Size = UDim2.new(1, -281, 0, 48)
        end
        if tpSpecPanel then
            tpSpecPanel.Position = UDim2.new(1, -271, 0, 144)
            tpSpecPanel.Size = UDim2.fromOffset(271, 292)
        end
    end


    -- V121 FINAL MOVEMENT : texte centré dans les cartes + curseurs à droite
    if movementPage then
        local leftCardWidth = UDim2.new(1, -281, 0, 48)
        local sliderW = UDim2.fromOffset(261, 8)

        if speedBtn then
            speedBtn.Position = UDim2.new(0, 0, 0, 36)
            speedBtn.Size = leftCardWidth
            speedBtn.Text = ""
        end
        if speedLabel then
            speedLabel.Visible = true
            speedLabel.Position = UDim2.fromOffset(0, 0)
            speedLabel.Size = UDim2.new(1, 0, 1, 0)
            speedLabel.Text = "🏃 SPEEDHACK"
            speedLabel.TextXAlignment = Enum.TextXAlignment.Center
            speedLabel.TextYAlignment = Enum.TextYAlignment.Center
            speedLabel.TextTransparency = 0
            speedLabel.ZIndex = 20
        end

        if flyBtn then
            flyBtn.Position = UDim2.new(0, 0, 0, 90)
            flyBtn.Size = leftCardWidth
            flyBtn.Text = "✈ FLY"
            flyBtn.TextXAlignment = Enum.TextXAlignment.Center
            flyBtn.TextYAlignment = Enum.TextYAlignment.Center
            flyBtn.TextTransparency = 0
            flyBtn.ZIndex = 20
            -- V125 : c'est FLY qui reprend exactement la typographie de SPEEDHACK.
            -- On copie la police, la taille, la couleur et les alignements de speedLabel.
            if speedLabel then
                flyBtn.Font = speedLabel.Font
                flyBtn.TextSize = speedLabel.TextSize
                flyBtn.TextColor3 = speedLabel.TextColor3
                flyBtn.TextXAlignment = speedLabel.TextXAlignment
                flyBtn.TextYAlignment = speedLabel.TextYAlignment
            else
                flyBtn.Font = Enum.Font.GothamBold
                flyBtn.TextSize = 11
                flyBtn.TextColor3 = Color3.fromRGB(235,235,235)
            end
            local pad = flyBtn:FindFirstChild("MovementFlyPadding")
            if not pad then
                pad = Instance.new("UIPadding")
                pad.Name = "MovementFlyPadding"
                pad.PaddingLeft = UDim.new(0, 0)
                pad.Parent = flyBtn
            end
        end

        if noclipBtn then
            noclipBtn.Position = UDim2.new(0, 0, 0, 144)
            noclipBtn.Size = leftCardWidth
        end
        if InvisibleCard then
            InvisibleCard.Position = UDim2.new(0, 0, 0, 252)
            InvisibleCard.Size = leftCardWidth
        end
        if SpecCard then
            SpecCard.Position = UDim2.new(0, 0, 0, 198)
            SpecCard.Size = leftCardWidth
        end

        if speedSlider then
            if speedSlider.Label then
                speedSlider.Label.Visible = true
                speedSlider.Label.Position = UDim2.new(1, -271, 0, 38)
                speedSlider.Label.Size = UDim2.fromOffset(261, 20)
                speedSlider.Label.TextXAlignment = Enum.TextXAlignment.Left
                speedSlider.Label.TextYAlignment = Enum.TextYAlignment.Center
                speedSlider.Label.Text = "WalkSpeed : " .. tostring(MovementWalkSpeed)
                speedSlider.Label.ZIndex = 20
            end
            if speedSlider.Track then
                speedSlider.Track.Visible = true
                speedSlider.Track.Position = UDim2.new(1, -271, 0, 64)
                speedSlider.Track.Size = sliderW
                speedSlider.Track.ZIndex = 20
            end
        end

        if flySpeedSlider then
            if flySpeedSlider.Label then
                flySpeedSlider.Label.Visible = true
                flySpeedSlider.Label.Position = UDim2.new(1, -271, 0, 92)
                flySpeedSlider.Label.Size = UDim2.fromOffset(261, 20)
                flySpeedSlider.Label.TextXAlignment = Enum.TextXAlignment.Left
                flySpeedSlider.Label.TextYAlignment = Enum.TextYAlignment.Center
                flySpeedSlider.Label.Text = "FlySpeed : " .. tostring(MovementFlySpeed)
                flySpeedSlider.Label.ZIndex = 20
            end
            if flySpeedSlider.Track then
                flySpeedSlider.Track.Visible = true
                flySpeedSlider.Track.Position = UDim2.new(1, -271, 0, 118)
                flySpeedSlider.Track.Size = sliderW
                flySpeedSlider.Track.ZIndex = 20
            end
        end
    end


    -- V115 FINAL TP/SPEC
    if movementPage and tpSpecPanel then
        tpSpecPanel.Position = UDim2.new(1, -271, 0, 144)
        tpSpecPanel.Size = UDim2.fromOffset(271, 292)
    end

    -- FINAL EMOJI LABELS
    if StartBtn then StartBtn.Text = "🛒 Auto Buy Food" end
    if ToggleFishBtn then ToggleFishBtn.Text = "🎣 START AUTO-FISH" end
    AutoSellBtn.Text = "💰 AUTO-SELL"
    if StaffESPBtn then StaffESPBtn.Text = "🛡️ ESP STAFF" end


    -- ============================================================
    -- V128 : ESP STANDALONE INTÉGRÉ DANS L'ONGLET ESP
    -- Une seule interface : aucune ScreenGui secondaire.
    -- Les fonctions viennent du standalone ESP original.
    -- ============================================================
    task.spawn(function()
        local ESPConfig = {
            -- Tous les 8 ESP principaux sont OFF au lancement.
            ESPEnabled = false,
            NamesEnabled = false,
            GameNameEnabled = false,
            DistanceEnabled = false,
            HealthEnabled = false,
            TracersEnabled = false,
            HighlightEnabled = false,
            BodyStatusEnabled = false,
            StaffDetection = false,

            MaxDistance = 2500,

            PlayerColor = Color3.fromRGB(80, 170, 255),
            StaffColor = Color3.fromRGB(255, 65, 65),
            DeadColor = Color3.fromRGB(120, 120, 120),

            FillTransparency = 0.82,
            OutlineTransparency = 0.05,
        }

        local ESP_GROUP_ID = 304256484
        local ESP_MIN_RANK = 200
        _G.PRISONRP_V128_ESP_STAFF_ENABLED = false

        -- Sécurité : aucun affichage ESP ne doit être actif au démarrage.
        ESPConfig.ESPEnabled = false
        ESPConfig.NamesEnabled = false
        ESPConfig.GameNameEnabled = false
        ESPConfig.DistanceEnabled = false
        ESPConfig.HealthEnabled = false
        ESPConfig.TracersEnabled = false
        ESPConfig.HighlightEnabled = false
        ESPConfig.BodyStatusEnabled = false
        ESPConfig.StaffDetection = (_G.PRISONRP_V128_ESP_STAFF_ENABLED == true)

        -- Zone scrollable dédiée à l'ESP : toutes les cases restent accessibles,
        -- même lorsque la sidebar V7 réduit la largeur de la page.
        local oldESPContent = espPage:FindFirstChild("V128ESPContent")
        if oldESPContent then oldESPContent:Destroy() end

        local ESPContent = Instance.new("ScrollingFrame")
        ESPContent.Name = "V128ESPContent"
        ESPContent.Size = UDim2.new(1, 0, 1, -28)
        ESPContent.Position = UDim2.fromOffset(0, 28)
        ESPContent.BackgroundTransparency = 1
        ESPContent.BorderSizePixel = 0
        ESPContent.ScrollBarThickness = 0
        ESPContent.ScrollBarImageTransparency = 1
        ESPContent.ScrollingEnabled = false
        ESPContent.ScrollBarImageColor3 = Color3.fromRGB(210, 115, 0)
        ESPContent.CanvasSize = UDim2.fromOffset(0, 680)
        ESPContent.ScrollingDirection = Enum.ScrollingDirection.Y
        ESPContent.ZIndex = 95
        ESPContent.Parent = espPage

        local function panel(y, h)
            local f = Instance.new("Frame")
            f.Size = UDim2.new(1, -8, 0, h)
            f.Position = UDim2.fromOffset(4, y)
            f.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
            f.BorderSizePixel = 0
            f.ZIndex = 96
            f.Parent = ESPContent

            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 8)
            c.Parent = f

            local st = Instance.new("UIStroke")
            st.Color = Color3.fromRGB(55, 55, 60)
            st.Transparency = 0.25
            st.Parent = f
            return f
        end

        local function title(parent, text, y)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -16, 0, 25)
            t.Position = UDim2.fromOffset(8, y)
            t.BackgroundTransparency = 1
            t.Text = text
            t.TextColor3 = Color3.fromRGB(245, 248, 255)
            t.TextSize = 12
            t.Font = Enum.Font.GothamBold
            t.TextXAlignment = Enum.TextXAlignment.Left
            t.ZIndex = 98
            t.Parent = parent
            return t
        end

        local espOptions = panel(0, 400)
        title(espOptions, "👁 PRISON RP — ESP JOUEURS", 5)

        local optionControls = {}

        -- TweenService doit être local à ce bloc : les anciens essais
        -- utilisaient une variable déclarée hors de cette portée, ce qui
        -- empêchait toute animation au moment du clic.
        local TweenService = game:GetService("TweenService")

        local function makeIntegratedSwitch(text, y, getter, setter)
            -- La carte est maintenant un Frame : cela permet de donner
            -- un vrai clic indépendant à la case ✓ et au switch.
            local b = Instance.new("Frame")
            local slot = #optionControls
            local col = slot % 2
            local row = math.floor(slot / 2)
            local cardW = 138
            local cardH = 48
            b.Size = UDim2.fromOffset(cardW, cardH)
            b.Position = UDim2.fromOffset(4 + col * 144, 68 + row * 52)
            b.BackgroundColor3 = Color3.fromRGB(34, 40, 51)
            b.BorderSizePixel = 0
            b.ZIndex = 98
            b.Parent = espOptions

            -- Zone de clic générale de la carte. Les boutons spécialisés
            -- ✓ et switch sont au-dessus et interceptent leur propre clic.
            local cardHit = Instance.new("TextButton")
            cardHit.Name = "CardHit"
            cardHit.Size = UDim2.fromScale(1, 1)
            cardHit.Position = UDim2.fromOffset(0, 0)
            cardHit.BackgroundTransparency = 1
            cardHit.BorderSizePixel = 0
            cardHit.Text = ""
            cardHit.AutoButtonColor = false
            cardHit.ZIndex = 98
            cardHit.Parent = b

            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 7)
            c.Parent = b

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(65, 75, 92)
            stroke.Transparency = 0.35
            stroke.Parent = b

            local selected = true

            -- Indicateur visuel uniquement : surtout pas de TextButton ici.
            -- Les anciens TextButton imbriqués provoquaient parfois deux clics
            -- (enfant + carte), ce qui faisait ON -> OFF immédiatement.
            local box = Instance.new("Frame")
            box.Size = UDim2.fromOffset(18, 18)
            box.Position = UDim2.fromOffset(6, 15)
            box.BackgroundColor3 = Color3.fromRGB(52, 59, 72)
            box.BorderSizePixel = 0
            box.Active = false
            box.ZIndex = 100
            box.Parent = b

            local bc = Instance.new("UICorner")
            bc.CornerRadius = UDim.new(0, 6)
            bc.Parent = box

            local check = Instance.new("TextLabel")
            check.Size = UDim2.fromScale(1, 1)
            check.BackgroundTransparency = 1
            check.Text = "✓"
            check.TextColor3 = Color3.fromRGB(255, 255, 255)
            check.TextSize = 14
            check.Font = Enum.Font.GothamBold
            check.ZIndex = 101
            check.Parent = box

            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Position = UDim2.fromOffset(28, 8)
            label.Size = UDim2.fromOffset(68, 32)
            label.Text = text
            label.TextColor3 = Color3.fromRGB(255, 255, 255)
            label.TextSize = 15
            label.Font = Enum.Font.GothamBold
            label.TextStrokeTransparency = 1
            label.TextWrapped = true
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.ZIndex = 99
            label.Parent = b

            local sw = Instance.new("Frame")
            sw.Size = UDim2.fromOffset(34, 18)
            sw.Position = UDim2.fromOffset(98, 15)
            sw.BackgroundColor3 = Color3.fromRGB(70, 76, 88)
            sw.BorderSizePixel = 0
            sw.Active = false
            sw.ZIndex = 100
            sw.Parent = b

            local sc = Instance.new("UICorner")
            sc.CornerRadius = UDim.new(1, 0)
            sc.Parent = sw

            local knob = Instance.new("Frame")
            knob.Size = UDim2.fromOffset(14, 14)
            knob.Position = UDim2.fromOffset(2, 2)
            knob.BackgroundColor3 = Color3.fromRGB(235, 238, 245)
            knob.BorderSizePixel = 0
            knob.Active = false
            knob.ZIndex = 101
            knob.Parent = sw

            local kc = Instance.new("UICorner")
            kc.CornerRadius = UDim.new(1, 0)
            kc.Parent = knob

            -- Animation plus douce et plus progressive. Tout est tweené dans
            -- le même timing pour éviter les états visuels désynchronisés.
            local switchTweenInfo = TweenInfo.new(
                0.24,
                Enum.EasingStyle.Quint,
                Enum.EasingDirection.Out
            )
            local checkTweenInfo = TweenInfo.new(
                0.18,
                Enum.EasingStyle.Sine,
                Enum.EasingDirection.Out
            )

            local runningTweens = {}
            local clickBusy = false

            local function stopTweens()
                for i = #runningTweens, 1, -1 do
                    local tw = runningTweens[i]
                    if tw then
                        pcall(function() tw:Cancel() end)
                    end
                    runningTweens[i] = nil
                end
            end

            local function playTween(instance, info, props)
                local tw = TweenService:Create(instance, info, props)
                runningTweens[#runningTweens + 1] = tw
                tw.Completed:Connect(function()
                    for i = #runningTweens, 1, -1 do
                        if runningTweens[i] == tw then
                            table.remove(runningTweens, i)
                            break
                        end
                    end
                end)
                tw:Play()
            end

            local function refresh(animated)
                local on = getter() == true
                local selectedColor = Color3.fromRGB(35, 125, 75)
                local unselectedColor = Color3.fromRGB(52, 59, 72)
                local targetSwitchColor = on
                    and Color3.fromRGB(40, 150, 80)
                    or Color3.fromRGB(70, 76, 88)
                local targetKnobPosition = on
                    and UDim2.new(1, -16, 0, 2)
                    or UDim2.fromOffset(2, 2)

                stopTweens()
                check.Visible = selected
                if animated then
                    -- Ne pas "snapper" les éléments avant le tween :
                    -- l'animation part ainsi de leur position/couleur actuelles.
                    playTween(sw, switchTweenInfo, {BackgroundColor3 = targetSwitchColor})
                    playTween(knob, switchTweenInfo, {Position = targetKnobPosition})
                    playTween(box, checkTweenInfo, {BackgroundColor3 = selected and selectedColor or unselectedColor})
                else
                    sw.BackgroundColor3 = targetSwitchColor
                    knob.Position = targetKnobPosition
                    box.BackgroundColor3 = selected and selectedColor or unselectedColor
                end
            end

            local function toggleValue()
                -- Très court verrou anti double-déclenchement sans empêcher
                -- les changements rapides normaux.
                if clickBusy then return end
                clickBusy = true
                local ok, current = pcall(getter)
                if not ok then current = false end
                local newState = not (current == true)

                local success = pcall(function()
                    setter(newState)
                end)

                if success then
                    refresh(true)
                else
                    refresh(false)
                end

                task.delay(0.10, function()
                    clickBusy = false
                end)
            end

            -- Clic indépendant sur les trois zones :
            -- • ✓ = sélectionne/désélectionne la fonction pour le bouton maître
            -- • switch = active/désactive réellement la fonction
            -- • reste de la carte = comportement du switch
            local checkHit = Instance.new("TextButton")
            checkHit.Name = "CheckHit"
            checkHit.Size = UDim2.fromOffset(22, 22)
            checkHit.Position = UDim2.fromOffset(4, 13)
            checkHit.BackgroundTransparency = 1
            checkHit.BorderSizePixel = 0
            checkHit.Text = ""
            checkHit.AutoButtonColor = false
            checkHit.ZIndex = 102
            checkHit.Parent = b

            local switchHit = Instance.new("TextButton")
            switchHit.Name = "SwitchHit"
            switchHit.Size = UDim2.fromOffset(38, 22)
            switchHit.Position = UDim2.fromOffset(96, 13)
            switchHit.BackgroundTransparency = 1
            switchHit.BorderSizePixel = 0
            switchHit.Text = ""
            switchHit.AutoButtonColor = false
            switchHit.ZIndex = 102
            switchHit.Parent = b

            checkHit.Activated:Connect(function()
                selected = not selected
                refresh(false)
            end)

            switchHit.Activated:Connect(function()
                toggleValue()
            end)

            cardHit.Activated:Connect(function()
                toggleValue()
            end)

            local control = {
                Name = text,
                setSelected = function(v)
                    selected = v == true
                    refresh(false)
                end,
                isSelected = function() return selected end,
                setValue = setter,
                getValue = getter,
                refresh = refresh,
            }

            table.insert(optionControls, control)
            refresh(false)
            return b
        end

        makeIntegratedSwitch("👁 ESP JOUEURS", 39,
            function() return ESPConfig.ESPEnabled end,
            function(v) ESPConfig.ESPEnabled = v end)

        makeIntegratedSwitch("🏷 NOMS / RP PSEUDO", 83,
            function() return ESPConfig.NamesEnabled end,
            function(v) ESPConfig.NamesEnabled = v end)

        makeIntegratedSwitch("🎮 PSEUDO JEU", 127,
            function() return ESPConfig.GameNameEnabled end,
            function(v) ESPConfig.GameNameEnabled = v end)

        makeIntegratedSwitch("📏 RANGE", 171,
            function() return ESPConfig.DistanceEnabled end,
            function(v) ESPConfig.DistanceEnabled = v end)

        makeIntegratedSwitch("❤️ VIE", 215,
            function() return ESPConfig.HealthEnabled end,
            function(v) ESPConfig.HealthEnabled = v end)

        makeIntegratedSwitch("🎯 TRACERS", 259,
            function() return ESPConfig.TracersEnabled end,
            function(v) ESPConfig.TracersEnabled = v end)

        local StaffDetectionCard = makeIntegratedSwitch("🛡 ESP STAFF", 303,
            function()
                return ESPConfig.StaffDetection == true
            end,
            function(v)
                -- Le setter doit rester léger : makeIntegratedSwitch()
                -- anime déjà la switch juste après l'appel.
                -- L'ancien appel à _G.PRISONRP_SET_ESP_STATE() rafraîchissait
                -- immédiatement toutes les switches et annulait visuellement
                -- le tween de cette switch.
                local newState = (v == true)
                ESPConfig.StaffDetection = newState
                _G.PRISONRP_V128_ESP_STAFF_ENABLED = newState

                if StaffESPBtn then
                    StaffESPBtn.Text = newState
                        and "🛡️ ESP STAFF : ON"
                        or "🛡️ ESP STAFF : OFF"
                end
            end)

        local MoneyViewCard = makeIntegratedSwitch("💰 MONEY VIEW", 347,
            function() return MoneyViewEnabled == true end,
            function(v)
                moneyViewSetEnabled(v)
            end)

        _G.PRISONRP_GET_ESP_STATE = function()
            local selected = {}
            local function packColor(color)
                if typeof(color) ~= "Color3" then return nil end
                return {R=math.floor(color.R*255+0.5), G=math.floor(color.G*255+0.5), B=math.floor(color.B*255+0.5)}
            end
            for _, control in ipairs(optionControls) do
                selected[control.Name] = control.isSelected() == true
            end
            return {
                ESPEnabled = ESPConfig.ESPEnabled == true,
                NamesEnabled = ESPConfig.NamesEnabled == true,
                GameNameEnabled = ESPConfig.GameNameEnabled == true,
                DistanceEnabled = ESPConfig.DistanceEnabled == true,
                HealthEnabled = ESPConfig.HealthEnabled == true,
                TracersEnabled = ESPConfig.TracersEnabled == true,
                HighlightEnabled = ESPConfig.HighlightEnabled == true,
                BodyStatusEnabled = ESPConfig.BodyStatusEnabled == true,
                StaffDetection = ESPConfig.StaffDetection == true,
                MaxDistance = ESPConfig.MaxDistance,
                PlayerColor = packColor(ESPConfig.PlayerColor),
                StaffColor = packColor(ESPConfig.StaffColor),
                DeadColor = packColor(ESPConfig.DeadColor),
                FillTransparency = ESPConfig.FillTransparency,
                OutlineTransparency = ESPConfig.OutlineTransparency,
                Selected = selected,
            }
        end
        _G.PRISONRP_SET_ESP_STATE = function(data)
            if type(data) ~= "table" then return end
            for _, key in ipairs({"ESPEnabled","NamesEnabled","GameNameEnabled","DistanceEnabled","HealthEnabled","TracersEnabled","HighlightEnabled","BodyStatusEnabled","StaffDetection"}) do
                if data[key] ~= nil then ESPConfig[key] = data[key] == true end
            end
            _G.PRISONRP_V128_ESP_STAFF_ENABLED = ESPConfig.StaffDetection == true
            if StaffESPBtn then
                StaffESPBtn.Text = ESPConfig.StaffDetection and "🛡️ ESP STAFF : ON" or "🛡️ ESP STAFF : OFF"
            end
            if tonumber(data.MaxDistance) then
                ESPConfig.MaxDistance = math.clamp(tonumber(data.MaxDistance), 1, 10000)
            end
            if type(data.PlayerColor) == "table" then
                ESPConfig.PlayerColor = Color3.fromRGB(math.clamp(tonumber(data.PlayerColor.R or data.PlayerColor[1]) or 80,0,255), math.clamp(tonumber(data.PlayerColor.G or data.PlayerColor[2]) or 170,0,255), math.clamp(tonumber(data.PlayerColor.B or data.PlayerColor[3]) or 255,0,255))
            end
            if type(data.StaffColor) == "table" then
                ESPConfig.StaffColor = Color3.fromRGB(math.clamp(tonumber(data.StaffColor.R or data.StaffColor[1]) or 255,0,255), math.clamp(tonumber(data.StaffColor.G or data.StaffColor[2]) or 65,0,255), math.clamp(tonumber(data.StaffColor.B or data.StaffColor[3]) or 65,0,255))
            end
            if type(data.DeadColor) == "table" then
                ESPConfig.DeadColor = Color3.fromRGB(math.clamp(tonumber(data.DeadColor.R or data.DeadColor[1]) or 120,0,255), math.clamp(tonumber(data.DeadColor.G or data.DeadColor[2]) or 120,0,255), math.clamp(tonumber(data.DeadColor.B or data.DeadColor[3]) or 120,0,255))
            end
            if data.FillTransparency ~= nil then ESPConfig.FillTransparency = math.clamp(tonumber(data.FillTransparency) or ESPConfig.FillTransparency,0,1) end
            if data.OutlineTransparency ~= nil then ESPConfig.OutlineTransparency = math.clamp(tonumber(data.OutlineTransparency) or ESPConfig.OutlineTransparency,0,1) end
            if type(data.Selected) == "table" then
                for _, control in ipairs(optionControls) do
                    if data.Selected[control.Name] ~= nil then
                        pcall(function() control.setSelected(data.Selected[control.Name] == true) end)
                    end
                end
            end
            for _, control in ipairs(optionControls) do
                pcall(control.refresh)
            end
        end

        local master = Instance.new("TextButton")
        master.Size = UDim2.fromOffset(286, 24)
        master.Position = UDim2.fromOffset(4, 280)
        master.BackgroundColor3 = Color3.fromRGB(43, 49, 61)
        master.Text = ""
        master.BorderSizePixel = 0
        master.AutoButtonColor = false
        master.ZIndex = 98
        master.Parent = espOptions

        local mc = Instance.new("UICorner")
        mc.CornerRadius = UDim.new(0, 7)
        mc.Parent = master

        local mb = Instance.new("TextLabel")
        mb.Size = UDim2.fromOffset(16, 16)
        mb.Position = UDim2.fromOffset(6, 4)
        mb.BackgroundColor3 = Color3.fromRGB(52, 59, 72)
        mb.BorderSizePixel = 0
        mb.Text = ""
        mb.ZIndex = 100
        mb.Parent = master

        local mbc = Instance.new("UICorner")
        mbc.CornerRadius = UDim.new(0, 6)
        mbc.Parent = mb

        local mcheck = Instance.new("TextLabel")
        mcheck.Size = UDim2.fromScale(1, 1)
        mcheck.BackgroundTransparency = 1
        mcheck.Text = "✓"
        mcheck.TextColor3 = Color3.fromRGB(255,255,255)
        mcheck.TextSize = 15
        mcheck.Font = Enum.Font.GothamBold
        mcheck.Visible = false
        mcheck.ZIndex = 101
        mcheck.Parent = mb

        local ml = Instance.new("TextLabel")
        ml.Size = UDim2.new(1, -30, 1, 0)
        ml.Position = UDim2.fromOffset(30, 0)
        ml.BackgroundTransparency = 1
        ml.Text = "⚡ ACTIVER LES BOUTONS COCHÉS"
        ml.TextColor3 = Color3.fromRGB(255,255,255)
        ml.TextSize = 10
        ml.Font = Enum.Font.GothamBold
        ml.TextXAlignment = Enum.TextXAlignment.Left
        ml.ZIndex = 99
        ml.Parent = master

        local masterState = false
        local function refreshMaster()
            mcheck.Visible = masterState
            mb.BackgroundColor3 = masterState
                and Color3.fromRGB(35,125,75)
                or Color3.fromRGB(52,59,72)
            master.BackgroundColor3 = masterState
                and Color3.fromRGB(38,56,48)
                or Color3.fromRGB(43,49,61)
            for _, c in ipairs(optionControls) do c.refresh() end
        end

        -- Même action pour le clic sur la case et pour son raccourci clavier.
        local function toggleCheckedButtonsMaster()
            masterState = not masterState
            for _, c in ipairs(optionControls) do
                if c.isSelected() then c.setValue(masterState) end
            end
            refreshMaster()
        end
        _G.PRISONRP_TOGGLE_ESP_CHECKED_BUTTONS = toggleCheckedButtonsMaster
        master.MouseButton1Click:Connect(toggleCheckedButtonsMaster)

        -- Layout ESP JOUEURS :
        -- DÉTECTION STAFF à gauche et MONEY VIEW juste à droite,
        -- mêmes dimensions et même ligne.
        if StaffDetectionCard then
            StaffDetectionCard.Size = UDim2.fromOffset(138, 48)
            StaffDetectionCard.Position = UDim2.fromOffset(4, 224)
            StaffDetectionCard.Visible = true
        end

        if MoneyViewCard then
            MoneyViewCard.Size = UDim2.fromOffset(138, 48)
            MoneyViewCard.Position = UDim2.fromOffset(148, 224)
            MoneyViewCard.Visible = true
        end

        -- La ligne Distance Money View est séparée et placée en dessous.
        if MoneyViewDistanceSlider then
            if MoneyViewDistanceSlider.Label then
                MoneyViewDistanceSlider.Label.Parent = espOptions
                MoneyViewDistanceSlider.Label.Position = UDim2.fromOffset(4, 330)
                MoneyViewDistanceSlider.Label.Size = UDim2.fromOffset(286, 20)
                MoneyViewDistanceSlider.Label.TextXAlignment = Enum.TextXAlignment.Left
                MoneyViewDistanceSlider.Label.ZIndex = 98
                MoneyViewDistanceSlider.Label.Visible = true
            end
            if MoneyViewDistanceSlider.Track then
                MoneyViewDistanceSlider.Track.Parent = espOptions
                MoneyViewDistanceSlider.Track.Position = UDim2.fromOffset(4, 355)
                MoneyViewDistanceSlider.Track.Size = UDim2.fromOffset(286, 8)
                MoneyViewDistanceSlider.Track.ZIndex = 98
                MoneyViewDistanceSlider.Track.Visible = true
            end
        end

        -- Panneau STAFF DÉTECTER à droite dans ESP JOUEURS.
        if StaffList then
            StaffList.Parent = espOptions
            StaffList.Position = UDim2.fromOffset(300, 38)
            StaffList.Size = UDim2.new(1, -308, 0, 315)
            StaffList.Visible = true
            StaffList.ZIndex = 98
            StaffList.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
            StaffList.TextXAlignment = Enum.TextXAlignment.Left
            StaffList.TextYAlignment = Enum.TextYAlignment.Top
            StaffList.TextWrapped = true
        end

        if StaffListTitle and StaffList then
            StaffListTitle.Parent = StaffList
            StaffListTitle.Visible = true
            StaffListTitle.Position = UDim2.fromOffset(8, 6)
            StaffListTitle.Size = UDim2.new(1, -16, 0, 24)
            StaffListTitle.Text = "🛡 STAFF DÉTECTER"
            StaffListTitle.TextXAlignment = Enum.TextXAlignment.Center
            StaffListTitle.TextYAlignment = Enum.TextYAlignment.Center
            StaffListTitle.ZIndex = 99
        end

        local ESPStatusLabel = Instance.new("TextLabel")
        ESPStatusLabel.Size = UDim2.new(1, -16, 0, 24)
        ESPStatusLabel.Position = UDim2.fromOffset(8, 375)
        ESPStatusLabel.BackgroundTransparency = 1
        ESPStatusLabel.Text = "ESP actif"
        ESPStatusLabel.TextColor3 = Color3.fromRGB(145,155,170)
        ESPStatusLabel.TextSize = 10
        ESPStatusLabel.Font = Enum.Font.GothamMedium
        ESPStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
        ESPStatusLabel.ZIndex = 98
        ESPStatusLabel.Parent = espOptions

        ESPContent.CanvasSize = UDim2.fromOffset(0, 766)

local ESPObjects = {}
local StaffESPObjects = {}
local Connections = {}
local StaffStateCache = {}
local StaffStateCacheTime = {}
local RPNameCache = {}
local RPNameCacheTime = {}
local STAFF_CACHE_INTERVAL = 0.75

-- Récupère le vrai pseudo RP du personnage, sans le remplacer par le @ Roblox.
-- AutoLocalize est désactivé sur les TextLabels ESP pour éviter la traduction
-- automatique de noms anglais (ex. « Soon Jin » qui devient « Bientôt Jin »).
local function safeText(v)
    if v == nil then return nil end
    local value = tostring(v)
    if value == "" then return nil end
    return value
end

local function getRPName(player)
    if not player then return "Inconnu" end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if humanoid and humanoid.DisplayName
        and humanoid.DisplayName ~= player.Name
        and humanoid.DisplayName ~= player.DisplayName then
        return humanoid.DisplayName
    end

    local keys = {
        "RPName", "RP_Name", "RoleplayName",
        "CharacterName", "CharName",
        "PseudoRP", "Pseudo_RP",
        "NomRP", "Nom_RP",
    }

    for _, container in ipairs({player, character}) do
        if container then
            for _, key in ipairs(keys) do
                local attr = container:GetAttribute(key)
                if typeof(attr) == "string"
                    and attr ~= ""
                    and attr ~= player.Name
                    and attr ~= player.DisplayName then
                    return attr
                end
            end

            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("StringValue") then
                    local objectName = obj.Name:lower()
                    if objectName:find("rp") or objectName:find("roleplay")
                        or objectName:find("charactername") or objectName:find("charname")
                        or objectName:find("pseudorp") or objectName:find("nomrp") then
                        local value = safeText(obj.Value)
                        if value and value ~= player.Name
                            and value ~= player.DisplayName then
                            return value
                        end
                    end
                end
            end
        end
    end

    return player.DisplayName or player.Name
end

local function getCachedRPName(player)
    if not player then return "Inconnu" end
    local now = os.clock()
    if RPNameCacheTime[player]
        and (now - RPNameCacheTime[player]) < 0.5
        and RPNameCache[player] then
        return RPNameCache[player]
    end

    local name = getRPName(player)
    RPNameCache[player] = name
    RPNameCacheTime[player] = now
    return name
end

-- STAFF ESP V128 : constantes de détection manquantes dans l'ancienne version.
-- Le groupe 304256484 est le groupe créateur de PRISON RP / Nyxkay Studio.
local STAFF_GROUP_ID = 304256484
local STAFF_MIN_RANK = 200
local STAFF_USER_IDS = {}
local STAFF_KEYWORDS = {
    "staff", "admin", "administrateur", "administratrice",
    "modérateur", "moderateur", "modératrice", "moderatrice",
    "fondateur", "fondatrice", "développeur", "developpeur",
    "développeuse", "developpeuse", "dev", "support",
    "responsable", "manager", "superadmin", "owner",
    "administrator", "moderator", "developer", "founder", "tester",
    "community manager", "head admin",
}
local tracerContainer = Instance.new("Folder")
tracerContainer.Name = "Tracers"
tracerContainer.Parent = ScreenGui

local function isStaff(player)
    if not ESPConfig.StaffDetection or not player then
        return false
    end

    if STAFF_USER_IDS[player.UserId] then
        return true
    end

    -- Groupe utilisé dans le script Staff ESP précédent.
    pcall(function()
        if player:IsInGroup(STAFF_GROUP_ID)
            and player:GetRankInGroup(STAFF_GROUP_ID) >= STAFF_MIN_RANK then
            return true
        end
    end)

    -- Le pcall ci-dessus ne peut pas retourner depuis cette fonction,
    -- donc on vérifie séparément.
    local ok, rank = pcall(function()
        return player:GetRankInGroup(STAFF_GROUP_ID)
    end)
    if ok and rank >= STAFF_MIN_RANK then
        return true
    end

    local containers = {player, player.Character}
    for _, container in ipairs(containers) do
        if container then
            for _, attrName in ipairs({
                "Role", "RoleName", "RoleTitle", "PlayerRole",
                "StaffRole", "AdminRole", "ModeratorRole",
                "Rank", "GroupRank", "GroupRole",
                "IsStaff", "IsAdmin", "IsModerator",
                "Staff", "Admin", "Moderator",
            }) do
                local value = container:GetAttribute(attrName)
                if value ~= nil then
                    local txt = tostring(value):lower()
                    if value == true or txt == "true" then
                        return true
                    end
                    for _, word in ipairs(STAFF_KEYWORDS) do
                        if txt:find(word, 1, true) then
                            return true
                        end
                    end
                end
            end
        end
    end

    local roleTexts = {
        player.Team and player.Team.Name,
        player:GetAttribute("Role"),
        player:GetAttribute("RoleName"),
        player:GetAttribute("Rank"),
    }

    for _, value in ipairs(roleTexts) do
        if value then
            local txt = tostring(value):lower()
            for _, word in ipairs(STAFF_KEYWORDS) do
                if txt:find(word, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function getRoot(character)
    return character and (
        character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
    )
end

local function createNameTag(player, character, root)
    local bill = Instance.new("BillboardGui")
    bill.Name = "PRISONRP_ESP_Name"
    bill.AutoLocalize = false
    bill.Adornee = root
    bill.AlwaysOnTop = true
    bill.Size = UDim2.fromOffset(220, 78)
    bill.StudsOffset = Vector3.new(0, 3.4, 0)
    bill.MaxDistance = ESPConfig.MaxDistance
    bill.Parent = root

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundTransparency = 1
    frame.Parent = bill

    local name = Instance.new("TextLabel")
    name.Name = "Name"
    name.AutoLocalize = false
    name.Size = UDim2.new(1, 0, 0, 20)
    name.Position = UDim2.fromOffset(0, 4) -- RP légèrement descendu vers le @pseudo
    name.BackgroundTransparency = 1
    name.TextSize = 13
    name.Font = Enum.Font.GothamBold
    name.TextStrokeTransparency = 0.25
    name.TextXAlignment = Enum.TextXAlignment.Center
    name.Parent = frame

    local gameName = Instance.new("TextLabel")
    gameName.Name = "GameName"
    gameName.AutoLocalize = false
    gameName.Size = UDim2.new(1, 0, 0, 15)
    gameName.Position = UDim2.fromOffset(0, 22)
    gameName.BackgroundTransparency = 1
    gameName.TextSize = 11
    gameName.Font = Enum.Font.GothamMedium
    gameName.TextColor3 = Color3.fromRGB(220, 225, 235)
    gameName.TextStrokeTransparency = 0.4
    gameName.TextXAlignment = Enum.TextXAlignment.Center
    gameName.Parent = frame

    local details = Instance.new("TextLabel")
    details.Name = "Details"
    details.AutoLocalize = false
    details.Size = UDim2.new(1, 0, 0, 38)
    details.Position = UDim2.fromOffset(0, 33)
    details.BackgroundTransparency = 1
    details.TextSize = 10
    details.Font = Enum.Font.GothamMedium
    details.TextColor3 = Color3.fromRGB(235, 235, 240)
    details.TextStrokeTransparency = 0.35
    details.TextXAlignment = Enum.TextXAlignment.Center
    details.TextWrapped = true
    details.Parent = frame

    return bill, name, gameName, details
end

local function createTracer()
    local line = Instance.new("Frame")
    line.Name = "ESPTracer"
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.BackgroundColor3 = ESPConfig.PlayerColor
    line.BorderSizePixel = 0
    line.Visible = false
    line.ZIndex = 2
    line.Parent = tracerContainer

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = line

    return line
end

local function setLine(line, fromPos, toPos, color)
    if not line then return end

    local delta = toPos - fromPos
    local length = delta.Magnitude

    if length < 1 then
        line.Visible = false
        return
    end

    line.Visible = true
    line.BackgroundColor3 = color
    line.Position = UDim2.fromOffset(
        (fromPos.X + toPos.X) / 2,
        (fromPos.Y + toPos.Y) / 2
    )
    line.Size = UDim2.fromOffset(length, 2)
    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
end


local function removeESP(player)
    local data = ESPObjects[player]
    if not data then return end

    if data.highlight then
        pcall(function() data.highlight:Destroy() end)
    end
    if data.billboard then
        pcall(function() data.billboard:Destroy() end)
    end
    if data.tracer then
        pcall(function() data.tracer:Destroy() end)
    end

    ESPObjects[player] = nil
end

local function setupESP(player)
    if player == LocalPlayer then return end
    removeESP(player)

    local character = player.Character
    local root = getRoot(character)
    if not character or not root then return end

    local data = {
        player = player,
        character = character,
        root = root,
    }

    -- Le Highlight est créé dès que le joueur est chargé, mais reste
    -- invisible tant que le bouton "ESP JOUEURS" est OFF.
    -- Cela évite le bug où le bouton s'active alors qu'aucun Highlight
    -- n'existe encore dans ESPObjects.
    local highlight = Instance.new("Highlight")
    highlight.Name = "PRISONRP_ESP_Highlight"
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = ESPConfig.FillTransparency
    highlight.OutlineTransparency = ESPConfig.OutlineTransparency
    highlight.Enabled = false
    highlight.Parent = character
    data.highlight = highlight

    local bill, nameLabel, gameNameLabel, detailLabel = createNameTag(player, character, root)
    data.billboard = bill
    data.nameLabel = nameLabel
    data.gameNameLabel = gameNameLabel
    data.detailLabel = detailLabel

    data.tracer = createTracer()

    ESPObjects[player] = data
end

local function updateESP(data)
    local player = data.player
    local character = player.Character
    local root = getRoot(character)

    if character ~= data.character or root ~= data.root then
        setupESP(player)
        return
    end

    if not character or not root or not root.Parent then
        removeESP(player)
        return
    end

    local myCharacter = LocalPlayer.Character
    local myRoot = getRoot(myCharacter)
    if not myRoot then return end

    local distance = (root.Position - myRoot.Position).Magnitude
    local inRange = distance <= ESPConfig.MaxDistance

    -- Chaque fonctionnalité est indépendante :
    -- ESP = uniquement le Highlight du personnage
    -- Noms/Distance/Vie = Billboard indépendant
    -- Tracers = tracers indépendants
    -- Détection Staff = indépendante des autres affichages

    local color = ESPConfig.PlayerColor

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local health = humanoid and math.max(0, humanoid.Health) or 0
    local maxHealth = humanoid and math.max(1, humanoid.MaxHealth) or 100
    local dead = humanoid and humanoid.Health <= 0

    if dead then
        color = ESPConfig.DeadColor
    end

    if data.highlight then
        -- Le bouton ESP JOUEURS contrôle le Highlight global.
        data.highlight.Enabled = ESPConfig.ESPEnabled
            and inRange

        data.highlight.FillColor = color
        data.highlight.OutlineColor = color
        data.highlight.FillTransparency = ESPConfig.FillTransparency
        data.highlight.OutlineTransparency = ESPConfig.OutlineTransparency
    end

    if data.billboard then
        -- Les informations restent indépendantes du Highlight.
        data.billboard.Enabled = inRange
            and (ESPConfig.NamesEnabled or ESPConfig.GameNameEnabled or ESPConfig.DistanceEnabled or ESPConfig.HealthEnabled)
        data.billboard.MaxDistance = ESPConfig.MaxDistance
    end

    if data.nameLabel then
        data.nameLabel.Visible = ESPConfig.NamesEnabled
        data.nameLabel.TextColor3 = color

        data.nameLabel.Text = getCachedRPName(player)
    end

    if data.gameNameLabel then
        data.gameNameLabel.Visible = ESPConfig.GameNameEnabled
        data.gameNameLabel.TextColor3 = color
        data.gameNameLabel.Text = player.DisplayName or player.Name
    end

    if data.detailLabel then
        local parts = {}

        if ESPConfig.NamesEnabled then
            table.insert(parts, "@" .. player.Name)
        end

        if ESPConfig.DistanceEnabled then
            table.insert(parts, string.format("%dm", math.floor(distance + 0.5)))
        end

        if ESPConfig.HealthEnabled then
            table.insert(parts, string.format("❤ %d/%d", math.floor(health + 0.5), math.floor(maxHealth + 0.5)))
        end

        data.detailLabel.Text = table.concat(parts, "  •  ")
        data.detailLabel.Visible = ESPConfig.NamesEnabled or ESPConfig.DistanceEnabled or ESPConfig.HealthEnabled
    end

    if data.tracer then
        -- Les tracers restent totalement indépendants de ESP JOUEURS.
        if ESPConfig.TracersEnabled and inRange then
            local camera = workspace.CurrentCamera
            if camera then
                local screenPos, onScreen = camera:WorldToViewportPoint(root.Position)
                if onScreen and screenPos.Z > 0 then
                    local viewport = camera.ViewportSize
                    local fromPos = Vector2.new(viewport.X / 2, viewport.Y - 8)
                    local toPos = Vector2.new(screenPos.X, screenPos.Y)
                    setLine(data.tracer, fromPos, toPos, color)
                else
                    data.tracer.Visible = false
                end
            end
        else
            data.tracer.Visible = false
        end
    end
end

-- =========================
-- STAFF ESP INDÉPENDANT
-- =========================
-- Détection staff mise en cache pour éviter GetRankInGroup / scans lourds à chaque frame.
local function cachedIsStaff(player, force)
    if not player then return false end
    local now = os.clock()
    if not force and StaffStateCacheTime[player] and (now - StaffStateCacheTime[player]) < STAFF_CACHE_INTERVAL then
        return StaffStateCache[player] == true
    end
    local result = isStaff(player)
    StaffStateCache[player] = result == true
    StaffStateCacheTime[player] = now
    return StaffStateCache[player]
end

-- Le STAFF ESP ne dépend d'aucun autre bouton.
-- Il possède son propre Highlight + son propre pseudo/distance.

local function createStaffTag(player, character, root)
    local bill = Instance.new("BillboardGui")
    bill.Name = "PRISONRP_STAFF_ESP_Name"
    bill.AutoLocalize = false
    bill.Adornee = root
    bill.AlwaysOnTop = true
    bill.Size = UDim2.fromOffset(220, 48)
    bill.StudsOffset = Vector3.new(0, 3.7, 0)
    bill.MaxDistance = ESPConfig.MaxDistance
    bill.Parent = root

    local name = Instance.new("TextLabel")
    name.Name = "StaffName"
    name.AutoLocalize = false
    name.Size = UDim2.new(1, 0, 0, 23)
    name.BackgroundTransparency = 1
    name.TextSize = 13
    name.Font = Enum.Font.GothamBold
    name.TextColor3 = ESPConfig.StaffColor
    name.TextStrokeTransparency = 0.2
    name.TextXAlignment = Enum.TextXAlignment.Center
    name.Parent = bill

    local distance = Instance.new("TextLabel")
    distance.Name = "StaffDistance"
    distance.Size = UDim2.new(1, 0, 0, 22)
    distance.Position = UDim2.fromOffset(0, 23)
    distance.BackgroundTransparency = 1
    distance.TextSize = 10
    distance.Font = Enum.Font.GothamMedium
    distance.TextColor3 = Color3.fromRGB(245, 245, 245)
    distance.TextStrokeTransparency = 0.3
    distance.TextXAlignment = Enum.TextXAlignment.Center
    distance.Parent = bill

    return bill, name, distance
end

local function removeStaffESP(player)
    local data = StaffESPObjects[player]
    if not data then return end

    if data.highlight then
        pcall(function() data.highlight:Destroy() end)
    end
    if data.billboard then
        pcall(function() data.billboard:Destroy() end)
    end

    StaffESPObjects[player] = nil
end

local function setupStaffESP(player)
    if player == LocalPlayer then return end
    removeStaffESP(player)

    if not ESPConfig.StaffDetection then return end
    if not cachedIsStaff(player, true) then return end

    local character = player.Character
    local root = getRoot(character)
    if not character or not root then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "PRISONRP_STAFF_ESP_Body"
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = ESPConfig.StaffColor
    highlight.FillTransparency = 0.72
    highlight.OutlineColor = ESPConfig.StaffColor
    highlight.OutlineTransparency = 0
    highlight.Parent = character

    local bill, nameLabel, distanceLabel = createStaffTag(player, character, root)

    StaffESPObjects[player] = {
        player = player,
        character = character,
        root = root,
        highlight = highlight,
        billboard = bill,
        nameLabel = nameLabel,
        distanceLabel = distanceLabel,
    }
end

local function updateStaffESP(data)
    if not ESPConfig.StaffDetection then
        removeStaffESP(data.player)
        return
    end

    local player = data.player
    if not player or not player.Parent then
        removeStaffESP(player)
        return
    end

    if not cachedIsStaff(player, false) then
        removeStaffESP(player)
        return
    end

    local character = player.Character
    local root = getRoot(character)
    if not character or not root or not root.Parent then
        removeStaffESP(player)
        return
    end

    if character ~= data.character or root ~= data.root then
        setupStaffESP(player)
        return
    end

    local myRoot = getRoot(LocalPlayer.Character)
    if not myRoot then return end

    local distance = (root.Position - myRoot.Position).Magnitude
    local inRange = distance <= ESPConfig.MaxDistance

    data.highlight.Enabled = inRange
    data.highlight.FillColor = ESPConfig.StaffColor
    data.highlight.OutlineColor = ESPConfig.StaffColor

    data.billboard.Enabled = inRange
    data.billboard.MaxDistance = ESPConfig.MaxDistance
    data.nameLabel.Text = getCachedRPName(player)
    data.distanceLabel.Text = string.format("🛡 STAFF  •  %dm", math.floor(distance + 0.5))
end

-- =========================
-- PLAYER CONNECTIONS
-- =========================

local function hookPlayer(player)
    if player == LocalPlayer then return end

    if player.Character then
        task.defer(function()
            setupESP(player)
            setupStaffESP(player)
        end)
    end

    Connections[player] = player.CharacterAdded:Connect(function()
        task.wait(0.15)
        setupESP(player)
        setupStaffESP(player)
    end)
end

for _, player in ipairs(Players:GetPlayers()) do
    hookPlayer(player)
end

Connections.PlayerAdded = Players.PlayerAdded:Connect(hookPlayer)

Connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
    removeESP(player)
    removeStaffESP(player)

    StaffStateCache[player] = nil
    StaffStateCacheTime[player] = nil

    if Connections[player] then
        pcall(function()
            Connections[player]:Disconnect()
        end)
        Connections[player] = nil
    end
end)

Connections.Render = RunService.RenderStepped:Connect(function()
    -- Répare automatiquement les joueurs dont le Character n'était pas encore
    -- prêt au moment du CharacterAdded (cas fréquent lors d'un respawn).
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and not ESPObjects[player] then
            pcall(function() setupESP(player) end)
        end
    end

    for player, data in pairs(ESPObjects) do
        if player and player.Parent then
            pcall(function()
                updateESP(data)
            end)
        else
            removeESP(player)
        end
    end

    -- STAFF ESP est traité séparément : il fonctionne même si ESP JOUEURS est OFF.
    if ESPConfig.StaffDetection then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                if not StaffESPObjects[player] then
                    pcall(function() setupStaffESP(player) end)
                end
            end
        end
    else
        for player in pairs(StaffESPObjects) do
            removeStaffESP(player)
        end
    end

    for player, data in pairs(StaffESPObjects) do
        if player and player.Parent then
            pcall(function()
                updateStaffESP(data)
            end)
        else
            removeStaffESP(player)
        end
    end

    ESPStatusLabel.Text = ESPConfig.ESPEnabled
        and ("ESP actif • " .. tostring(#Players:GetPlayers() - 1) .. " joueur(s)")
        or "ESP désactivé"
end)

-- =========================
-- CLEANUP
-- =========================

_G.PRISONRP_HUB_ESP_CLEANUP = function()
    for player in pairs(ESPObjects) do
        removeESP(player)
    end
    for player in pairs(StaffESPObjects) do
        removeStaffESP(player)
    end

    for _, connection in pairs(Connections) do
        pcall(function()
            if typeof(connection) == "RBXScriptConnection" then
                connection:Disconnect()
            end
        end)
    end

    ESPObjects = {}
    StaffESPObjects = {}
    Connections = {}
    StaffStateCache = {}
    StaffStateCacheTime = {}
    RPNameCache = {}
    RPNameCacheTime = {}

    _G.PRISONRP_HUB_ESP_CLEANUP = nil
end

    -- V160 : le titre ESP & SURVEILLANCE est volontairement conservé.

    --==============================================================
    -- V153 FINAL : ESP JOUEURS — POSITIONS GARANTIES
    --==============================================================
    pcall(function()
        -- Les deux cartes doivent toujours être visibles et côte à côte.
        if StaffDetectionCard then
            StaffDetectionCard.Parent = espOptions
            StaffDetectionCard.Visible = true
            StaffDetectionCard.Size = UDim2.fromOffset(138, 48)
            StaffDetectionCard.Position = UDim2.fromOffset(4, 224)
            StaffDetectionCard.ZIndex = 98
        end

        if MoneyViewCard then
            MoneyViewCard.Parent = espOptions
            MoneyViewCard.Visible = true
            MoneyViewCard.Size = UDim2.fromOffset(138, 48)
            MoneyViewCard.Position = UDim2.fromOffset(148, 224)
            MoneyViewCard.ZIndex = 98
        end

        -- Le slider "Distance Money View" reste bien sous les cartes.
        if MoneyViewDistanceSlider then
            if MoneyViewDistanceSlider.Label then
                MoneyViewDistanceSlider.Label.Parent = espOptions
                MoneyViewDistanceSlider.Label.Visible = true
                MoneyViewDistanceSlider.Label.Position = UDim2.fromOffset(4, 330)
                MoneyViewDistanceSlider.Label.Size = UDim2.fromOffset(286, 20)
                MoneyViewDistanceSlider.Label.ZIndex = 98
            end
            if MoneyViewDistanceSlider.Track then
                MoneyViewDistanceSlider.Track.Parent = espOptions
                MoneyViewDistanceSlider.Track.Visible = true
                MoneyViewDistanceSlider.Track.Position = UDim2.fromOffset(4, 355)
                MoneyViewDistanceSlider.Track.Size = UDim2.fromOffset(286, 8)
                MoneyViewDistanceSlider.Track.ZIndex = 98
            end
        end

        -- Rien de l'ancien panneau SURVEILLANCE ne doit rester.
        for _, obj in ipairs(ESPContent:GetChildren()) do
            if obj:IsA("Frame") then
                for _, d in ipairs(obj:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text == "🛡 SURVEILLANCE / MONEY VIEW" then
                        obj:Destroy()
                        break
                    end
                end
            end
        end
    end)

    --==============================================================
    -- V160 FINAL : TITRE ESP VISIBLE + PAS DE DÉFILEMENT
    --==============================================================
    pcall(function()
        if espPage then
            local titleObj = nil
            local lineObj = nil
            for _, obj in ipairs(espPage:GetChildren()) do
                if obj:IsA("TextLabel") and obj.Text == "ESP & SURVEILLANCE" then
                    titleObj = obj
                elseif obj:IsA("Frame") and obj.Name == "V96SectionLine" then
                    lineObj = obj
                end
            end

            if titleObj then
                titleObj.Visible = true
                titleObj.Position = UDim2.fromOffset(0, 0)
                titleObj.Size = UDim2.new(1, 0, 0, 20)
                titleObj.ZIndex = 94
            end

            if lineObj then
                lineObj.Visible = true
                lineObj.Position = UDim2.fromOffset(0, 20)
                lineObj.Size = UDim2.new(1, 0, 0, 1)
                lineObj.ZIndex = 94
            end
        end

        if ESPContent then
            ESPContent.Position = UDim2.fromOffset(0, 28)
            ESPContent.Size = UDim2.new(1, 0, 1, -28)
            ESPContent.ScrollingEnabled = false
            ESPContent.ScrollBarThickness = 0
            ESPContent.ScrollBarImageTransparency = 1
            ESPContent.CanvasPosition = Vector2.zero
        end

        if espOptions then
            espOptions.Position = UDim2.fromOffset(4, 0)
            espOptions.Size = UDim2.new(1, -8, 0, 400)
        end
    end)

    --==============================================================
    -- V162 FINAL : AUCUNE BARRE DE DÉFILEMENT ESP
    --==============================================================
    pcall(function()
        if ESPContent then
            ESPContent.ScrollingEnabled = false
            ESPContent.ScrollBarThickness = 0
            ESPContent.ScrollBarImageTransparency = 1
            ESPContent.CanvasPosition = Vector2.zero
        end
    end)


end) -- ferme le task.spawn de l'ESP intégré

-- FINAL STYLE : boutons PÊCHE / TP / AUTO-SELL / VENDRE TOUT
-- Ce bloc est exécuté après les autres réglages de style.
task.defer(function()
    task.wait()
    local styledButtons = {
        ToggleFishBtn,
        RarityBtn,
        TeleportBtn,
        AutoSellBtn,
        SellNowBtn,
    }

    for _, btn in ipairs(styledButtons) do
        if btn then
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 16
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.TextXAlignment = Enum.TextXAlignment.Center
            btn.TextYAlignment = Enum.TextYAlignment.Center
        end
    end

    if AutoSellBtn then
        AutoSellBtn.Text = "💰 AUTO-SELL"
    end
end)

-- STYLE FINAL : AUTO EAT/DRINK, AUTO BUY FOOD, AUTO MINE, TP VENDEUR
task.defer(function()
    task.wait()

    local styledButtons = {
        AutoEatDrinkBtn,
        StartBtn,
        AutoMineBtn,
        AutoMineSellerBtn,
    }

    for _, btn in ipairs(styledButtons) do
        if btn then
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 16
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.TextXAlignment = Enum.TextXAlignment.Center
            btn.TextYAlignment = Enum.TextYAlignment.Center
        end
    end

    if AutoEatDrinkBtn then
        AutoEatDrinkBtn.TextXAlignment = Enum.TextXAlignment.Center
        AutoEatDrinkBtn.TextYAlignment = Enum.TextYAlignment.Center
        local oldPad = AutoEatDrinkBtn:FindFirstChild("AutoEatDrinkTextPadding")
        if oldPad then oldPad:Destroy() end
    end
end)


    --==============================================================
    -- FINAL PATCH V132
    -- GIVE MONEY AUTO LOOP DANS L'ONGLET AUTRES
    --==============================================================
    -- REGISTER CLEANUP V33 : Give Money isolé dans sa propre fonction anonyme.
    -- Cela évite que ses nombreux locals consomment les registres du gros scope principal.
    _G.PRISONRP_GiveMoneyUI = _G.PRISONRP_GiveMoneyUI or {}
    (function()
        local GiveMoneyPlayers = game:GetService("Players")
        local GiveMoneyRS = game:GetService("ReplicatedStorage")
        local GiveMoneyLocalPlayer = GiveMoneyPlayers.LocalPlayer
        local GiveMoneyConnections = {}
        local GiveMoneyRunning = false
        local GiveMoneyRunToken = 0

        local GiveMoneyRemotes = GiveMoneyRS:FindFirstChild("Remotes")
        local GiveMoneyRemote = GiveMoneyRemotes and GiveMoneyRemotes:FindFirstChild("GiveMoney")

        -- Nettoyage explicite : la tâche de 15 secondes et les écouteurs Players
        -- ne doivent pas survivre à UNLOAD ou s'empiler au rechargement du hub.
        _G.PRISONRP_GIVE_MONEY_STOP = function()
            GiveMoneyRunning = false
            GiveMoneyRunToken += 1
            for i = #GiveMoneyConnections, 1, -1 do
                local connection = GiveMoneyConnections[i]
                pcall(function() connection:Disconnect() end)
                GiveMoneyConnections[i] = nil
            end
            _G.PRISONRP_GiveMoneyRPcache = {}
        end

        -- Si le remote existe, on crée uniquement la partie UI dans AUTRES.
        -- Le système reste indépendant du reste du hub.
        if GiveMoneyRemote and autresPage then
            local GiveMoneyFrame = Instance.new("Frame")
            GiveMoneyFrame.Name = "GiveMoneyPanel"
            -- Colonne verticale placée à droite de l'onglet AUTRES.
            GiveMoneyFrame.Size = UDim2.fromOffset(205, 430)
            GiveMoneyFrame.Position = UDim2.new(1, -205, 0, 10)
            GiveMoneyFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
            GiveMoneyFrame.BorderSizePixel = 0
            GiveMoneyFrame.ZIndex = 20
            GiveMoneyFrame.Parent = autresPage

            local GiveMoneyCorner = Instance.new("UICorner")
            GiveMoneyCorner.CornerRadius = UDim.new(0, 9)
            GiveMoneyCorner.Parent = GiveMoneyFrame

            local GiveMoneyTitle = Instance.new("TextLabel")
            GiveMoneyTitle.Size = UDim2.new(1, -12, 0, 26)
            GiveMoneyTitle.Position = UDim2.fromOffset(6, 5)
            GiveMoneyTitle.BackgroundTransparency = 1
            GiveMoneyTitle.Text = "💰 GIVE MONEY"
            GiveMoneyTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
            GiveMoneyTitle.TextSize = 11
            GiveMoneyTitle.Font = Enum.Font.GothamBold
            GiveMoneyTitle.TextXAlignment = Enum.TextXAlignment.Left
            GiveMoneyTitle.ZIndex = 21
            GiveMoneyTitle.Parent = GiveMoneyFrame

            local GiveMoneySelected = Instance.new("TextLabel")
            GiveMoneySelected.Size = UDim2.new(1, -12, 0, 20)
            GiveMoneySelected.Position = UDim2.fromOffset(6, 32)
            GiveMoneySelected.BackgroundTransparency = 1
            GiveMoneySelected.Text = "Joueur : aucun"
            GiveMoneySelected.TextColor3 = Color3.fromRGB(180, 185, 195)
            GiveMoneySelected.TextSize = 9
            GiveMoneySelected.Font = Enum.Font.Gotham
            GiveMoneySelected.TextXAlignment = Enum.TextXAlignment.Left
            GiveMoneySelected.TextTruncate = Enum.TextTruncate.AtEnd
            GiveMoneySelected.ZIndex = 21
            GiveMoneySelected.Parent = GiveMoneyFrame

            local GiveMoneySearch = Instance.new("TextBox")
            GiveMoneySearch.Size = UDim2.new(1, -12, 0, 30)
            GiveMoneySearch.Position = UDim2.fromOffset(6, 56)
            GiveMoneySearch.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
            GiveMoneySearch.BorderSizePixel = 0
            GiveMoneySearch.PlaceholderText = "Rechercher..."
            GiveMoneySearch.PlaceholderColor3 = Color3.fromRGB(125, 130, 140)
            GiveMoneySearch.Text = ""
            GiveMoneySearch.TextColor3 = Color3.fromRGB(255, 255, 255)
            GiveMoneySearch.TextSize = 9
            GiveMoneySearch.Font = Enum.Font.Gotham
            GiveMoneySearch.ZIndex = 21
            GiveMoneySearch.Parent = GiveMoneyFrame

            local GiveMoneySearchCorner = Instance.new("UICorner")
            GiveMoneySearchCorner.CornerRadius = UDim.new(0, 6)
            GiveMoneySearchCorner.Parent = GiveMoneySearch

            local GiveMoneyList = Instance.new("ScrollingFrame")
            GiveMoneyList.Size = UDim2.new(1, -12, 0, 215)
            GiveMoneyList.Position = UDim2.fromOffset(6, 91)
            GiveMoneyList.BackgroundColor3 = Color3.fromRGB(30, 32, 39)
            GiveMoneyList.BorderSizePixel = 0
            GiveMoneyList.ScrollBarThickness = 3
            GiveMoneyList.CanvasSize = UDim2.new(0, 0, 0, 0)
            GiveMoneyList.ZIndex = 21
            GiveMoneyList.Parent = GiveMoneyFrame

            local GiveMoneyListCorner = Instance.new("UICorner")
            GiveMoneyListCorner.CornerRadius = UDim.new(0, 7)
            GiveMoneyListCorner.Parent = GiveMoneyList

            local GiveMoneyLayout = Instance.new("UIListLayout")
            GiveMoneyLayout.Padding = UDim.new(0, 4)
            GiveMoneyLayout.Parent = GiveMoneyList

            local GiveMoneyAmount = Instance.new("TextBox")
            GiveMoneyAmount.Name = "GiveMoneyAmount"
            GiveMoneyAmount.Size = UDim2.new(1, -12, 0, 30)
            GiveMoneyAmount.Position = UDim2.fromOffset(6, 316)
            GiveMoneyAmount.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
            GiveMoneyAmount.BorderSizePixel = 0
            GiveMoneyAmount.PlaceholderText = "Montant à donner..."
            GiveMoneyAmount.PlaceholderColor3 = Color3.fromRGB(125, 130, 140)
            GiveMoneyAmount.Text = "3000"
            GiveMoneyAmount.TextColor3 = Color3.fromRGB(255, 255, 255)
            GiveMoneyAmount.TextSize = 10
            GiveMoneyAmount.Font = Enum.Font.GothamBold
            GiveMoneyAmount.ClearTextOnFocus = false
            GiveMoneyAmount.ZIndex = 21
            GiveMoneyAmount.Parent = GiveMoneyFrame

            local GiveMoneyAmountCorner = Instance.new("UICorner")
            GiveMoneyAmountCorner.CornerRadius = UDim.new(0, 6)
            GiveMoneyAmountCorner.Parent = GiveMoneyAmount

            local function getGiveMoneyAmount()
                local raw = tostring(GiveMoneyAmount.Text or "")
                raw = raw:gsub("[^%d]", "")
                local amount = tonumber(raw)
                if not amount or amount < 1 then
                    return nil
                end
                return math.floor(amount)
            end

            local GiveMoneyToggle = Instance.new("TextButton")
            GiveMoneyToggle.Size = UDim2.new(1, -12, 0, 34)
            GiveMoneyToggle.Position = UDim2.fromOffset(6, 352)
            GiveMoneyToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            GiveMoneyToggle.BorderSizePixel = 0
            GiveMoneyToggle.Text = "OFF • 3000 / 15s"
            GiveMoneyToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
            GiveMoneyToggle.TextSize = 10
            GiveMoneyToggle.Font = Enum.Font.GothamBold
            GiveMoneyToggle.ZIndex = 21
            GiveMoneyToggle.Parent = GiveMoneyFrame

            local GiveMoneyToggleCorner = Instance.new("UICorner")
            GiveMoneyToggleCorner.CornerRadius = UDim.new(0, 7)
            GiveMoneyToggleCorner.Parent = GiveMoneyToggle

            local GiveMoneySelectedPlayer = nil

            local function updateGiveMoneyToggle()
                if not GiveMoneyToggle or not GiveMoneyToggle.Parent then return end
                local amount = getGiveMoneyAmount() or 3000
                if GiveMoneyRunning then
                    GiveMoneyToggle.Text = "ON  ✓  •  " .. tostring(amount) .. " / 15s"
                    GiveMoneyToggle.BackgroundColor3 = Color3.fromRGB(45, 170, 90)
                else
                    GiveMoneyToggle.Text = "OFF  •  " .. tostring(amount) .. " / 15s"
                    GiveMoneyToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
                end
            end

            GiveMoneyConnections[#GiveMoneyConnections + 1] = GiveMoneyAmount:GetPropertyChangedSignal("Text"):Connect(function()
                local clean = tostring(GiveMoneyAmount.Text or ""):gsub("[^%d]", "")
                if GiveMoneyAmount.Text ~= clean then
                    GiveMoneyAmount.Text = clean
                end
                updateGiveMoneyToggle()
            end)

            -- V173 : même logique de pseudo RP que TP / SPEC.
            -- Registre optimisé : cache stocké hors locals du chunk principal.
            _G.PRISONRP_GiveMoneyRPcache = _G.PRISONRP_GiveMoneyRPcache or {}

            local function giveMoneyCleanRPText(text, player)
                if not text then return nil end
                text = tostring(text):gsub("\r", "")
                local lines = {}
                for line in text:gmatch("[^\n]+") do
                    line = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if line ~= "" then table.insert(lines, line) end
                end

                local raw = table.concat(lines, " ")
                local beforeAt = raw:match("^(.-)%s*@[%w_]+")
                if beforeAt then
                    beforeAt = beforeAt:gsub("^%s+", ""):gsub("%s+$", "")
                    if beforeAt ~= "" and beforeAt ~= player.Name and beforeAt ~= player.DisplayName then
                        return beforeAt
                    end
                end

                for i, line in ipairs(lines) do
                    if line == "@" .. player.Name then
                        local candidate = lines[i - 1]
                        if candidate and candidate ~= "" and not candidate:find("%[")
                            and candidate ~= player.Name and candidate ~= player.DisplayName then
                            return candidate
                        end
                    end
                end

                for _, line in ipairs(lines) do
                    local lower = line:lower()
                    if line ~= player.Name
                        and line ~= player.DisplayName
                        and not line:find("@")
                        and not line:find("%[")
                        and not lower:find("vie:")
                        and not lower:find("health")
                        and not lower:find("distance")
                        and not lower:find("dis:")
                        and not lower:find("homme")
                        and not lower:find("femme")
                        and #line <= 40 then
                        return line
                    end
                end
                return nil
            end

            local function giveMoneyGetRPPseudo(player)
                if not player then return "Inconnu" end
                if _G.PRISONRP_GiveMoneyRPcache[player] and _G.PRISONRP_GiveMoneyRPcache[player] ~= "" then
                    return _G.PRISONRP_GiveMoneyRPcache[player]
                end

                local character = player.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.DisplayName and humanoid.DisplayName ~= ""
                    and humanoid.DisplayName ~= player.Name and humanoid.DisplayName ~= player.DisplayName then
                    _G.PRISONRP_GiveMoneyRPcache[player] = humanoid.DisplayName
                    return humanoid.DisplayName
                end

                local containers = {player, character}
                local keys = {"RPName", "RP_Name", "RoleplayName", "CharacterName", "CharName", "PseudoRP", "Pseudo_RP", "NomRP", "Nom_RP"}
                for _, container in ipairs(containers) do
                    if container then
                        for _, key in ipairs(keys) do
                            local attr = container:GetAttribute(key)
                            if typeof(attr) == "string" and attr ~= "" and attr ~= player.Name and attr ~= player.DisplayName then
                                _G.PRISONRP_GiveMoneyRPcache[player] = attr
                                return attr
                            end
                        end
                        for _, obj in ipairs(container:GetChildren()) do
                            if obj:IsA("StringValue") or obj:IsA("TextLabel") then
                                local n = obj.Name:lower()
                                if n:find("rp") or n:find("roleplay") or n:find("charactername")
                                    or n:find("charname") or n:find("pseudorp") or n:find("nomrp") then
                                    local value = obj:IsA("StringValue") and obj.Value or obj.Text
                                    if value and value ~= "" and value ~= player.Name and value ~= player.DisplayName then
                                        _G.PRISONRP_GiveMoneyRPcache[player] = value
                                        return value
                                    end
                                end
                            end
                        end
                    end
                end

                local pg = player:FindFirstChildOfClass("PlayerGui")
                if pg then
                    for _, obj in ipairs(pg:GetDescendants()) do
                        if obj:IsA("TextLabel") and obj.Text and obj.Text ~= "" then
                            local candidate = giveMoneyCleanRPText(obj.Text, player)
                            if candidate then
                                _G.PRISONRP_GiveMoneyRPcache[player] = candidate
                                return candidate
                            end
                        end
                    end
                end

                local fallback = player.DisplayName or player.Name
                _G.PRISONRP_GiveMoneyRPcache[player] = fallback
                return fallback
            end

            local function createGiveMoneyPlayerButton(player)
                local button = Instance.new("TextButton")
                button.Size = UDim2.new(1, -8, 0, 28)
                button.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
                button.BorderSizePixel = 0
                button.Text = giveMoneyGetRPPseudo(player) .. " -- @" .. player.Name
                button.TextColor3 = Color3.fromRGB(255, 255, 255)
                button.TextSize = 10
                button.Font = Enum.Font.Gotham
                button.TextXAlignment = Enum.TextXAlignment.Left
                button.ZIndex = 22
                button.Parent = GiveMoneyList

                local c = Instance.new("UICorner")
                c.CornerRadius = UDim.new(0, 6)
                c.Parent = button

                button.MouseButton1Click:Connect(function()
                    GiveMoneySelectedPlayer = player
                    GiveMoneySelected.Text = "Joueur : " .. giveMoneyGetRPPseudo(player) .. " -- @" .. player.Name

                    for _, v in ipairs(GiveMoneyList:GetChildren()) do
                        if v:IsA("TextButton") then
                            v.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
                        end
                    end

                    button.BackgroundColor3 = Color3.fromRGB(55, 105, 190)
                end)
            end

            local function refreshGiveMoneyPlayers()
                for _, v in ipairs(GiveMoneyList:GetChildren()) do
                    if v:IsA("TextButton") then
                        v:Destroy()
                    end
                end

                local query = string.lower(GiveMoneySearch.Text or "")

                for _, player in ipairs(GiveMoneyPlayers:GetPlayers()) do
                    if player ~= GiveMoneyLocalPlayer then
                        local name1 = string.lower(player.Name)
                        local name2 = string.lower(player.DisplayName)
                        local rpName = string.lower(tostring(giveMoneyGetRPPseudo(player) or ""))

                        if query == ""
                            or string.find(name1, query, 1, true)
                            or string.find(name2, query, 1, true)
                            or string.find(rpName, query, 1, true) then
                            createGiveMoneyPlayerButton(player)
                        end
                    end
                end

                task.defer(function()
                    GiveMoneyList.CanvasSize = UDim2.new(
                        0, 0, 0,
                        GiveMoneyLayout.AbsoluteContentSize.Y + 8
                    )
                end)
            end

            GiveMoneyConnections[#GiveMoneyConnections + 1] = GiveMoneySearch:GetPropertyChangedSignal("Text"):Connect(refreshGiveMoneyPlayers)
            GiveMoneyConnections[#GiveMoneyConnections + 1] = GiveMoneyPlayers.PlayerAdded:Connect(refreshGiveMoneyPlayers)

            GiveMoneyConnections[#GiveMoneyConnections + 1] = GiveMoneyPlayers.PlayerRemoving:Connect(function(player)
                _G.PRISONRP_GiveMoneyRPcache[player] = nil
                if GiveMoneySelectedPlayer == player then
                    GiveMoneySelectedPlayer = nil
                    GiveMoneyRunning = false
                    GiveMoneyRunToken += 1
                    if GiveMoneySelected and GiveMoneySelected.Parent then
                        GiveMoneySelected.Text = "Joueur : aucun"
                    end
                    updateGiveMoneyToggle()
                end
                refreshGiveMoneyPlayers()
            end)

            GiveMoneyToggle.MouseButton1Click:Connect(function()
                if not GiveMoneySelectedPlayer then
                    GiveMoneySelected.Text = "⚠ Sélectionne un joueur"
                    return
                end

                local amount = getGiveMoneyAmount()
                if not amount then
                    GiveMoneySelected.Text = "⚠ Montant invalide"
                    return
                end

                if GiveMoneyRunning then
                    GiveMoneyRunning = false
                    GiveMoneyRunToken += 1
                    updateGiveMoneyToggle()
                    return
                end

                GiveMoneyRunning = true
                GiveMoneyRunToken += 1
                local thisRunToken = GiveMoneyRunToken
                updateGiveMoneyToggle()

                task.spawn(function()
                    while GiveMoneyRunning
                        and thisRunToken == GiveMoneyRunToken
                        and GiveMoneySelectedPlayer do
                        local target = GiveMoneySelectedPlayer

                        if not target.Parent then
                            GiveMoneyRunning = false
                            GiveMoneyRunToken += 1
                            break
                        end

                        -- Lire le montant à chaque cycle afin que l'UI et les requêtes
                        -- restent synchronisées si l'utilisateur modifie le champ en cours.
                        local currentAmount = getGiveMoneyAmount()
                        if not currentAmount then
                            GiveMoneyRunning = false
                            GiveMoneyRunToken += 1
                            if GiveMoneySelected and GiveMoneySelected.Parent then
                                GiveMoneySelected.Text = "⚠ Montant invalide"
                            end
                            updateGiveMoneyToggle()
                            break
                        end

                        pcall(function()
                            GiveMoneyRemote:FireServer(currentAmount, target.UserId)
                        end)

                        task.wait(15)
                    end

                    if thisRunToken == GiveMoneyRunToken then
                        updateGiveMoneyToggle()
                    end
                end)
            end)

            refreshGiveMoneyPlayers()

            -- Expose only the controls needed by the later layout patches.
            _G.PRISONRP_GiveMoneyUI.Frame = GiveMoneyFrame
            _G.PRISONRP_GiveMoneyUI.List = GiveMoneyList
            _G.PRISONRP_GiveMoneyUI.Amount = GiveMoneyAmount
            _G.PRISONRP_GiveMoneyUI.Toggle = GiveMoneyToggle
        end
    end)()


    --==============================================================
    -- FINAL PATCH V135 : ORGANISATION AUTRES
    -- Give Money plus large, en colonne à droite et remonté.
    -- Les boutons AUTRES principaux restent collés à gauche.
    --==============================================================
    pcall(function()
        if _G.PRISONRP_GiveMoneyUI.Frame and autresPage then
            _G.PRISONRP_GiveMoneyUI.Frame.Size = UDim2.fromOffset(205, 430)
            _G.PRISONRP_GiveMoneyUI.Frame.Position = UDim2.new(1, -205, 0, 10)
        end

        if AutoPushupBtn then
            AutoPushupBtn.Position = UDim2.fromOffset(0, 20)
            AutoPushupBtn.Size = UDim2.new(1, -215, 0, 32)
        end

        if BlackMarketBtn then
            BlackMarketBtn.Position = UDim2.fromOffset(0, 58)
            BlackMarketBtn.Size = UDim2.new(1, -215, 0, 32)
        end

        if ESPToggleBtn then
            ESPToggleBtn.Position = UDim2.fromOffset(0, 96)
            ESPToggleBtn.Size = UDim2.new(1, -215, 0, 32)
        end

    end)


    --==============================================================
    -- FINAL PATCH V145 : MISE EN PAGE AUTRES
    -- Cases de gauche remontées + Give Money allongé pour englober
    -- toute la liste, le montant et le bouton ON/OFF.
    --==============================================================
    pcall(function()
        if _G.PRISONRP_GiveMoneyUI.Frame then
            _G.PRISONRP_GiveMoneyUI.Frame.Size = UDim2.fromOffset(205, 430)
            _G.PRISONRP_GiveMoneyUI.Frame.Position = UDim2.new(1, -205, 0, 10)
        end

        if _G.PRISONRP_GiveMoneyUI.List then
            _G.PRISONRP_GiveMoneyUI.List.Size = UDim2.new(1, -12, 0, 215)
        end

        if _G.PRISONRP_GiveMoneyUI.Amount then
            _G.PRISONRP_GiveMoneyUI.Amount.Position = UDim2.fromOffset(6, 316)
        end

        if _G.PRISONRP_GiveMoneyUI.Toggle then
            _G.PRISONRP_GiveMoneyUI.Toggle.Position = UDim2.fromOffset(6, 352)
        end

        if AutoPushupBtn then
            AutoPushupBtn.Position = UDim2.fromOffset(0, 20)
            AutoPushupBtn.Size = UDim2.new(1, -215, 0, 32)
        end

        if BlackMarketBtn then
            BlackMarketBtn.Position = UDim2.fromOffset(0, 58)
            BlackMarketBtn.Size = UDim2.new(1, -215, 0, 32)
        end

        if ESPToggleBtn then
            ESPToggleBtn.Position = UDim2.fromOffset(0, 96)
            ESPToggleBtn.Size = UDim2.new(1, -215, 0, 32)
        end

    end)


    --==============================================================
    -- V146 : Give Money — bouton OFF/ON plus petit et entièrement
    -- contenu dans le panneau.
    --==============================================================
    pcall(function()
        if _G.PRISONRP_GiveMoneyUI.Frame then
            _G.PRISONRP_GiveMoneyUI.Frame.Size = UDim2.fromOffset(205, 430)
        end
        if _G.PRISONRP_GiveMoneyUI.List then
            _G.PRISONRP_GiveMoneyUI.List.Size = UDim2.new(1, -12, 0, 215)
        end
        if _G.PRISONRP_GiveMoneyUI.Amount then
            _G.PRISONRP_GiveMoneyUI.Amount.Size = UDim2.new(1, -12, 0, 30)
            _G.PRISONRP_GiveMoneyUI.Amount.Position = UDim2.fromOffset(6, 316)
        end
        if _G.PRISONRP_GiveMoneyUI.Toggle then
            _G.PRISONRP_GiveMoneyUI.Toggle.Size = UDim2.new(1, -12, 0, 34)
            _G.PRISONRP_GiveMoneyUI.Toggle.Position = UDim2.fromOffset(6, 352)
        end
    end)


    --==============================================================
    -- V149 : STAFF ESP SUPPRIMÉ / AUTO LEAVE DANS AUTRES
    --==============================================================
    pcall(function()
        -- Suppression complète de la case STAFF ESP.
        if StaffESPBtn then
            StaffESPBtn.Visible = false
            StaffESPBtn.Parent = nil
        end

        -- Au cas où une ancienne copie existe encore dans l'interface.
        if Content then
            for _, obj in ipairs(Content:GetDescendants()) do
                if obj:IsA("GuiButton") and (
                    obj.Name == "StaffESPBtn"
                    or string.find(string.lower(obj.Text or ""), "esp staff", 1, true)
                ) then
                    obj.Visible = false
                end
            end
        end

        if espPage then
            for _, obj in ipairs(espPage:GetDescendants()) do
                if obj:IsA("GuiButton") and (
                    obj.Name == "StaffESPBtn"
                    or string.find(string.lower(obj.Text or ""), "esp staff", 1, true)
                ) then
                    obj.Visible = false
                end
            end
        end

        -- Déplacement de la case AUTO LEAVE dans AUTRES.
        if StaffAutoLeaveBtn and autresPage then
            StaffAutoLeaveBtn.Parent = autresPage
            StaffAutoLeaveBtn.Visible = true
            StaffAutoLeaveBtn.Position = UDim2.fromOffset(0, 172)
            StaffAutoLeaveBtn.Size = UDim2.new(1, -215, 0, 32)
            StaffAutoLeaveBtn.TextXAlignment = Enum.TextXAlignment.Center
            StaffAutoLeaveBtn.TextYAlignment = Enum.TextYAlignment.Center
        end
    end)

    --==============================================================
    -- V150 FINAL : ESP JOUEURS REORGANISÉ
    --==============================================================
    pcall(function()
        -- Supprime/masque définitivement l'ancienne case ESP STAFF.
        if StaffESPBtn then
            StaffESPBtn.Visible = false
            StaffESPBtn.Parent = nil
        end

        -- Supprime toute ancienne carte "SURVEILLANCE / MONEY VIEW".
        if MainFrame then
            for _, obj in ipairs(MainFrame:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Text == "🛡 SURVEILLANCE / MONEY VIEW" then
                    local p = obj.Parent
                    if p then
                        p.Visible = false
                    end
                end
            end
        end
    end)


    --==============================================================
    -- V175 : AUTRES — tout le contenu passe sous la barre du titre
    -- La ligne de section "AUTRES" est à Y=20 ; aucun élément visible
    -- ne doit donc commencer au-dessus ou sur cette ligne.
    --==============================================================
    pcall(function()
        local autresContentTop = 30

        if _G.PRISONRP_GiveMoneyUI.Frame then
            _G.PRISONRP_GiveMoneyUI.Frame.Position = UDim2.new(1, -205, 0, autresContentTop)
        end

        if AutoPushupBtn then
            AutoPushupBtn.Position = UDim2.fromOffset(0, autresContentTop)
        end

        if BlackMarketBtn then
            BlackMarketBtn.Position = UDim2.fromOffset(0, autresContentTop + 38)
        end

        if ESPToggleBtn then
            ESPToggleBtn.Position = UDim2.fromOffset(0, autresContentTop + 76)
        end


        if StaffAutoLeaveBtn then
            StaffAutoLeaveBtn.Position = UDim2.fromOffset(0, autresContentTop + 114)
        end
    end)

    --==============================================================
    -- V176 FINAL : GIVE MONEY SOUS LA BARRE AUTRES
    -- Le panneau est recréé localement dans le bloc Give Money, donc on
    -- le récupère par son nom ici pour garantir le déplacement final.
    --==============================================================
    pcall(function()
        if autresPage then
            local giveMoneyPanel = autresPage:FindFirstChild("GiveMoneyPanel")
            if giveMoneyPanel then
                giveMoneyPanel.Position = UDim2.new(1, -205, 0, 34)
            end
        end
    end)

    --==============================================================
    -- V167 FINAL : AUTO MINE — TP DÉPART + SUIVI PROGRESSIF
    --==============================================================
    pcall(function()
        -- Rien à faire ici : la position de départ est appliquée par
        -- autoMineTeleportToMineStart() uniquement au lancement.
        -- Les roches suivantes restent suivies avec autoMineFlyToPosition().
    end)



    --==============================================================
    -- V179 FINAL : CASES DE GAUCHE AUTRES — MÊMES DIMENSIONS + ÉCART UNIFORME
    --==============================================================
    pcall(function()
        local top = 30
        local commonHeight = 34
        local gap = 6
        local step = commonHeight + gap
        -- 8 px de marge avec le panneau Give Money à droite.
        -- Les 5 cases restantes gardent les mêmes dimensions et le même écart.
        local commonSize = UDim2.new(1, -213, 0, commonHeight)

        if AutoPushupBtn then
            AutoPushupBtn.Parent = autresPage
            AutoPushupBtn.Position = UDim2.fromOffset(0, top)
            AutoPushupBtn.Size = commonSize
        end

        if BlackMarketBtn then
            BlackMarketBtn.Parent = autresPage
            BlackMarketBtn.Position = UDim2.fromOffset(0, top + step)
            BlackMarketBtn.Size = commonSize
        end

        if ESPToggleBtn then
            ESPToggleBtn.Parent = autresPage
            ESPToggleBtn.Position = UDim2.fromOffset(0, top + step * 2)
            ESPToggleBtn.Size = commonSize
        end

        if StaffAutoLeaveBtn then
            StaffAutoLeaveBtn.Parent = autresPage
            StaffAutoLeaveBtn.Position = UDim2.fromOffset(0, top + step * 3)
            StaffAutoLeaveBtn.Size = commonSize
        end

        if AutoArmWrestleState.Btn then
            AutoArmWrestleState.Btn.Parent = autresPage
            AutoArmWrestleState.Btn.Position = UDim2.fromOffset(0, top + step * 4)
            AutoArmWrestleState.Btn.Size = commonSize
        end
    end)


    --==============================================================
    -- V178 FINAL : AUTRES — TP BLACK MARKET / ESP BLACK MARKET
    -- mêmes couleurs neutres que les autres cases + GIVE MONEY aligné
    -- avec AUTO POMPES.
    --==============================================================
    pcall(function()
        local neutral = Color3.fromRGB(45, 48, 62)
        local white = Color3.fromRGB(255, 255, 255)

        if BlackMarketBtn then
            BlackMarketBtn.BackgroundColor3 = neutral
            BlackMarketBtn.TextColor3 = white
        end

        if ESPToggleBtn then
            ESPToggleBtn.BackgroundColor3 = neutral
            ESPToggleBtn.TextColor3 = white
        end

        if _G.PRISONRP_GiveMoneyUI.Frame then
            _G.PRISONRP_GiveMoneyUI.Frame.Position = UDim2.new(1, -205, 0, 30)
        elseif autresPage then
            local giveMoneyPanel = autresPage:FindFirstChild("GiveMoneyPanel")
            if giveMoneyPanel then
                giveMoneyPanel.Position = UDim2.new(1, -205, 0, 30)
            end
        end
    end)



    --==============================================================
    -- V186 FINAL : même typographie que START AUTO-FISH
    -- Cases demandées : SPEEDHACK, FLY, NOCLIP, INVISIBLE, FREECAM, SPEC, TP,
    -- AUTO POMPES, TP BLACK MARKET, ESP BLACK MARKET et AUTO-LEAVE.
    --==============================================================
    pcall(function()
        local function applyStartAutoFishTextStyle(obj)
            if not obj then return end
            obj.Font = Enum.Font.GothamBold
            obj.TextSize = 15
            obj.TextColor3 = C.white
            obj.TextStrokeTransparency = 1
            obj.TextXAlignment = Enum.TextXAlignment.Center
            obj.TextYAlignment = Enum.TextYAlignment.Center
        end

        for _, obj in ipairs({
            flyBtn,
            noclipBtn,
            InvisibleCard,
            SpecCard,
            tpSpecButton,
            tpButton,
            AutoPushupBtn,
            BlackMarketBtn,
            ESPToggleBtn,
            StaffAutoLeaveBtn,
            AutoArmWrestleState.Btn,
            speedBtn,
            speedLabel,
            ToggleFishBtn,
        }) do
            applyStartAutoFishTextStyle(obj)
        end

        -- SPEEDHACK : le texte visible est le TextLabel speedLabel.
        if speedLabel then
            speedLabel.Font = Enum.Font.GothamBold
            speedLabel.TextSize = 15
            speedLabel.TextColor3 = C.white
            speedLabel.TextStrokeTransparency = 1
            speedLabel.TextXAlignment = Enum.TextXAlignment.Center
            speedLabel.TextYAlignment = Enum.TextYAlignment.Center
        end
    end)

end) -- ferme le pcall principal ouvert ligne 2812

--==============================================================
-- AIMBOT NEPTUNE -> PRISON RP FR GDP
--==============================================================
do
--[[
    Aimbot Neptune - CLEAN + UI
    Rebuilt from the deobfuscated Neptune configuration.

    UI Neptune originale retirée : les réglages sont intégrés dans un seul onglet AIMBOT du hub PRISON RP FR GDP.

    RightShift = afficher/masquer le hub

    NOTE:
    This version uses executor-side APIs such as getgenv(), Drawing and
    mousemoverel(), so it is not intended for normal Roblox Studio LocalScripts.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--------------------------------------------------
-- CLEAN OLD INSTANCE
--------------------------------------------------

if _G.PRISONRP_AIMBOT_STOP then
    pcall(_G.PRISONRP_AIMBOT_STOP)
end

local Aimbot = {}
_G.PRISONRP_AIMBOT = Aimbot

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

Aimbot.Settings = {
    Enabled = false,
    Toggle = false,
    LockPart = "Head",
    TriggerKey = "MouseButton2",
    Sensitivity = 0,

    TeamCheck = false,
    WallCheck = false,
    AliveCheck = true,

    ThirdPerson = false,
    ThirdPersonSensitivity = 3
}

Aimbot.FOVSettings = {
    Enabled = true,
    Visible = true,
    Amount = 90,
    Filled = false,
    Transparency = 0.5,
    Sides = 60,
    Thickness = 1,

    Color = Color3.fromRGB(255, 255, 255),
    LockedColor = Color3.fromRGB(255, 70, 70)
}

local BodyParts = {
    "Head",
    "HumanoidRootPart",
    "Torso",
    "Left Arm",
    "Right Arm",
    "Left Leg",
    "Right Leg",
    "LeftHand",
    "RightHand",
    "LeftLowerArm",
    "RightLowerArm",
    "LeftUpperArm",
    "RightUpperArm",
    "LeftFoot",
    "UpperTorso",
    "LeftUpperLeg",
    "RightFoot",
    "RightLowerLeg",
    "LowerTorso",
    "RightUpperLeg"
}

--------------------------------------------------
-- STATE
--------------------------------------------------

local Running = false
local Typing = false
local Locked = nil
local Tween = nil
local Connections = {}

--------------------------------------------------
-- FOV CIRCLE
--------------------------------------------------

local FOVCircle = nil
if Drawing and type(Drawing.new) == "function" then
    pcall(function()
        FOVCircle = Drawing.new("Circle")
    end)
end

local function UpdateFOV()
    if not FOVCircle then return end
    FOVCircle.Radius = Aimbot.FOVSettings.Amount
    FOVCircle.Thickness = Aimbot.FOVSettings.Thickness
    FOVCircle.Filled = Aimbot.FOVSettings.Filled
    FOVCircle.NumSides = Aimbot.FOVSettings.Sides
    FOVCircle.Color = Aimbot.FOVSettings.Color
    FOVCircle.Transparency = Aimbot.FOVSettings.Transparency
    FOVCircle.Visible =
        Aimbot.FOVSettings.Enabled
        and Aimbot.FOVSettings.Visible
        and Aimbot.Settings.Enabled
end

UpdateFOV()

--------------------------------------------------
-- AIM FUNCTIONS
--------------------------------------------------

local function CancelLock()
    Locked = nil
    Aimbot.Locked = nil

    if Tween then
        pcall(function()
            Tween:Cancel()
        end)
        Tween = nil
    end

    if FOVCircle then
        FOVCircle.Color = Aimbot.FOVSettings.Color
    end
end

local function GetClosestPlayer()
    if Locked then
        return
    end

    local RequiredDistance =
        Aimbot.FOVSettings.Enabled
        and Aimbot.FOVSettings.Amount
        or 2000

    local Mouse = UserInputService:GetMouseLocation()
    local MousePosition = Vector2.new(Mouse.X, Mouse.Y)

    for _, Player in ipairs(Players:GetPlayers()) do
        if Player == LocalPlayer then
            continue
        end

        local Character = Player.Character
        if not Character then
            continue
        end

        local Part =
            Character:FindFirstChild(Aimbot.Settings.LockPart)

        local Humanoid =
            Character:FindFirstChildOfClass("Humanoid")

        if not Part or not Humanoid then
            continue
        end

        if Aimbot.Settings.TeamCheck
            and Player.Team == LocalPlayer.Team then
            continue
        end

        if Aimbot.Settings.AliveCheck
            and Humanoid.Health <= 0 then
            continue
        end

        if Aimbot.Settings.WallCheck then
            local Parts = Camera:GetPartsObscuringTarget(
                {Part.Position},
                Character:GetDescendants()
            )

            if #Parts > 0 then
                continue
            end
        end

        local ScreenPosition, OnScreen =
            Camera:WorldToViewportPoint(Part.Position)

        if not OnScreen then
            continue
        end

        local Target =
            Vector2.new(ScreenPosition.X, ScreenPosition.Y)

        local Distance =
            (MousePosition - Target).Magnitude

        if Distance < RequiredDistance then
            RequiredDistance = Distance
            Locked = Player
            Aimbot.Locked = Player
        end
    end
end

--------------------------------------------------
-- INPUT
--------------------------------------------------

Connections.TextBoxFocused =
    UserInputService.TextBoxFocused:Connect(function()
        Typing = true
    end)

Connections.TextBoxReleased =
    UserInputService.TextBoxFocusReleased:Connect(function()
        Typing = false
    end)

local function IsTrigger(Input)
    local Key = tostring(Aimbot.Settings.TriggerKey or "")

    -- Mouse buttons (ex: MouseButton2) appartiennent à Enum.UserInputType,
    -- pas à Enum.KeyCode. On teste donc UserInputType en premier et sans
    -- indexation directe qui ferait planter le script si le nom n'existe pas.
    local MouseInputType = nil
    pcall(function()
        MouseInputType = Enum.UserInputType[Key]
    end)

    if MouseInputType and Input.UserInputType == MouseInputType then
        return true
    end

    -- Les touches clavier appartiennent à Enum.KeyCode.
    local KeyCode = nil
    pcall(function()
        KeyCode = Enum.KeyCode[Key]
    end)

    if KeyCode and Input.KeyCode == KeyCode then
        return true
    end

    return false
end

Connections.InputBegan =
    UserInputService.InputBegan:Connect(function(Input)
        if Typing then
            return
        end

        if IsTrigger(Input) then
            if Aimbot.Settings.Toggle then
                Running = not Running

                if not Running then
                    CancelLock()
                end
            else
                Running = true
            end
        end
    end)

Connections.InputEnded =
    UserInputService.InputEnded:Connect(function(Input)
        if Typing or Aimbot.Settings.Toggle then
            return
        end

        if IsTrigger(Input) then
            Running = false
            CancelLock()
        end
    end)

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

Connections.RenderStepped =
    RunService.RenderStepped:Connect(function()
        local Mouse = UserInputService:GetMouseLocation()

        if FOVCircle then
            FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
        end

        UpdateFOV()

        if not Running or not Aimbot.Settings.Enabled then
            return
        end

        GetClosestPlayer()

        if not Locked then
            return
        end

        local Character = Locked.Character

        if not Character then
            CancelLock()
            return
        end

        local Part =
            Character:FindFirstChild(
                Aimbot.Settings.LockPart
            )

        if not Part then
            CancelLock()
            return
        end

        local Humanoid =
            Character:FindFirstChildOfClass("Humanoid")

        if not Humanoid
            or (Aimbot.Settings.AliveCheck
                and Humanoid.Health <= 0) then
            CancelLock()
            return
        end

        if Aimbot.Settings.ThirdPerson then
            local Screen =
                Camera:WorldToViewportPoint(Part.Position)

            local X = Screen.X - Mouse.X
            local Y = Screen.Y - Mouse.Y

            local Sens =
                math.clamp(
                    Aimbot.Settings.ThirdPersonSensitivity,
                    0.1,
                    5
                )

            if type(mousemoverel) == "function" then
                mousemoverel(X * Sens, Y * Sens)
            end
        else
            local Sens =
                Aimbot.Settings.Sensitivity

            if Sens > 0 then
                Tween = TweenService:Create(
                    Camera,
                    TweenInfo.new(
                        Sens,
                        Enum.EasingStyle.Sine,
                        Enum.EasingDirection.Out
                    ),
                    {
                        CFrame = CFrame.new(
                            Camera.CFrame.Position,
                            Part.Position
                        )
                    }
                )

                Tween:Play()
            else
                Camera.CFrame =
                    CFrame.new(
                        Camera.CFrame.Position,
                        Part.Position
                    )
            end
        end

        if FOVCircle then
            FOVCircle.Color = Aimbot.FOVSettings.LockedColor
        end
    end)



--------------------------------------------------
-- PRISON RP FR GDP : AIMBOT INTEGRATION
-- Une seule page, même thème que le hub, sans onglet "Fonctions" Neptune.
--------------------------------------------------

local AIM_C = {
    bg = Color3.fromRGB(16, 19, 25),
    panel = Color3.fromRGB(22, 27, 35),
    card = Color3.fromRGB(31, 38, 48),
    card2 = Color3.fromRGB(38, 46, 58),
    border = Color3.fromRGB(62, 73, 88),
    accent = Color3.fromRGB(38, 135, 235),
    white = Color3.fromRGB(255, 255, 255),
    soft = Color3.fromRGB(238, 241, 245),
    muted = Color3.fromRGB(165, 174, 188),
    off = Color3.fromRGB(70, 80, 94),
    on = Color3.fromRGB(40, 145, 78),
}

local mainHub = MainFrame
local v7Body = mainHub and mainHub:FindFirstChild("V7Body")
local v7Sidebar = v7Body and v7Body:FindFirstChild("V7Sidebar")
local v7Marker, v7Glow
if v7Sidebar then
    for _, child in ipairs(v7Sidebar:GetChildren()) do
        if child:IsA("Frame") and child.Size == UDim2.fromOffset(2, 22) then
            if child.BackgroundTransparency < 0.5 and not v7Marker then
                v7Marker = child
            elseif child.BackgroundTransparency >= 0.5 and not v7Glow then
                v7Glow = child
            end
        end
    end
end

-- Page Aimbot : même zone de contenu que les 4 autres pages.
local aimPage = Instance.new("ScrollingFrame")
aimPage.Name = "AimbotPage"
aimPage.Parent = v7Body or mainHub
aimPage.BackgroundTransparency = 1
aimPage.BorderSizePixel = 0
aimPage.ScrollBarThickness = 3
aimPage.ScrollBarImageColor3 = Color3.fromRGB(79, 142, 255)
aimPage.CanvasSize = UDim2.new(0, 0, 0, 0)
aimPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
aimPage.ScrollingDirection = Enum.ScrollingDirection.Y
aimPage.ZIndex = 91
aimPage.Visible = false

local aimPadding = Instance.new("UIPadding")
aimPadding.PaddingLeft = UDim.new(0, 2)
aimPadding.PaddingRight = UDim.new(0, 2)
aimPadding.PaddingTop = UDim.new(0, 0)
aimPadding.PaddingBottom = UDim.new(0, 4)
aimPadding.Parent = aimPage

local aimLayout = Instance.new("UIListLayout")
aimLayout.Padding = UDim.new(0, 5)
aimLayout.SortOrder = Enum.SortOrder.LayoutOrder
aimLayout.Parent = aimPage

aimLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    aimPage.CanvasSize = UDim2.fromOffset(0, aimLayout.AbsoluteContentSize.Y + 8)
end)

local function fitAimPage()
    if not aimPage or not v7Body then return end
    local scale = (MainFrameScale and MainFrameScale.Scale) or 1
    local bodyW = v7Body.AbsoluteSize.X / scale
    local bodyH = v7Body.AbsoluteSize.Y / scale
    local open = v7Sidebar and ((v7Sidebar.AbsoluteSize.X / scale) >= 100) or false
    local x = open and 155 or 57
    local width = math.max(100, bodyW - x - 10)
    aimPage.Position = UDim2.fromOffset(x, 8)
    aimPage.Size = UDim2.fromOffset(width, math.max(100, bodyH - 16))
end

fitAimPage()

task.defer(function()
    task.wait()
    fitAimPage()
end)

if v7Sidebar then
    v7Sidebar:GetPropertyChangedSignal("Size"):Connect(function()
        fitAimPage()
    end)
end

local function aimStroke(obj)
    local s = Instance.new("UIStroke")
    s.Color = AIM_C.border
    s.Transparency = 0.35
    s.Thickness = 1
    s.Parent = obj
    return s
end

local function aimCorner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 7)
    c.Parent = obj
    return c
end

local function aimSection(_text)
    -- V220 : aucun élément vide pour les titres masqués.
    -- Les faux en-têtes occupaient encore des interstices dans l'UIListLayout.
    return nil
end

local function newRow(height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, height)
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.ZIndex = 93
    row.LayoutOrder = 1
    row.Parent = aimPage
    return row
end

local function cardBase(parent, x, width, height)
    local card = Instance.new("TextButton")
    card.Size = UDim2.new(width, -6, 0, height)
    card.Position = UDim2.new(x, x == 0 and 0 or 6, 0, 0)
    card.BackgroundColor3 = AIM_C.card
    card.Text = ""
    card.AutoButtonColor = false
    card.BorderSizePixel = 0
    card.ZIndex = 94
    card.Parent = parent
    aimCorner(card, 7)
    aimStroke(card)
    return card
end

_G.PRISONRP_AIM_CONTROLS = {}
local function registerAimControl(kind, text, getter, setter, refresh)
    table.insert(_G.PRISONRP_AIM_CONTROLS, {Kind=kind, Name=text, Get=getter, Set=setter, Refresh=refresh})
end

local function addToggle(parent, x, text, getter, setter)
    local card = cardBase(parent, x, 0.5, 36)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -50, 1, 0)
    label.Position = UDim2.fromOffset(5, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = AIM_C.white
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ZIndex = 95
    label.Parent = card

    local sw = Instance.new("Frame")
    sw.Size = UDim2.fromOffset(38, 20)
    sw.Position = UDim2.new(1, -44, 0.5, -10)
    sw.BackgroundColor3 = AIM_C.off
    sw.BorderSizePixel = 0
    sw.ZIndex = 96
    sw.Parent = card
    aimCorner(sw, 99)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14, 14)
    knob.Position = UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = AIM_C.white
    knob.BorderSizePixel = 0
    knob.ZIndex = 97
    knob.Parent = sw
    aimCorner(knob, 99)

    local function refresh()
        local on = getter()
        game:GetService("TweenService"):Create(sw, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = on and AIM_C.on or AIM_C.off
        }):Play()
        game:GetService("TweenService"):Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = on and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
        }):Play()
    end

    card.MouseButton1Click:Connect(function()
        setter(not getter())
        refresh()
    end)
    refresh()
    registerAimControl("toggle", text, getter, setter, refresh)
    return card
end

local function addCycle(parent, x, text, getter, setter, list)
    local card = cardBase(parent, x, 0.5, 36)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.58, 0, 1, 0)
    label.Position = UDim2.fromOffset(6, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = AIM_C.white
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.ZIndex = 95
    label.Parent = card

    local value = Instance.new("TextLabel")
    value.Size = UDim2.new(0.38, -6, 1, -8)
    value.Position = UDim2.new(0.60, 0, 0, 4)
    value.BackgroundColor3 = Color3.fromRGB(22, 27, 35)
    value.TextColor3 = AIM_C.soft
    value.TextSize = 10
    value.Font = Enum.Font.GothamMedium
    value.TextXAlignment = Enum.TextXAlignment.Center
    value.TextYAlignment = Enum.TextYAlignment.Center
    value.BorderSizePixel = 0
    value.ZIndex = 96
    value.Parent = card
    aimCorner(value, 5)

    local index = 1
    for i, v in ipairs(list) do
        if v == getter() then index = i break end
    end

    local function refresh()
        value.Text = tostring(getter())
    end

    card.MouseButton1Click:Connect(function()
        index = index + 1
        if index > #list then index = 1 end
        setter(list[index])
        refresh()
    end)
    refresh()
    registerAimControl("cycle", text, getter, setter, refresh)
    return card
end

local function addTextbox(parent, x, text, getter, setter)
    local card = cardBase(parent, x, 0.5, 36)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.42, 0, 1, 0)
    label.Position = UDim2.fromOffset(6, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = AIM_C.white
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.ZIndex = 95
    label.Parent = card

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.44, -2, 0, 26)
    box.Position = UDim2.new(0.50, 0, 0.5, -13)
    box.BackgroundColor3 = Color3.fromRGB(22, 27, 35)
    box.TextColor3 = AIM_C.soft
    box.PlaceholderColor3 = AIM_C.muted
    box.TextSize = 10
    box.Font = Enum.Font.GothamMedium
    box.Text = tostring(getter())
    box.ClearTextOnFocus = false
    box.BorderSizePixel = 0
    box.ZIndex = 96
    box.Parent = card
    aimCorner(box, 5)

    box.FocusLost:Connect(function()
        if box.Text ~= "" then setter(box.Text) end
        box.Text = tostring(getter())
    end)
    registerAimControl("textbox", text, getter, setter, function() box.Text = tostring(getter()) end)
    return card
end

local function addSlider(parent, x, text, getter, setter, minValue, maxValue, decimals)
    local card = cardBase(parent, x, 0.5, 52)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -14, 0, 20)
    label.Position = UDim2.fromOffset(7, 2)
    label.BackgroundTransparency = 1
    label.TextColor3 = AIM_C.white
    label.TextSize = 11
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 95
    label.Parent = card

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -14, 0, 6)
    bar.Position = UDim2.fromOffset(7, 38)
    bar.BackgroundColor3 = AIM_C.off
    bar.BorderSizePixel = 0
    bar.ZIndex = 95
    bar.Parent = card
    aimCorner(bar, 99)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = AIM_C.accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 96
    fill.Parent = bar
    aimCorner(fill, 99)

    local dragging = false
    local function refresh()
        local v = getter()
        local alpha = math.clamp((v - minValue) / (maxValue - minValue), 0, 1)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        local fmt = "%.." -- replaced below
        if decimals == 0 then
            label.Text = string.format("%s  %d", text, math.floor(v + 0.5))
        else
            label.Text = string.format("%s  %%.%df", text, decimals):format(v)
        end
    end

    local function setFromX(px)
        local alpha = math.clamp((px - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
        local v = minValue + (maxValue - minValue) * alpha
        if decimals == 0 then
            v = math.floor(v + 0.5)
        else
            local m = 10 ^ decimals
            v = math.floor(v * m + 0.5) / m
        end
        setter(v)
        refresh()
    end

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    refresh()
    registerAimControl("slider", text, getter, setter, refresh)
    return card
end

local function addColorCycle(parent, x, text, getter, setter)
    local colors = {
        Color3.fromRGB(255,255,255),
        Color3.fromRGB(255,70,70),
        Color3.fromRGB(79,142,255),
        Color3.fromRGB(80,220,120),
        Color3.fromRGB(255,210,50),
        Color3.fromRGB(190,80,255),
    }
    local card = cardBase(parent, x, 0.5, 36)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.72, 0, 1, 0)
    label.Position = UDim2.fromOffset(5, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = AIM_C.white
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = card

    local preview = Instance.new("Frame")
    preview.Size = UDim2.fromOffset(28, 22)
    preview.Position = UDim2.new(1, -35, 0.5, -11)
    preview.BackgroundColor3 = getter()
    preview.BorderSizePixel = 0
    preview.Parent = card
    aimCorner(preview, 5)

    local idx = 1
    for i, c in ipairs(colors) do
        if c == getter() then idx = i break end
    end
    card.MouseButton1Click:Connect(function()
        idx = idx + 1
        if idx > #colors then idx = 1 end
        setter(colors[idx])
        preview.BackgroundColor3 = getter()
        UpdateFOV()
    end)
    registerAimControl("color", text, getter, setter, function() preview.BackgroundColor3 = getter() end)
    return card
end

local function addAction(parent, x, text, callback)
    local card = cardBase(parent, x, 0.5, 36)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = AIM_C.white
    label.TextSize = 12
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = card
    card.MouseButton1Click:Connect(callback)
    return card
end

-- V220 : la bannière interne AIMBOT est retirée pour placer les réglages
-- directement en haut de la page et libérer de la place utile.

-- Compact rows : aucun onglet Neptune séparé pour les fonctions.
aimSection("AIMBOT")
local r1 = newRow(36)
addToggle(r1, 0, "AIMBOT", function() return Aimbot.Settings.Enabled end, function(v)
    Aimbot.Settings.Enabled = v
    if not v then Running = false; CancelLock() end
    UpdateFOV()
end)
addToggle(r1, 0.5, "TOGGLE", function() return Aimbot.Settings.Toggle end, function(v)
    Aimbot.Settings.Toggle = v
end)

local r2 = newRow(36)
addCycle(r2, 0, "LOCK PART", function() return Aimbot.Settings.LockPart end, function(v)
    Aimbot.Settings.LockPart = v
    CancelLock()
end, BodyParts)
addTextbox(r2, 0.5, "HOTKEY", function() return Aimbot.Settings.TriggerKey end, function(v)
    Aimbot.Settings.TriggerKey = v
    CancelLock()
end)

local r3 = newRow(52)
addSlider(r3, 0, "SENSIBILITÉ", function() return Aimbot.Settings.Sensitivity end, function(v) Aimbot.Settings.Sensitivity = v end, 0, 1, 2)
addSlider(r3, 0.5, "3P SENS", function() return Aimbot.Settings.ThirdPersonSensitivity end, function(v) Aimbot.Settings.ThirdPersonSensitivity = v end, 0.1, 5, 1)

aimSection("CHECKS")
local r4 = newRow(36)
addToggle(r4, 0, "TEAM CHECK", function() return Aimbot.Settings.TeamCheck end, function(v) Aimbot.Settings.TeamCheck = v; CancelLock() end)
addToggle(r4, 0.5, "WALL CHECK", function() return Aimbot.Settings.WallCheck end, function(v) Aimbot.Settings.WallCheck = v; CancelLock() end)
local r5 = newRow(36)
addToggle(r5, 0, "ALIVE CHECK", function() return Aimbot.Settings.AliveCheck end, function(v) Aimbot.Settings.AliveCheck = v; CancelLock() end)
addToggle(r5, 0.5, "3E PERSONNE", function() return Aimbot.Settings.ThirdPerson end, function(v) Aimbot.Settings.ThirdPerson = v end)

aimSection("FOV")
local r6 = newRow(36)
addToggle(r6, 0, "FOV", function() return Aimbot.FOVSettings.Enabled end, function(v) Aimbot.FOVSettings.Enabled = v; CancelLock(); UpdateFOV() end)
addToggle(r6, 0.5, "FOV VISIBLE", function() return Aimbot.FOVSettings.Visible end, function(v) Aimbot.FOVSettings.Visible = v; UpdateFOV() end)
local r7 = newRow(52)
addSlider(r7, 0, "FOV SIZE", function() return Aimbot.FOVSettings.Amount end, function(v) Aimbot.FOVSettings.Amount = v; UpdateFOV() end, 10, 300, 0)
addSlider(r7, 0.5, "TRANSPARENCE", function() return Aimbot.FOVSettings.Transparency end, function(v) Aimbot.FOVSettings.Transparency = v; UpdateFOV() end, 0, 1, 1)
local r8 = newRow(52)
addSlider(r8, 0, "SIDES", function() return Aimbot.FOVSettings.Sides end, function(v) Aimbot.FOVSettings.Sides = v; UpdateFOV() end, 3, 60, 0)
addSlider(r8, 0.5, "ÉPAISSEUR", function() return Aimbot.FOVSettings.Thickness end, function(v) Aimbot.FOVSettings.Thickness = v; UpdateFOV() end, 1, 20, 0)
local r9 = newRow(36)
addToggle(r9, 0, "FOV REMPLI", function() return Aimbot.FOVSettings.Filled end, function(v) Aimbot.FOVSettings.Filled = v; UpdateFOV() end)
addColorCycle(r9, 0.5, "COULEUR", function() return Aimbot.FOVSettings.Color end, function(v) Aimbot.FOVSettings.Color = v end)
local r10 = newRow(36)
addColorCycle(r10, 0, "COULEUR LOCK", function() return Aimbot.FOVSettings.LockedColor end, function(v) Aimbot.FOVSettings.LockedColor = v end)
addAction(r10, 0.5, "RESET", function()
    Aimbot.Settings.Enabled = true
    Aimbot.Settings.Toggle = false
    Aimbot.Settings.LockPart = "Head"
    Aimbot.Settings.TriggerKey = "MouseButton2"
    Aimbot.Settings.Sensitivity = 0
    Aimbot.Settings.TeamCheck = false
    Aimbot.Settings.WallCheck = false
    Aimbot.Settings.AliveCheck = true
    Aimbot.Settings.ThirdPerson = false
    Aimbot.Settings.ThirdPersonSensitivity = 3
    Aimbot.FOVSettings.Enabled = true
    Aimbot.FOVSettings.Visible = true
    Aimbot.FOVSettings.Amount = 90
    Aimbot.FOVSettings.Filled = false
    Aimbot.FOVSettings.Transparency = 0.5
    Aimbot.FOVSettings.Sides = 60
    Aimbot.FOVSettings.Thickness = 1
    Aimbot.FOVSettings.Color = Color3.fromRGB(255,255,255)
    Aimbot.FOVSettings.LockedColor = Color3.fromRGB(255,70,70)
    Running = false
    CancelLock()
    UpdateFOV()
end)

aimSection("ACTIONS")
local r11 = newRow(36)
addAction(r11, 0, "RESTART AIMBOT", function()
    Running = false
    CancelLock()
    UpdateFOV()
end)
addAction(r11, 0.5, "STOP AIMBOT", function()
    Running = false
    CancelLock()
    UpdateFOV()
end)

-- Diagnostic discret : ne rajoute pas de texte dans la page Aimbot.
if not FOVCircle then
    warn("[PRISON RP Aimbot] Drawing indisponible : le FOV ne peut pas être affiché dans cet executor.")
end

-- AIMBOT SIDEBAR : même mécanique que la sidebar GDP, sans créer une UI Neptune parallèle.
if v7Sidebar then
    local oldAimbotTab = v7Sidebar:FindFirstChild("V7Tab_Aimbot")
    if oldAimbotTab then oldAimbotTab:Destroy() end

    local aimTab = Instance.new("TextButton")
    aimTab.Name = "V7Tab_Aimbot"
    aimTab.Parent = v7Sidebar
    aimTab.Position = UDim2.fromOffset(6, 5 + (4 * 31))
    aimTab.Size = UDim2.fromOffset(31, 27)
    aimTab.BackgroundColor3 = Color3.fromRGB(25, 29, 37)
    aimTab.BackgroundTransparency = 1
    aimTab.BorderSizePixel = 0
    aimTab.AutoButtonColor = false
    aimTab.Text = ""
    aimTab.ZIndex = 102
    aimCorner(aimTab, 4)

    local aimIcon = Instance.new("TextLabel")
    aimIcon.Name = "V7Icon"
    aimIcon.Parent = aimTab
    aimIcon.Position = UDim2.fromOffset(0, -2)
    aimIcon.Size = UDim2.fromOffset(31, 31)
    aimIcon.BackgroundTransparency = 1
    aimIcon.Text = "🎯"
    aimIcon.TextColor3 = Color3.fromRGB(92, 97, 108)
    aimIcon.Font = Enum.Font.GothamBold
    aimIcon.TextSize = 18
    aimIcon.TextXAlignment = Enum.TextXAlignment.Center
    aimIcon.TextYAlignment = Enum.TextYAlignment.Center
    aimIcon.ZIndex = 103

    local aimLabel = Instance.new("TextLabel")
    aimLabel.Name = "V7Label"
    aimLabel.Parent = aimTab
    aimLabel.Position = UDim2.fromOffset(36, 0)
    aimLabel.Size = UDim2.new(1, -40, 1, 0)
    aimLabel.BackgroundTransparency = 1
    aimLabel.Text = "AIMBOT"
    aimLabel.TextColor3 = Color3.fromRGB(116,121,132)
    aimLabel.Font = Enum.Font.GothamBold
    aimLabel.TextSize = 11
    aimLabel.TextXAlignment = Enum.TextXAlignment.Left
    aimLabel.TextTransparency = 1
    aimLabel.ZIndex = 103

    local function styleAimbotTab(active)
        if not aimTab or not aimTab.Parent then return end
        aimTab.BackgroundTransparency = active and 0.72 or 1
        aimIcon.TextColor3 = active and Color3.fromRGB(132,165,230) or Color3.fromRGB(92,97,108)
        if active then
            for i = 1, 4 do
                local b = v7Sidebar:FindFirstChild("V7Tab_" .. tostring(i))
                local icon = b and b:FindFirstChild("V7Icon")
                if b then b.BackgroundTransparency = 1 end
                if icon then icon.TextColor3 = Color3.fromRGB(92,97,108) end
            end
        end
        if active then
            if v7Marker then
                v7Marker.Position = UDim2.fromOffset(0, aimTab.Position.Y.Offset + 5)
            end
            if v7Glow then
                v7Glow.Position = UDim2.fromOffset(0, aimTab.Position.Y.Offset + 5)
            end
        end
    end

    local function showAimbotPage()
        if not aimPage or not aimPage.Parent then return end
        local pages = {
            v7Body:FindFirstChild("V7Content") or v7Body:FindFirstChild("Content") or mainHub:FindFirstChild("Content"),
            v7Body:FindFirstChild("OmegaOthersPage"),
            v7Body:FindFirstChild("OmegaESPPage"),
            v7Body:FindFirstChild("OmegaAutresPage"),
        }
        -- Les 4 pages ont été reparentées dans V7Body ; on identifie aussi par références de nom.
        for _, page in ipairs(pages) do
            if page and page:IsA("GuiObject") then page.Visible = false end
        end
        -- Content n'est pas toujours nommé V7Content : récupérer les pages visibles par leurs noms connus.
        for _, child in ipairs(v7Body:GetChildren()) do
            if child:IsA("GuiObject") and child ~= v7Sidebar and child ~= aimPage then
                if child.Name == "OmegaOthersPage" or child.Name == "OmegaESPPage" or child.Name == "OmegaAutresPage" or child.Name == "Content" then
                    child.Visible = false
                end
            end
        end
        aimPage.Visible = true
        _G.PRISONRP_ACTIVE_UI_PAGE = 5
        if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
            pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, 5)
        end
        fitAimPage()
        styleAimbotTab(true)
    end

    aimTab.MouseButton1Click:Connect(showAimbotPage)
    aimTab.MouseEnter:Connect(function()
        if type(_G.PRISONRP_V7_SET_EXPANDED) == "function" then
            _G.PRISONRP_V7_SET_EXPANDED(true)
        end
        fitAimPage()
    end)

    local existingTabs = {}
    for i = 1, 4 do
        local b = v7Sidebar:FindFirstChild("V7Tab_" .. tostring(i))
        if b then
            existingTabs[i] = b
            b.MouseButton1Click:Connect(function()
                aimPage.Visible = false
                styleAimbotTab(false)
            end)
        end
    end

    v7Sidebar:GetPropertyChangedSignal("Size"):Connect(function()
        local scale = (MainFrameScale and MainFrameScale.Scale) or 1
        local open = (v7Sidebar.AbsoluteSize.X / scale) >= 100
        aimTab.Size = UDim2.fromOffset(open and 130 or 31, 27)
        aimLabel.TextTransparency = open and 0 or 1
        if open then
            aimTab.Position = UDim2.fromOffset(6, 5 + (4 * 31))
        else
            aimTab.Position = UDim2.fromOffset(6, 5 + (4 * 31))
        end
        fitAimPage()
    end)

    -- Keep the active styling coherent with existing tabs when the Aimbot page is not selected.
    styleAimbotTab(false)
end


--==============================================================
-- PARAMÈTRES V14 : sauvegarde complète des cases, curseurs et réglages.
-- Le système est ajouté à côté de l'onglet AIMBOT sans modifier
-- la navigation originale des 4 onglets.
--==============================================================
do
    local settingsBody = MainFrame and MainFrame:FindFirstChild("V7Body")
    local settingsSidebar = settingsBody and settingsBody:FindFirstChild("V7Sidebar")

    if settingsBody and settingsSidebar then
        local settingsPage = Instance.new("ScrollingFrame")
        settingsPage.Name = "OmegaSettingsPage"
        settingsPage.Parent = settingsBody
        settingsPage.BackgroundTransparency = 1
        settingsPage.BorderSizePixel = 0
        settingsPage.ScrollBarThickness = 3
        settingsPage.ScrollBarImageColor3 = Color3.fromRGB(79, 142, 255)
        settingsPage.CanvasSize = UDim2.new(0, 0, 0, 0)
        settingsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
        settingsPage.ScrollingDirection = Enum.ScrollingDirection.Y
        settingsPage.ZIndex = 91
        settingsPage.Visible = false

        local settingsPadding = Instance.new("UIPadding")
        settingsPadding.PaddingLeft = UDim.new(0, 2)
        settingsPadding.PaddingRight = UDim.new(0, 2)
        settingsPadding.PaddingTop = UDim.new(0, 2)
        settingsPadding.PaddingBottom = UDim.new(0, 6)
        settingsPadding.Parent = settingsPage

        local settingsLayout = Instance.new("UIListLayout")
        settingsLayout.Padding = UDim.new(0, 8)
        settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        settingsLayout.Parent = settingsPage

        settingsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            settingsPage.CanvasSize = UDim2.fromOffset(0, settingsLayout.AbsoluteContentSize.Y + 12)
        end)

        local function fitSettingsPage()
            local scale = (MainFrameScale and MainFrameScale.Scale) or 1
            local bodyW = settingsBody.AbsoluteSize.X / scale
            local bodyH = settingsBody.AbsoluteSize.Y / scale
            local open = (settingsSidebar.AbsoluteSize.X / scale) >= 100
            local x = open and 155 or 57
            settingsPage.Position = UDim2.fromOffset(x, 8)
            settingsPage.Size = UDim2.fromOffset(math.max(100, bodyW - x - 10), math.max(100, bodyH - 16))
        end

        local function makeCorner(obj, radius)
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, radius)
            c.Parent = obj
        end

        local title = Instance.new("TextLabel")
        title.LayoutOrder = 1
        title.Size = UDim2.new(1, -4, 0, 42)
        title.BackgroundColor3 = Color3.fromRGB(22, 27, 35)
        title.BorderSizePixel = 0
        title.Text = "⚙ PARAMÈTRES"
        title.TextColor3 = Color3.fromRGB(255,255,255)
        title.TextSize = 14
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextYAlignment = Enum.TextYAlignment.Center
        title.ZIndex = 92
        title.Parent = settingsPage
        local titlePad = Instance.new("UIPadding")
        titlePad.PaddingLeft = UDim.new(0, 12)
        titlePad.Parent = title
        makeCorner(title, 8)

        -- Les deux anciens panneaux d'information/état sont volontairement retirés.
        -- On garde uniquement le titre, la réinitialisation et les 5 slots de sauvegarde.
        local resetDefaultsButton = Instance.new("TextButton")
        resetDefaultsButton.LayoutOrder = 2
        resetDefaultsButton.Size = UDim2.new(1, -4, 0, 46)
        resetDefaultsButton.BackgroundColor3 = Color3.fromRGB(145, 72, 48)
        resetDefaultsButton.BorderSizePixel = 0
        resetDefaultsButton.AutoButtonColor = true
        resetDefaultsButton.Text = "↺ RÉINITIALISER PAR DÉFAUT"
        resetDefaultsButton.TextColor3 = Color3.fromRGB(255,255,255)
        resetDefaultsButton.TextSize = 13
        resetDefaultsButton.Font = Enum.Font.GothamBold
        resetDefaultsButton.ZIndex = 93
        resetDefaultsButton.Parent = settingsPage
        makeCorner(resetDefaultsButton, 8)

        local slotsTitle = Instance.new("TextLabel")
        slotsTitle.LayoutOrder = 3
        slotsTitle.Size = UDim2.new(1, -4, 0, 26)
        slotsTitle.BackgroundTransparency = 1
        slotsTitle.Text = "SAUVEGARDES"
        slotsTitle.TextColor3 = Color3.fromRGB(170,178,190)
        slotsTitle.TextSize = 11
        slotsTitle.Font = Enum.Font.GothamBold
        slotsTitle.TextXAlignment = Enum.TextXAlignment.Left
        slotsTitle.TextYAlignment = Enum.TextYAlignment.Center
        slotsTitle.ZIndex = 92
        slotsTitle.Parent = settingsPage
        local slotsTitlePad = Instance.new("UIPadding")
        slotsTitlePad.PaddingLeft = UDim.new(0, 8)
        slotsTitlePad.Parent = slotsTitle

        local status = Instance.new("TextLabel")
        status.LayoutOrder = 9
        status.Size = UDim2.new(1, -4, 0, 34)
        status.BackgroundTransparency = 1
        status.Text = ""
        status.TextColor3 = Color3.fromRGB(170,178,190)
        status.TextSize = 10
        status.Font = Enum.Font.GothamMedium
        status.TextWrapped = true
        status.TextXAlignment = Enum.TextXAlignment.Center
        status.TextYAlignment = Enum.TextYAlignment.Center
        status.ZIndex = 92
        status.Parent = settingsPage

        local settingsFile = "PRISON_RP_Settings.json"
        local slotFiles = {
            "PRISON_RP_Settings_Slot1.json",
            "PRISON_RP_Settings_Slot2.json",
            "PRISON_RP_Settings_Slot3.json",
            "PRISON_RP_Settings_Slot4.json",
            "PRISON_RP_Settings_Slot5.json",
        }
        local HttpService = game:GetService("HttpService")

        -- V215 : les noms sont stockés séparément des réglages pour rester
        -- compatibles avec les fichiers de sauvegarde déjà existants.
        local slotNamesFile = "PRISON_RP_Settings_SlotNames.json"
        local slotNames = {}
        local slotNameLabels = {}

        local function cleanSlotName(value, index)
            local name = tostring(value or "")
            name = name:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            name = name:sub(1, 28)
            if name == "" then
                name = "Sauvegarde " .. tostring(index)
            end
            return name
        end

        local function loadSlotNames()
            local storedNames = nil
            if type(isfile) == "function" and type(readfile) == "function" then
                local exists = false
                pcall(function() exists = isfile(slotNamesFile) end)
                if exists then
                    local okRead, raw = pcall(function() return readfile(slotNamesFile) end)
                    if okRead and type(raw) == "string" then
                        local okDecode, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
                        if okDecode and type(decoded) == "table" then
                            storedNames = decoded
                        end
                    end
                end
            end
            for i = 1, 5 do
                local value
                if storedNames then
                    value = storedNames[tostring(i)] or storedNames[i]
                end
                slotNames[i] = cleanSlotName(value, i)
            end
        end

        local function writeSlotNames()
            if type(writefile) ~= "function" then return false end
            local serializable = {}
            for i = 1, 5 do
                serializable[tostring(i)] = slotNames[i]
            end
            local okEncode, encoded = pcall(function()
                return HttpService:JSONEncode(serializable)
            end)
            if not okEncode then return false end
            local okWrite = pcall(function() writefile(slotNamesFile, encoded) end)
            return okWrite
        end

        loadSlotNames()

        local function numberClamp(value, minValue, maxValue, fallback)
            local n = tonumber(value)
            if not n then n = fallback end
            return math.clamp(n, minValue, maxValue)
        end

        local function colorToTable(color)
            if typeof(color) ~= "Color3" then return nil end
            return {R=math.floor(color.R*255+0.5),G=math.floor(color.G*255+0.5),B=math.floor(color.B*255+0.5)}
        end

        local function tableToColor(data, fallback)
            if type(data) ~= "table" then return fallback end
            local r=tonumber(data.R) or tonumber(data[1]); local g=tonumber(data.G) or tonumber(data[2]); local b=tonumber(data.B) or tonumber(data[3])
            if not r or not g or not b then return fallback end
            return Color3.fromRGB(math.clamp(math.floor(r+0.5),0,255),math.clamp(math.floor(g+0.5),0,255),math.clamp(math.floor(b+0.5),0,255))
        end

        local function syncVisibleTextInputs()
            if MovementSpeedBox and tonumber(MovementSpeedBox.Text) then
                MovementWalkSpeed = math.clamp(tonumber(MovementSpeedBox.Text), 1, 250)
                pcall(function() if speedSlider then speedSlider.Set(MovementWalkSpeed) end end)
                pcall(function() if _G.PRISONRP_SETTINGS_SET_WALKSPEED then _G.PRISONRP_SETTINGS_SET_WALKSPEED(MovementWalkSpeed) end end)
            end
            if MovementFlySpeedBox and tonumber(MovementFlySpeedBox.Text) then
                MovementFlySpeed = math.clamp(tonumber(MovementFlySpeedBox.Text), 10, 500)
                pcall(function() if flySpeedSlider then flySpeedSlider.Set(MovementFlySpeed) end end)
                pcall(function() if _G.PRISONRP_SETTINGS_SET_FLYSPEED then _G.PRISONRP_SETTINGS_SET_FLYSPEED(MovementFlySpeed) end end)
            end
        end

        local function getCurrentPageIndex()
            if showBindsPage and settingsPage and (BindPages.Page and BindPages.Page.Visible) then return 7 end
            if settingsPage and settingsPage.Visible then return 6 end
            if aimPage and aimPage.Visible then return 5 end
            if autresPage and autresPage.Visible then return 4 end
            if espPage and espPage.Visible then return 3 end
            if movementPage and movementPage.Visible then return 2 end
            return 1
        end

        --==============================================================
        -- BINDS : choix des touches directement dans l'interface.
        -- Uniquement les switchs demandés + la switch principale AIMBOT.
        -- FREECAM n'a plus de touche F native : elle se contrôle uniquement
        -- par son switch ou son bind défini ici.
        --==============================================================
        local BindConfig = {
            AutoFishing = {label="START AUTO FISH", key=nil, button=ToggleFishBtn},
            AutoEatDrink = {label="AUTO DRINK / EAT", key=nil, button=AutoEatDrinkBtn},
            AutoMine = {label="AUTO MINE", key=nil, button=AutoMineBtn},
            SpeedHack = {label="SPEEDHACK", key=nil, button=speedBtn},
            Fly = {label="FLY", key=nil, button=flyBtn},
            Noclip = {label="NOCLIP", key=nil, button=noclipBtn},
            Freecam = {label="FREECAM", key=nil, button=SpecCard},
            Invisible = {label="INVISIBLE", key=nil, button=InvisibleCard},
            AimEnabled = {label="AIMBOT", key=nil, aimControl="AIMBOT"},
            ESPCheckedButtons = {
                label="ESP : ACTIVER LES BOUTONS COCHÉS",
                key=nil,
                callback=function()
                    local toggle = _G.PRISONRP_TOGGLE_ESP_CHECKED_BUTTONS
                    if type(toggle) == "function" then pcall(toggle) end
                end,
            },
        }

        local BindOrder = {
            "AutoFishing", "AutoEatDrink", "AutoMine", "SpeedHack", "Fly", "Noclip", "Freecam", "Invisible",
            "AimEnabled", "ESPCheckedButtons"
        }

        local BindKeys = {
            "AUCUNE","Q","E","R","T","Y","U","I","O","P",
            "A","S","D","F","G","H","J","K","L",
            "Z","X","C","V","B","N","M",
            "1","2","3","4","5","6","7","8","9","0",
            "LEFT SHIFT","LEFT CTRL","SPACE","MOUSE 1","MOUSE 2"
        }

        local BindInputMap = {
            ["LEFT SHIFT"] = Enum.KeyCode.LeftShift,
            ["RIGHT SHIFT"] = Enum.KeyCode.RightShift,
            ["LEFT CTRL"] = Enum.KeyCode.LeftControl,
            ["RIGHT CTRL"] = Enum.KeyCode.RightControl,
            ["SPACE"] = Enum.KeyCode.Space,
            ["ENTER"] = Enum.KeyCode.Return,
            ["TAB"] = Enum.KeyCode.Tab,
            ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two,
            ["3"] = Enum.KeyCode.Three, ["4"] = Enum.KeyCode.Four,
            ["5"] = Enum.KeyCode.Five, ["6"] = Enum.KeyCode.Six,
            ["7"] = Enum.KeyCode.Seven, ["8"] = Enum.KeyCode.Eight,
            ["9"] = Enum.KeyCode.Nine, ["0"] = Enum.KeyCode.Zero,
            ["MOUSE 1"] = Enum.UserInputType.MouseButton1,
            ["MOUSE 2"] = Enum.UserInputType.MouseButton2,
        }
        local BindPages = {}
        local refreshBindsUI
        local showBindsPage
        local activeBindDropdown
        -- Une capture active signifie que la prochaine touche clavier sert à définir le bind,
        -- et ne doit surtout pas déclencher un autre bind pendant cette opération.
        local bindCaptureEntry = nil
        local bindCaptureButton = nil

        local function bindKeyToDisplay(key)
            return key and tostring(key) or "AUCUNE"
        end

        local function keyCodeToBindName(keyCode)
            local names = {
                [Enum.KeyCode.LeftShift] = "LEFT SHIFT",
                [Enum.KeyCode.RightShift] = "RIGHT SHIFT",
                [Enum.KeyCode.LeftControl] = "LEFT CTRL",
                [Enum.KeyCode.RightControl] = "RIGHT CTRL",
                [Enum.KeyCode.Space] = "SPACE",
                [Enum.KeyCode.Return] = "ENTER",
                [Enum.KeyCode.Tab] = "TAB",
                [Enum.KeyCode.One] = "1", [Enum.KeyCode.Two] = "2",
                [Enum.KeyCode.Three] = "3", [Enum.KeyCode.Four] = "4",
                [Enum.KeyCode.Five] = "5", [Enum.KeyCode.Six] = "6",
                [Enum.KeyCode.Seven] = "7", [Enum.KeyCode.Eight] = "8",
                [Enum.KeyCode.Nine] = "9", [Enum.KeyCode.Zero] = "0",
            }
            return names[keyCode] or keyCode.Name
        end

        local function isValidBindName(name)
            if type(name) ~= "string" or name == "" then return false end
            if BindInputMap[name] ~= nil then return true end
            local ok, item = pcall(function() return Enum.KeyCode[name] end)
            return ok and typeof(item) == "EnumItem" and item.EnumType == Enum.KeyCode
        end

        local function samePressedInput(input, key)
            if not key or key == "AUCUNE" then return false end
            local mapped = BindInputMap[key]
            if typeof(mapped) == "EnumItem" then
                if mapped.EnumType == Enum.UserInputType then
                    return input.UserInputType == mapped
                end
                if mapped.EnumType == Enum.KeyCode then
                    return input.KeyCode == mapped
                end
            end
            return input.KeyCode.Name == tostring(key) or input.UserInputType.Name == tostring(key)
        end

        local function toggleBoundSwitch(entry)
            if not entry then return end

            -- Bind de la case ESP « ACTIVER LES BOUTONS COCHÉS ».
            if type(entry.callback) == "function" then
                pcall(entry.callback)
                return
            end

            -- Les cases AIMBOT sont créées avec addToggle() et enregistrées
            -- dans _G.PRISONRP_AIM_CONTROLS. On réutilise directement leur
            -- getter/setter pour déclencher le même comportement que le clic UI.
            if entry.aimControl then
                for _, control in ipairs(_G.PRISONRP_AIM_CONTROLS or {}) do
                    if control and control.Kind == "toggle" and control.Name == entry.aimControl then
                        local ok, current = pcall(control.Get)
                        if ok then
                            pcall(control.Set, not (current == true))
                            pcall(control.Refresh)
                        end
                        return
                    end
                end
                return
            end

            local btn = entry.button
            if btn and btn.Parent and btn:IsA("GuiButton") then
                pcall(function() btn:Activate() end)
            end
        end

        local BindInputConnection = UserInputService.InputBegan:Connect(function(input, processed)
            -- En mode capture, la prochaine touche du clavier est enregistrée directement.
            if bindCaptureEntry then
                if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                if input.KeyCode == Enum.KeyCode.Unknown then return end

                local entry = bindCaptureEntry
                local keyButton = bindCaptureButton
                if input.KeyCode == Enum.KeyCode.Escape then
                    -- Échap annule la capture sans modifier le bind actuel.
                    bindCaptureEntry = nil
                    bindCaptureButton = nil
                elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                    -- Retour arrière/Suppr efface le bind de cette ligne.
                    entry.key = nil
                    bindCaptureEntry = nil
                    bindCaptureButton = nil
                else
                    entry.key = keyCodeToBindName(input.KeyCode)
                    bindCaptureEntry = nil
                    bindCaptureButton = nil
                end
                if keyButton and keyButton.Parent then
                    keyButton.BackgroundColor3 = Color3.fromRGB(45,54,67)
                end
                if refreshBindsUI then pcall(refreshBindsUI) end
                return
            end

            if processed then return end
            for _, entry in pairs(BindConfig) do
                if entry.key and samePressedInput(input, entry.key) then
                    toggleBoundSwitch(entry)
                end
            end
        end)
        table.insert(BindPages, BindInputConnection)

        local function copyBindState()
            local result = {}
            for _, id in ipairs(BindOrder) do
                local entry = BindConfig[id]
                if entry then result[id] = entry.key end
            end
            return result
        end

        local function applyBindState(data)
            if type(data) ~= "table" then return end
            for _, id in ipairs(BindOrder) do
                local entry = BindConfig[id]
                if entry then
                    local v = data[id]
                    if v == "AUCUNE" or v == nil then
                        entry.key = nil
                    else
                        -- Les binds capturés directement peuvent utiliser n'importe quelle touche clavier,
                        -- pas uniquement l'ancienne liste limitée du menu déroulant.
                        entry.key = isValidBindName(v) and v or nil
                    end
                end
            end
            if refreshBindsUI then pcall(refreshBindsUI) end
        end

        local function resetBindState()
            for _, id in ipairs(BindOrder) do
                local entry = BindConfig[id]
                if entry then entry.key = nil end
            end
            if refreshBindsUI then pcall(refreshBindsUI) end
        end

        local function currentSettings()
            syncVisibleTextInputs()
            local esp = type(_G.PRISONRP_GET_ESP_STATE)=="function" and _G.PRISONRP_GET_ESP_STATE() or {}
            local spec = type(_G.PRISONRP_GET_SPEC_STATE)=="function" and _G.PRISONRP_GET_SPEC_STATE() or {}
            local tpspec = type(_G.PRISONRP_GET_TPSPEC_STATE)=="function" and _G.PRISONRP_GET_TPSPEC_STATE() or {}
            return {
                Version=5,
                Snapshot="FULL_EXACT",
                SavedAt=os.time(),
                CurrentPage=getCurrentPageIndex(),
                WalkSpeed=tonumber(MovementWalkSpeed) or 35,
                FlySpeed=tonumber(MovementFlySpeed) or 60,
                WalkSpeedText=MovementSpeedBox and tostring(MovementSpeedBox.Text) or tostring(MovementWalkSpeed),
                FlySpeedText=MovementFlySpeedBox and tostring(MovementFlySpeedBox.Text) or tostring(MovementFlySpeed),
                MinRarityIndex=math.clamp(math.floor(tonumber(_G.MinRarityIndex) or 1),1,#RarityList),
                AutoEatDrinkThreshold=tonumber(AUTO_EAT_DRINK_THRESHOLD) or 50,
                MoneyViewDistance=tonumber(MoneyViewMaxDistance) or 125,
                Freecam={
                    Speed=(spec and tonumber(spec.Speed)) or 45,
                    FastSpeed=(spec and tonumber(spec.FastSpeed)) or 80,
                },
                TPSpecSettings={
                    Distance=tonumber(TPSpecDistance) or 8,
                    Yaw=tonumber(TPSpecYaw) or 0,
                    Pitch=tonumber(TPSpecPitch) or math.rad(-10),
                    Sensitivity=tonumber(TPSpecSensitivity) or 0.004,
                    MinDistance=tonumber(TPSpecMinDistance) or 4,
                    MaxDistance=tonumber(TPSpecMaxDistance) or 18,
                },
                Toggles={
                    AutoFishing=_G.AutoFishingEnabled==true,
                    AutoSell=_G.AutoSellEnabled==true,
                    AutoEatDrink=AutoEatDrinkEnabled==true,
                    AutoPushup=_G.AutoPushupEnabled==true,
                    AutoMine=AutoMineRunning==true,
                    SpeedHack=MovementWalkSpeedEnabled==true,
                    Fly=MovementFlyEnabled==true,
                    Noclip=MovementNoclipEnabled==true,
                    FreecamArmed=spec.Armed==true,
                    InvisibleEnabled=(type(_G.PRISONRP_GET_INVISIBLE_STATE)=="function" and _G.PRISONRP_GET_INVISIBLE_STATE()) or false,
                    StaffESP=_G.PRISONRP_V128_ESP_STAFF_ENABLED==true,
                    StaffAutoLeave=StaffAutoLeaveEnabled==true,
                    BlackMarketESP=_G.BlackMarketESP==true,
                    MoneyView=_G.MoneyViewEnabledValue==true,
                    AutoArmWrestle=(_G.PRISONRP_AUTO_ARM_WRESTLE_STATE and _G.PRISONRP_AUTO_ARM_WRESTLE_STATE.Enabled)==true,
                    TPSpec=tpspec.Enabled==true,
                },
                ESP=esp,
                Binds=copyBindState(),
                Aimbot={
                    Enabled=Aimbot.Settings.Enabled==true, Toggle=Aimbot.Settings.Toggle==true,
                    LockPart=Aimbot.Settings.LockPart, TriggerKey=Aimbot.Settings.TriggerKey,
                    Sensitivity=tonumber(Aimbot.Settings.Sensitivity) or 0,
                    ThirdPersonSensitivity=tonumber(Aimbot.Settings.ThirdPersonSensitivity) or 0.1,
                    TeamCheck=Aimbot.Settings.TeamCheck==true, WallCheck=Aimbot.Settings.WallCheck==true,
                    AliveCheck=Aimbot.Settings.AliveCheck==true, ThirdPerson=Aimbot.Settings.ThirdPerson==true,
                    FOVEnabled=Aimbot.FOVSettings.Enabled==true, FOVVisible=Aimbot.FOVSettings.Visible==true,
                    FOVAmount=tonumber(Aimbot.FOVSettings.Amount) or 0, FOVFilled=Aimbot.FOVSettings.Filled==true,
                    FOVTransparency=tonumber(Aimbot.FOVSettings.Transparency) or 0,
                    FOVSides=tonumber(Aimbot.FOVSettings.Sides) or 60, FOVThickness=tonumber(Aimbot.FOVSettings.Thickness) or 1,
                    FOVColor=colorToTable(Aimbot.FOVSettings.Color), FOVLockedColor=colorToTable(Aimbot.FOVSettings.LockedColor),
                },
            }
        end

        -- Snapshot propre des réglages d'origine, capturé avant tout chargement.
        -- Valeurs par défaut demandées : AIMBOT OFF + les 8 options ESP OFF.
        local defaultSettings = currentSettings()
        defaultSettings.CurrentPage = 6
        if type(defaultSettings.Aimbot) == "table" then
            defaultSettings.Aimbot.Enabled = false
        end
        defaultSettings.Binds = {}
        if type(defaultSettings.ESP) == "table" then
            for _, key in ipairs({
                "ESPEnabled", "NamesEnabled", "GameNameEnabled", "DistanceEnabled",
                "HealthEnabled", "TracersEnabled", "HighlightEnabled", "BodyStatusEnabled"
            }) do
                defaultSettings.ESP[key] = false
            end
        end

        local function refreshAimControls()
            if type(_G.PRISONRP_AIM_CONTROLS)~="table" then return end
            for _,c in ipairs(_G.PRISONRP_AIM_CONTROLS) do pcall(c.Refresh) end
        end

        local function applyLoadedSettings(data)
            if type(data)~="table" then return end
            if type(data.Binds) == "table" then
                applyBindState(data.Binds)
            else
                resetBindState()
            end
            MovementWalkSpeed=numberClamp(data.WalkSpeed,1,250,MovementWalkSpeed)
            MovementFlySpeed=numberClamp(data.FlySpeed,10,500,MovementFlySpeed)
            if MovementSpeedBox then MovementSpeedBox.Text=tostring(data.WalkSpeedText or MovementWalkSpeed) end
            if MovementFlySpeedBox then MovementFlySpeedBox.Text=tostring(data.FlySpeedText or MovementFlySpeed) end
            _G.MinRarityIndex=math.clamp(math.floor(tonumber(data.MinRarityIndex) or _G.MinRarityIndex),1,#RarityList)
            AUTO_EAT_DRINK_THRESHOLD=numberClamp(data.AutoEatDrinkThreshold,1,100,AUTO_EAT_DRINK_THRESHOLD)
            if _G.PRISONRP_SETTINGS_SET_WALKSPEED then pcall(function() _G.PRISONRP_SETTINGS_SET_WALKSPEED(MovementWalkSpeed) end) end
            if _G.PRISONRP_SETTINGS_SET_FLYSPEED then pcall(function() _G.PRISONRP_SETTINGS_SET_FLYSPEED(MovementFlySpeed) end) end
            if _G.PRISONRP_SETTINGS_SET_MONEY_DISTANCE and data.MoneyViewDistance~=nil then pcall(function() _G.PRISONRP_SETTINGS_SET_MONEY_DISTANCE(numberClamp(data.MoneyViewDistance,10,1000,MoneyViewMaxDistance)) end) end
            if type(data.Freecam)=="table" and Spec then
                if data.Freecam.Speed ~= nil then Spec.Speed = numberClamp(data.Freecam.Speed,1,500,Spec.Speed) end
                if data.Freecam.FastSpeed ~= nil then Spec.FastSpeed = numberClamp(data.Freecam.FastSpeed,1,1000,Spec.FastSpeed) end
            end
            if type(data.TPSpecSettings)=="table" then
                if data.TPSpecSettings.Distance ~= nil then TPSpecDistance = numberClamp(data.TPSpecSettings.Distance,1,100, TPSpecDistance) end
                if data.TPSpecSettings.Yaw ~= nil then TPSpecYaw = tonumber(data.TPSpecSettings.Yaw) or TPSpecYaw end
                if data.TPSpecSettings.Pitch ~= nil then TPSpecPitch = tonumber(data.TPSpecSettings.Pitch) or TPSpecPitch end
                if data.TPSpecSettings.Sensitivity ~= nil then TPSpecSensitivity = numberClamp(data.TPSpecSettings.Sensitivity,0.0001,0.1,TPSpecSensitivity) end
                if data.TPSpecSettings.MinDistance ~= nil then TPSpecMinDistance = numberClamp(data.TPSpecSettings.MinDistance,1,100,TPSpecMinDistance) end
                if data.TPSpecSettings.MaxDistance ~= nil then TPSpecMaxDistance = numberClamp(data.TPSpecSettings.MaxDistance,1,200,TPSpecMaxDistance) end
            end
            if type(_G.PRISONRP_SET_ESP_STATE)=="function" and type(data.ESP)=="table" then pcall(function() _G.PRISONRP_SET_ESP_STATE(data.ESP) end) end

            local t=type(data.Toggles)=="table" and data.Toggles or {}

            -- Restauration DIRECTE des états : on ne simule plus un clic GUI.
            -- Cela garantit que chaque case sauvegardée retrouve exactement son état.
            local function restoreBool(getter, setterOn, setterOff, desired)
                local want = desired == true
                local now = false
                if type(getter) == "function" then
                    local ok, value = pcall(getter)
                    if ok then now = value == true end
                end
                if now == want then return end
                if want then
                    if type(setterOn) == "function" then pcall(setterOn) end
                else
                    if type(setterOff) == "function" then pcall(setterOff) end
                end
            end

            -- AUTO-FISH / AUTO-SELL / AUTO EAT-DRINK : ces moteurs surveillent
            -- déjà leurs variables d'état en continu. On restaure donc directement.
            _G.AutoFishingEnabled = t.AutoFishing == true
            _G.AutoSellEnabled = t.AutoSell == true
            AutoEatDrinkEnabled = t.AutoEatDrink == true
            _G.AutoEatDrinkEnabled = AutoEatDrinkEnabled

            -- AUTO-POMPES
            restoreBool(
                function() return _G.AutoPushupEnabled == true end,
                function() startAutoPushup() end,
                function() stopAutoPushup() end,
                t.AutoPushup
            )

            -- AUTO-MINE
            restoreBool(
                function() return AutoMineRunning == true end,
                function() autoMineStart() end,
                function() autoMineStop() end,
                t.AutoMine
            )

            -- SPEEDHACK
            restoreBool(
                function() return MovementWalkSpeedEnabled == true end,
                function() MovementWalkSpeedEnabled = true; movementApplyWalkSpeed() end,
                function() MovementWalkSpeedEnabled = false; movementApplyWalkSpeed() end,
                t.SpeedHack
            )

            -- FLY
            restoreBool(
                function() return MovementFlyEnabled == true end,
                function() MovementFlyEnabled = true; movementStartFly() end,
                function() MovementFlyEnabled = false; movementStopFly() end,
                t.Fly
            )

            -- NOCLIP
            restoreBool(
                function() return MovementNoclipEnabled == true end,
                function() movementSetNoclip(true) end,
                function() movementSetNoclip(false) end,
                t.Noclip
            )

            -- FREECAM
            if t.FreecamArmed ~= nil then
                pcall(function()
                    specSetArmed(t.FreecamArmed == true)
                    if t.FreecamArmed == true and not Spec.Enabled then
                        specEnable()
                    elseif t.FreecamArmed ~= true and Spec.Enabled then
                        specDisable()
                    end
                end)
            end

            -- INVISIBLE
            if type(_G.PRISONRP_SET_INVISIBLE_STATE)=="function" and t.InvisibleEnabled ~= nil then
                pcall(function() _G.PRISONRP_SET_INVISIBLE_STATE(t.InvisibleEnabled == true) end)
            end

            -- ESP STAFF
            if t.StaffESP ~= nil then
                _G.PRISONRP_V128_ESP_STAFF_ENABLED = t.StaffESP == true
                if type(_G.PRISONRP_SET_ESP_STATE) == "function" then
                    pcall(function()
                        _G.PRISONRP_SET_ESP_STATE({StaffDetection = _G.PRISONRP_V128_ESP_STAFF_ENABLED})
                    end)
                end
                if not _G.PRISONRP_V128_ESP_STAFF_ENABLED then
                    pcall(function() if type(stopStaffESP)=="function" then stopStaffESP() end end)
                elseif StaffESPBtn then
                    StaffESPBtn.Text = "🛡️ ESP STAFF : ON"
                end
            end

            -- AUTO-LEAVE STAFF
            StaffAutoLeaveEnabled = t.StaffAutoLeave == true
            if StaffAutoLeaveBtn then
                StaffAutoLeaveBtn.Text = StaffAutoLeaveEnabled and "🚪 AUTO-LEAVE : ON" or "🚪 AUTO-LEAVE : OFF"
            end

            -- BLACK MARKET ESP
            _G.BlackMarketESP = t.BlackMarketESP == true
            pcall(function() toggleBlackMarketESP() end)

            -- MONEY VIEW
            if type(moneyViewSetEnabled)=="function" then
                pcall(function() moneyViewSetEnabled(t.MoneyView == true) end)
            elseif type(_G.MoneyViewEnabled)=="function" then
                pcall(function() _G.MoneyViewEnabled(t.MoneyView == true) end)
            end

            -- AUTO BRAS DE FER
            if t.AutoArmWrestle ~= nil then
                if t.AutoArmWrestle == true and not (_G.PRISONRP_AUTO_ARM_WRESTLE_STATE and _G.PRISONRP_AUTO_ARM_WRESTLE_STATE.Enabled) then
                    pcall(function() if type(_G.PRISONRP_START_AUTO_ARM_WRESTLE)=="function" then _G.PRISONRP_START_AUTO_ARM_WRESTLE() end end)
                elseif t.AutoArmWrestle ~= true and (_G.PRISONRP_AUTO_ARM_WRESTLE_STATE and _G.PRISONRP_AUTO_ARM_WRESTLE_STATE.Enabled) then
                    pcall(function() if type(_G.PRISONRP_STOP_AUTO_ARM_WRESTLE)=="function" then _G.PRISONRP_STOP_AUTO_ARM_WRESTLE() end end)
                end
            end

            -- TP SPEC
            if type(_G.PRISONRP_SET_TPSPEC_STATE)=="function" and t.TPSpec ~= nil then
                pcall(function() _G.PRISONRP_SET_TPSPEC_STATE({Enabled=t.TPSpec==true}) end)
            end

            -- Réactualise les états visuels des switches après restauration.
            -- IMPORTANT : cette partie est exécutée hors du gros pcall principal ;
            -- elle ne peut donc pas dépendre de locaux comme C ou GDPRefreshers.
            local function refreshSavedSwitchVisuals()
                local neutralCard = Color3.fromRGB(45, 48, 62)
                local activeCard = Color3.fromRGB(40, 150, 80)

                local function syncSwitchVisual(btn, on)
                    if not btn or not btn.Parent then return end
                    local sw = btn:FindFirstChild("GDPCheckbox")
                    local knob = sw and sw:FindFirstChild("Knob")
                    if not sw or not knob then return end

                    local wantedOn = on == true
                    -- Même géométrie que gdpCheckbox.refresh(false).
                    knob.Position = wantedOn
                        and UDim2.new(1, -19, 0, 3)
                        or UDim2.fromOffset(3, 3)
                    sw.BackgroundColor3 = wantedOn
                        and Color3.fromRGB(40, 150, 80)
                        or Color3.fromRGB(70, 80, 94)
                    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    if btn == ToggleFishBtn then
                        btn.BackgroundColor3 = wantedOn and activeCard or neutralCard
                    else
                        btn.BackgroundColor3 = neutralCard
                    end
                end

                syncSwitchVisual(ToggleFishBtn, _G.AutoFishingEnabled == true)
                syncSwitchVisual(AutoSellBtn, _G.AutoSellEnabled == true)
                syncSwitchVisual(AutoEatDrinkBtn, AutoEatDrinkEnabled == true)
                syncSwitchVisual(AutoPushupBtn, _G.AutoPushupEnabled == true)
                syncSwitchVisual(AutoMineBtn, AutoMineRunning == true)
                syncSwitchVisual(speedBtn, MovementWalkSpeedEnabled == true)
                syncSwitchVisual(flyBtn, MovementFlyEnabled == true)
                syncSwitchVisual(noclipBtn, MovementNoclipEnabled == true)
                syncSwitchVisual(StaffESPBtn, _G.PRISONRP_V128_ESP_STAFF_ENABLED == true)
                syncSwitchVisual(StaffAutoLeaveBtn, StaffAutoLeaveEnabled == true)
                syncSwitchVisual(ESPToggleBtn, _G.BlackMarketESP == true)
                syncSwitchVisual(MoneyViewBtn, _G.MoneyViewEnabledValue == true)
                syncSwitchVisual((_G.PRISONRP_AUTO_ARM_WRESTLE_STATE and _G.PRISONRP_AUTO_ARM_WRESTLE_STATE.Btn), (_G.PRISONRP_AUTO_ARM_WRESTLE_STATE and _G.PRISONRP_AUTO_ARM_WRESTLE_STATE.Enabled) == true)

                local invisibleState = type(_G.PRISONRP_GET_INVISIBLE_STATE)=="function" and _G.PRISONRP_GET_INVISIBLE_STATE() or false
                syncSwitchVisual(InvisibleCard, invisibleState == true)

                -- TP/SPEC utilise un switch cloné : forcer aussi son visuel.
                if tpSpecSwitch and tpSpecKnob then
                    tpSpecKnob.Position = TPSpecEnabled
                        and UDim2.new(1, -19, 0, 3)
                        or UDim2.fromOffset(3, 3)
                    tpSpecSwitch.BackgroundColor3 = TPSpecEnabled
                        and Color3.fromRGB(40, 150, 80)
                        or Color3.fromRGB(70, 80, 94)
                    tpSpecKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                elseif tpSpecButton then
                    syncSwitchVisual(tpSpecButton, TPSpecEnabled == true)
                end

                pcall(updateUI)
                pcall(updateAutoEatDrinkUI)
                pcall(function()
                    if RarityBtn then
                        RarityBtn.Text = "Pêcher à partir de : " .. tostring(RarityList[_G.MinRarityIndex] or RarityList[1])
                    end
                end)
                pcall(function()
                    stats.status = _G.AutoFishingEnabled and "Running..."
                        or (AutoEatDrinkEnabled and "Auto Eat / Drink : ON (" .. tostring(AUTO_EAT_DRINK_THRESHOLD) .. ")" or "Stopped")
                end)
            end

            -- Premier passage immédiat + plusieurs repasses pour les fonctions
            -- dont l'interface finit de se construire juste après le lancement.
            refreshSavedSwitchVisuals()
            task.delay(0.05, refreshSavedSwitchVisuals)
            task.delay(0.20, refreshSavedSwitchVisuals)
            task.delay(0.50, refreshSavedSwitchVisuals)
            task.delay(1.00, refreshSavedSwitchVisuals)
            task.delay(2.00, refreshSavedSwitchVisuals)

            if type(data.Aimbot)=="table" then
                local a=data.Aimbot
                Aimbot.Settings.Enabled=a.Enabled==true; Aimbot.Settings.Toggle=a.Toggle==true
                if a.LockPart then Aimbot.Settings.LockPart=tostring(a.LockPart) end
                if a.TriggerKey then Aimbot.Settings.TriggerKey=tostring(a.TriggerKey) end
                Aimbot.Settings.Sensitivity=numberClamp(a.Sensitivity,0,1,Aimbot.Settings.Sensitivity)
                Aimbot.Settings.ThirdPersonSensitivity=numberClamp(a.ThirdPersonSensitivity,0.1,5,Aimbot.Settings.ThirdPersonSensitivity)
                Aimbot.Settings.TeamCheck=a.TeamCheck==true; Aimbot.Settings.WallCheck=a.WallCheck==true; Aimbot.Settings.AliveCheck=a.AliveCheck==true; Aimbot.Settings.ThirdPerson=a.ThirdPerson==true
                Aimbot.FOVSettings.Enabled=a.FOVEnabled==true; Aimbot.FOVSettings.Visible=a.FOVVisible==true
                Aimbot.FOVSettings.Amount=numberClamp(a.FOVAmount,10,300,Aimbot.FOVSettings.Amount); Aimbot.FOVSettings.Filled=a.FOVFilled==true
                Aimbot.FOVSettings.Transparency=numberClamp(a.FOVTransparency,0,1,Aimbot.FOVSettings.Transparency); Aimbot.FOVSettings.Sides=numberClamp(a.FOVSides,3,60,Aimbot.FOVSettings.Sides); Aimbot.FOVSettings.Thickness=numberClamp(a.FOVThickness,1,20,Aimbot.FOVSettings.Thickness)
                Aimbot.FOVSettings.Color=tableToColor(a.FOVColor,Aimbot.FOVSettings.Color); Aimbot.FOVSettings.LockedColor=tableToColor(a.FOVLockedColor,Aimbot.FOVSettings.LockedColor)
                Running=false; pcall(CancelLock); pcall(UpdateFOV); refreshAimControls()
            end
            pcall(updateUI); pcall(updateAutoEatDrinkUI)
            pcall(function() RarityBtn.Text="Pêcher à partir de : "..tostring(RarityList[_G.MinRarityIndex] or RarityList[1]) end)
            if data.CurrentPage then
                local page = math.clamp(math.floor(tonumber(data.CurrentPage) or 1), 1, 7)
                if page == 7 then
                    if showBindsPage then pcall(showBindsPage) end
                elseif page == 6 then
                    pcall(showSettingsPage)
                elseif page == 5 and type(showAimbotPage)=="function" then
                    pcall(showAimbotPage)
                elseif page <= 4 and type(selectPage)=="function" then
                    pcall(selectPage, page)
                end
            end
        end

        local function writeSettingsFile(path)
            if type(writefile) ~= "function" then
                status.Text = "⚠ writefile n'est pas disponible dans cet executor."
                status.TextColor3 = Color3.fromRGB(255,170,90)
                return false
            end
            local okEncode, encoded = pcall(function()
                return HttpService:JSONEncode(currentSettings())
            end)
            if not okEncode then
                status.Text = "⚠ Impossible d'encoder les paramètres."
                status.TextColor3 = Color3.fromRGB(255,110,110)
                return false
            end
            local okWrite = pcall(function()
                writefile(path, encoded)
            end)
            if okWrite then
                return true
            end
            status.Text = "⚠ Impossible d'écrire la sauvegarde."
            status.TextColor3 = Color3.fromRGB(255,110,110)
            return false
        end

        local function readSettingsFile(path)
            if type(readfile) ~= "function" or type(isfile) ~= "function" or not isfile(path) then
                return nil
            end
            local okRead, raw = pcall(function() return readfile(path) end)
            if not okRead or type(raw) ~= "string" then return nil end
            local okDecode, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if not okDecode or type(data) ~= "table" then return nil end
            return data
        end

        local function resetToDefaults()
            local ok = pcall(function()
                applyLoadedSettings(defaultSettings)
            end)
            if ok then
                status.Text = "✓ Paramètres réinitialisés par défaut."
                status.TextColor3 = Color3.fromRGB(125,230,155)
            else
                status.Text = "⚠ Échec de la réinitialisation."
                status.TextColor3 = Color3.fromRGB(255,110,110)
            end
        end

        resetDefaultsButton.MouseButton1Click:Connect(resetToDefaults)

        -- Petite fenêtre de renommage, créée uniquement à la demande.
        local renameOverlay = nil
        local function closeRenameModal()
            if renameOverlay then
                pcall(function() renameOverlay:Destroy() end)
                renameOverlay = nil
            end
        end

        local function openRenameModal(slotIndex)
            closeRenameModal()
            local overlay = Instance.new("Frame")
            overlay.Name = "SettingsRenameOverlay"
            overlay.Size = UDim2.fromScale(1, 1)
            overlay.Position = UDim2.fromScale(0, 0)
            overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            overlay.BackgroundTransparency = 0.38
            overlay.BorderSizePixel = 0
            overlay.ZIndex = 200
            overlay.Parent = MainFrame
            renameOverlay = overlay

            local panel = Instance.new("Frame")
            panel.Name = "RenamePanel"
            panel.AnchorPoint = Vector2.new(0.5, 0.5)
            panel.Position = UDim2.fromScale(0.5, 0.5)
            panel.Size = UDim2.new(1, -28, 0, 166)
            panel.BackgroundColor3 = Color3.fromRGB(24, 29, 38)
            panel.BorderSizePixel = 0
            panel.ZIndex = 201
            panel.Parent = overlay
            makeCorner(panel, 10)
            local outline = Instance.new("UIStroke")
            outline.Color = Color3.fromRGB(72, 112, 175)
            outline.Transparency = 0.25
            outline.Thickness = 1
            outline.Parent = panel

            local heading = Instance.new("TextLabel")
            heading.Size = UDim2.new(1, -20, 0, 30)
            heading.Position = UDim2.fromOffset(10, 9)
            heading.BackgroundTransparency = 1
            heading.Text = "RENOMMER LA SAUVEGARDE"
            heading.TextColor3 = Color3.fromRGB(240, 244, 250)
            heading.TextSize = 12
            heading.Font = Enum.Font.GothamBold
            heading.TextXAlignment = Enum.TextXAlignment.Left
            heading.ZIndex = 202
            heading.Parent = panel

            local input = Instance.new("TextBox")
            input.Name = "SaveNameInput"
            input.Size = UDim2.new(1, -20, 0, 34)
            input.Position = UDim2.fromOffset(10, 48)
            input.BackgroundColor3 = Color3.fromRGB(35, 42, 54)
            input.BorderSizePixel = 0
            input.ClearTextOnFocus = false
            input.Text = slotNames[slotIndex] or ("Sauvegarde " .. tostring(slotIndex))
            input.PlaceholderText = "Nom de la sauvegarde"
            input.PlaceholderColor3 = Color3.fromRGB(145, 153, 166)
            input.TextColor3 = Color3.fromRGB(255, 255, 255)
            input.TextSize = 12
            input.Font = Enum.Font.GothamMedium
            input.TextXAlignment = Enum.TextXAlignment.Left
            input.ZIndex = 202
            input.Parent = panel
            makeCorner(input, 7)
            local inputPadding = Instance.new("UIPadding")
            inputPadding.PaddingLeft = UDim.new(0, 9)
            inputPadding.PaddingRight = UDim.new(0, 9)
            inputPadding.Parent = input

            local function makeModalButton(name, text, color, xOffset)
                local button = Instance.new("TextButton")
                button.Name = name
                button.Size = UDim2.new(0.5, -15, 0, 32)
                button.Position = UDim2.new(xOffset, xOffset == 0 and 10 or 5, 1, -42)
                button.BackgroundColor3 = color
                button.BorderSizePixel = 0
                button.AutoButtonColor = true
                button.Text = text
                button.TextColor3 = Color3.fromRGB(255, 255, 255)
                button.TextSize = 11
                button.Font = Enum.Font.GothamBold
                button.ZIndex = 202
                button.Parent = panel
                makeCorner(button, 7)
                return button
            end

            local saveNameButton = makeModalButton("ConfirmRename", "ENREGISTRER", Color3.fromRGB(40, 145, 78), 0)
            local cancelNameButton = makeModalButton("CancelRename", "ANNULER", Color3.fromRGB(58, 66, 80), 0.5)

            local committed = false
            local function commitRename()
                if committed then return end
                committed = true
                slotNames[slotIndex] = cleanSlotName(input.Text, slotIndex)
                local persisted = writeSlotNames()
                local nameLabel = slotNameLabels[slotIndex]
                if nameLabel and nameLabel.Parent then
                    nameLabel.Text = slotNames[slotIndex] .. "  ✎"
                end
                if persisted then
                    status.Text = "✓ Nom enregistré : " .. slotNames[slotIndex]
                    status.TextColor3 = Color3.fromRGB(125, 230, 155)
                else
                    status.Text = "⚠ Nom modifié pour cette session, mais impossible de l'enregistrer sur disque."
                    status.TextColor3 = Color3.fromRGB(255, 170, 90)
                end
                closeRenameModal()
            end

            saveNameButton.MouseButton1Click:Connect(commitRename)
            cancelNameButton.MouseButton1Click:Connect(closeRenameModal)
            input.FocusLost:Connect(function(enterPressed)
                if enterPressed then commitRename() end
            end)
            task.defer(function()
                if input and input.Parent then
                    pcall(function()
                        input:CaptureFocus()
                        input.CursorPosition = #input.Text + 1
                    end)
                end
            end)
        end

        for index = 1, 5 do
            local slotIndex = index
            local row = Instance.new("Frame")
            row.LayoutOrder = 3 + index
            row.Size = UDim2.new(1, -4, 0, 50)
            row.BackgroundColor3 = Color3.fromRGB(31, 38, 48)
            row.BorderSizePixel = 0
            row.ZIndex = 92
            row.Parent = settingsPage
            makeCorner(row, 8)

            local label = Instance.new("TextButton")
            label.Name = "SlotNameButton"
            label.Size = UDim2.new(1, -142, 1, 0)
            label.Position = UDim2.fromOffset(10, 0)
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.AutoButtonColor = false
            label.Text = (slotNames[slotIndex] or ("Sauvegarde " .. tostring(slotIndex))) .. "  ✎"
            label.TextColor3 = Color3.fromRGB(235,238,244)
            label.TextSize = 11
            label.Font = Enum.Font.GothamBold
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.TextTruncate = Enum.TextTruncate.AtEnd
            label.ZIndex = 93
            label.Parent = row
            slotNameLabels[slotIndex] = label
            label.MouseButton1Click:Connect(function()
                openRenameModal(slotIndex)
            end)

            local saveSlotButton = Instance.new("TextButton")
            saveSlotButton.Size = UDim2.fromOffset(58, 30)
            saveSlotButton.Position = UDim2.new(1, -130, 0.5, -15)
            saveSlotButton.BackgroundColor3 = Color3.fromRGB(40,145,78)
            saveSlotButton.BorderSizePixel = 0
            saveSlotButton.AutoButtonColor = true
            saveSlotButton.Text = "SAUVER"
            saveSlotButton.TextColor3 = Color3.fromRGB(255,255,255)
            saveSlotButton.TextSize = 9
            saveSlotButton.Font = Enum.Font.GothamBold
            saveSlotButton.ZIndex = 94
            saveSlotButton.Parent = row
            makeCorner(saveSlotButton, 7)

            local loadSlotButton = Instance.new("TextButton")
            loadSlotButton.Size = UDim2.fromOffset(58, 30)
            loadSlotButton.Position = UDim2.new(1, -66, 0.5, -15)
            loadSlotButton.BackgroundColor3 = Color3.fromRGB(52,100,165)
            loadSlotButton.BorderSizePixel = 0
            loadSlotButton.AutoButtonColor = true
            loadSlotButton.Text = "CHARGER"
            loadSlotButton.TextColor3 = Color3.fromRGB(255,255,255)
            loadSlotButton.TextSize = 8
            loadSlotButton.Font = Enum.Font.GothamBold
            loadSlotButton.ZIndex = 94
            loadSlotButton.Parent = row
            makeCorner(loadSlotButton, 7)

            saveSlotButton.MouseButton1Click:Connect(function()
                if writeSettingsFile(slotFiles[slotIndex]) then
                    status.Text = "✓ «" .. slotNames[slotIndex] .. "» enregistrée."
                    status.TextColor3 = Color3.fromRGB(125,230,155)
                end
            end)

            loadSlotButton.MouseButton1Click:Connect(function()
                local data = readSettingsFile(slotFiles[slotIndex])
                if not data then
                    status.Text = "⚠ «" .. slotNames[slotIndex] .. "» n'existe pas encore."
                    status.TextColor3 = Color3.fromRGB(255,170,90)
                    return
                end
                local ok = pcall(function() applyLoadedSettings(data) end)
                if ok then
                    status.Text = "✓ «" .. slotNames[slotIndex] .. "» chargée."
                    status.TextColor3 = Color3.fromRGB(125,230,155)
                else
                    status.Text = "⚠ Impossible de charger «" .. slotNames[slotIndex] .. "»."
                    status.TextColor3 = Color3.fromRGB(255,110,110)
                end
            end)
        end

        --==============================================================
        -- ONGLET BINDS
        --==============================================================
        do
            local oldBindsPage = settingsBody:FindFirstChild("OmegaBindsPage")
            if oldBindsPage then oldBindsPage:Destroy() end

            local bindsPage = Instance.new("ScrollingFrame")
            bindsPage.Name = "OmegaBindsPage"
            bindsPage.Parent = settingsBody
            bindsPage.BackgroundTransparency = 1
            bindsPage.BorderSizePixel = 0
            bindsPage.ScrollBarThickness = 3
            bindsPage.ScrollBarImageColor3 = Color3.fromRGB(79,142,255)
            bindsPage.CanvasSize = UDim2.new(0,0,0,0)
            bindsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
            bindsPage.ScrollingDirection = Enum.ScrollingDirection.Y
            bindsPage.ZIndex = 91
            bindsPage.Visible = false
            BindPages.Page = bindsPage

            local pad = Instance.new("UIPadding")
            pad.PaddingLeft = UDim.new(0,2); pad.PaddingRight = UDim.new(0,2)
            pad.PaddingTop = UDim.new(0,2); pad.PaddingBottom = UDim.new(0,8)
            pad.Parent = bindsPage

            local layout = Instance.new("UIListLayout")
            layout.Padding = UDim.new(0,7)
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Parent = bindsPage
            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                bindsPage.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
            end)

            local function fitBindsPage()
                local scale = (MainFrameScale and MainFrameScale.Scale) or 1
                local bodyW = settingsBody.AbsoluteSize.X / scale
                local bodyH = settingsBody.AbsoluteSize.Y / scale
                local open = (settingsSidebar.AbsoluteSize.X / scale) >= 100
                local x = open and 155 or 57
                bindsPage.Position = UDim2.fromOffset(x,8)
                bindsPage.Size = UDim2.fromOffset(math.max(100, bodyW-x-10), math.max(100, bodyH-16))
            end

            local title = Instance.new("TextLabel")
            title.LayoutOrder = 1; title.Size = UDim2.new(1,-4,0,42)
            title.BackgroundColor3 = Color3.fromRGB(22,27,35); title.BorderSizePixel = 0
            title.Text = "⌨ BINDS"
            title.TextColor3 = Color3.fromRGB(255,255,255); title.TextSize = 14
            title.Font = Enum.Font.GothamBold; title.TextXAlignment = Enum.TextXAlignment.Left
            title.TextYAlignment = Enum.TextYAlignment.Center; title.ZIndex = 92; title.Parent = bindsPage
            makeCorner(title,8)
            local titlePad = Instance.new("UIPadding"); titlePad.PaddingLeft=UDim.new(0,12); titlePad.Parent=title

            local info = Instance.new("TextLabel")
            info.LayoutOrder = 2; info.Size = UDim2.new(1,-4,0,38)
            info.BackgroundTransparency = 1
            info.Text = "Clique sur TOUCHE puis appuie sur une touche du clavier. Échap annule, Retour arrière/Suppr efface."
            info.TextColor3 = Color3.fromRGB(170,178,190); info.TextSize = 10
            info.Font = Enum.Font.GothamMedium; info.TextWrapped=true
            info.TextXAlignment = Enum.TextXAlignment.Left; info.TextYAlignment=Enum.TextYAlignment.Center
            info.ZIndex=92; info.Parent=bindsPage
            local infoPad=Instance.new("UIPadding"); infoPad.PaddingLeft=UDim.new(0,8); infoPad.Parent=info

            local rowButtons = {}
            local rowData = {}

            -- Aucun menu déroulant : cliquer sur le bouton TOUCHE démarre une capture clavier.
            -- Cela évite que l'ancienne petite liste se retrouve masquée par d'autres panneaux.
            local function closeDropdown()
                bindCaptureEntry = nil
                bindCaptureButton = nil
                activeBindDropdown = nil
                if refreshBindsUI then pcall(refreshBindsUI) end
            end

            local function openDropdown(entry, ownerRow, ownerButton)
                if bindCaptureEntry == entry then
                    closeDropdown()
                    return
                end
                closeDropdown()
                bindCaptureEntry = entry
                bindCaptureButton = ownerButton
                activeBindDropdown = entry
                ownerButton.BackgroundColor3 = Color3.fromRGB(60,90,145)
                ownerButton.Text = "APPUIE UNE TOUCHE"
            end

            local order=3
            for _, id in ipairs(BindOrder) do
                local entry=BindConfig[id]
                if entry then
                    local row=Instance.new("Frame")
                    row.LayoutOrder=order; order+=1
                    row.Size=UDim2.new(1,-4,0,46)
                    row.BackgroundColor3=Color3.fromRGB(31,38,48); row.BorderSizePixel=0; row.ZIndex=92
                    row.Parent=bindsPage; makeCorner(row,8)
                    rowData[id]=row

                    local label=Instance.new("TextLabel")
                    label.Size=UDim2.new(1,-145,1,0); label.Position=UDim2.fromOffset(10,0)
                    label.BackgroundTransparency=1; label.Text=entry.label
                    label.TextColor3=Color3.fromRGB(235,238,244); label.TextSize=11
                    label.Font=Enum.Font.GothamBold; label.TextXAlignment=Enum.TextXAlignment.Left
                    label.TextYAlignment=Enum.TextYAlignment.Center; label.ZIndex=93; label.Parent=row

                    local keyButton=Instance.new("TextButton")
                    keyButton.Size=UDim2.fromOffset(122,30); keyButton.Position=UDim2.new(1,-132,0.5,-15)
                    keyButton.BackgroundColor3=Color3.fromRGB(45,54,67); keyButton.BorderSizePixel=0
                    keyButton.AutoButtonColor=true; keyButton.Text="TOUCHE : "..bindKeyToDisplay(entry.key)
                    keyButton:SetAttribute("BindKeyValue", entry.key)
                    keyButton.TextColor3=Color3.fromRGB(245,247,250); keyButton.TextSize=9
                    keyButton.Font=Enum.Font.GothamBold; keyButton.ZIndex=94; keyButton.Parent=row; makeCorner(keyButton,7)
                    rowButtons[id]=keyButton
                    keyButton.MouseButton1Click:Connect(function() openDropdown(entry,row,keyButton) end)
                end
            end

            refreshBindsUI=function()
                for _, id in ipairs(BindOrder) do
                    local button=rowButtons[id]
                    local entry=BindConfig[id]
                    if entry and button then
                        button:SetAttribute("BindKeyValue", entry.key)
                        if bindCaptureEntry == entry then
                            button.Text = "APPUIE UNE TOUCHE"
                            button.BackgroundColor3 = Color3.fromRGB(60,90,145)
                        else
                            button.Text = "TOUCHE : " .. bindKeyToDisplay(entry.key)
                            button.BackgroundColor3 = Color3.fromRGB(45,54,67)
                        end
                    end
                end
            end

            local clear=Instance.new("TextButton")
            clear.LayoutOrder=order; order+=1; clear.Size=UDim2.new(1,-4,0,42)
            clear.BackgroundColor3=Color3.fromRGB(95,70,48); clear.BorderSizePixel=0; clear.AutoButtonColor=true
            clear.Text="✕ EFFACER TOUS LES BINDS"; clear.TextColor3=Color3.fromRGB(255,255,255)
            clear.TextSize=11; clear.Font=Enum.Font.GothamBold; clear.ZIndex=93; clear.Parent=bindsPage; makeCorner(clear,8)
            clear.MouseButton1Click:Connect(function() resetBindState() end)

            local active=false
            local iconColor=Color3.fromRGB(92,97,108)
            local activeColor=Color3.fromRGB(132,165,230)

            local bindsTab=Instance.new("TextButton")
            bindsTab.Name="V7Tab_Binds"; bindsTab.Parent=settingsSidebar
            bindsTab.Position=UDim2.fromOffset(6,5+(6*31)); bindsTab.Size=UDim2.fromOffset(31,27)
            bindsTab.BackgroundColor3=Color3.fromRGB(25,29,37); bindsTab.BackgroundTransparency=1
            bindsTab.BorderSizePixel=0; bindsTab.AutoButtonColor=false; bindsTab.Text=""; bindsTab.ZIndex=102
            makeCorner(bindsTab,4)
            local bi=Instance.new("TextLabel"); bi.Name="V7Icon"; bi.Parent=bindsTab; bi.Position=UDim2.fromOffset(0,-2); bi.Size=UDim2.fromOffset(31,31)
            bi.BackgroundTransparency=1; bi.Text="⌨"; bi.TextColor3=iconColor; bi.Font=Enum.Font.GothamBold; bi.TextSize=18
            bi.TextXAlignment=Enum.TextXAlignment.Center; bi.TextYAlignment=Enum.TextYAlignment.Center; bi.ZIndex=103
            local bl=Instance.new("TextLabel"); bl.Name="V7Label"; bl.Parent=bindsTab; bl.Position=UDim2.fromOffset(36,0); bl.Size=UDim2.new(1,-40,1,0)
            bl.BackgroundTransparency=1; bl.Text="BINDS"; bl.TextColor3=Color3.fromRGB(116,121,132); bl.Font=Enum.Font.GothamBold; bl.TextSize=11
            bl.TextXAlignment=Enum.TextXAlignment.Left; bl.TextYAlignment=Enum.TextYAlignment.Center; bl.TextTransparency=1; bl.ZIndex=103

            local marker=settingsMarker
            local glow=settingsGlow
            local function setBindsActive(v)
                active=v; local scale=(MainFrameScale and MainFrameScale.Scale) or 1
                local expanded=(settingsSidebar.AbsoluteSize.X/scale)>=100
                bindsTab.BackgroundTransparency=(expanded and v) and 0.72 or 1
                bi.TextColor3=v and activeColor or iconColor
                if v then
                    if marker then marker.Position=UDim2.fromOffset(0,bindsTab.Position.Y.Offset+5) end
                    if glow then glow.Position=UDim2.fromOffset(0,bindsTab.Position.Y.Offset+5) end
                end
            end

            showBindsPage=function()
                for _,name in ipairs({"Content","OmegaOthersPage","OmegaESPPage","OmegaAutresPage","AimbotPage","OmegaSettingsPage"}) do
                    local pg=settingsBody:FindFirstChild(name)
                    if pg and pg:IsA("GuiObject") then pg.Visible=false end
                end
                bindsPage.Visible=true
                _G.PRISONRP_ACTIVE_UI_PAGE = 7
                if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
                    pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, 7)
                end
                fitBindsPage(); setBindsActive(true)
                local currentSettingsTab = settingsSidebar and settingsSidebar:FindFirstChild("V7Tab_Settings")
                if currentSettingsTab then
                    currentSettingsTab.BackgroundTransparency=1
                    local si=currentSettingsTab:FindFirstChild("V7Icon")
                    if si then si.TextColor3=iconColor end
                end
                local aim=settingsSidebar and settingsSidebar:FindFirstChild("V7Tab_Aimbot")
                local ai=aim and aim:FindFirstChild("V7Icon")
                if aim then aim.BackgroundTransparency=1 end
                if ai then ai.TextColor3=iconColor end
                refreshBindsUI()
            end

            bindsTab.MouseButton1Click:Connect(showBindsPage)
            bindsTab.MouseEnter:Connect(function()
                if type(_G.PRISONRP_V7_SET_EXPANDED) == "function" then
                    _G.PRISONRP_V7_SET_EXPANDED(true)
                end
                fitBindsPage()
            end)
            settingsSidebar:GetPropertyChangedSignal("Size"):Connect(function()
                local scale=(MainFrameScale and MainFrameScale.Scale) or 1
                local open=(settingsSidebar.AbsoluteSize.X/scale)>=100
                bindsTab.Size=UDim2.fromOffset(open and 130 or 31,27)
                bl.TextTransparency=open and 0 or 1
                bindsTab.Position=UDim2.fromOffset(6,5+(6*31))
                fitBindsPage()
                if active then setBindsActive(true) else bindsTab.BackgroundTransparency=1 end
            end)
            for i=1,4 do
                local b=settingsSidebar:FindFirstChild("V7Tab_"..tostring(i))
                if b then b.MouseButton1Click:Connect(function() bindsPage.Visible=false; setBindsActive(false); closeDropdown() end) end
            end
            local aim=settingsSidebar:FindFirstChild("V7Tab_Aimbot")
            if aim then aim.MouseButton1Click:Connect(function() bindsPage.Visible=false; setBindsActive(false); closeDropdown() end) end
            if settingsTab then settingsTab.MouseButton1Click:Connect(function() bindsPage.Visible=false; setBindsActive(false); closeDropdown() end) end

            BindPages.Fit=fitBindsPage
            refreshBindsUI()
        end

        local function loadSettings()
            -- Priorité à la sauvegarde 1 pour conserver le chargement automatique existant.
            local data = readSettingsFile(slotFiles[1]) or readSettingsFile(settingsFile)
            if type(data) == "table" then
                pcall(function() applyLoadedSettings(data) end)
            end
        end

        -- Création unique de l'onglet, juste sous AIMBOT.
        local oldSettingsTab = settingsSidebar:FindFirstChild("V7Tab_Settings")
        if oldSettingsTab then oldSettingsTab:Destroy() end

        local settingsTab = Instance.new("TextButton")
        settingsTab.Name = "V7Tab_Settings"
        settingsTab.Parent = settingsSidebar
        settingsTab.Position = UDim2.fromOffset(6, 5 + (5 * 31))
        settingsTab.Size = UDim2.fromOffset(31,27)
        settingsTab.BackgroundColor3 = Color3.fromRGB(25,29,37)
        settingsTab.BackgroundTransparency = 1
        settingsTab.BorderSizePixel = 0
        settingsTab.AutoButtonColor = false
        settingsTab.Text = ""
        settingsTab.ZIndex = 102
        makeCorner(settingsTab, 4)

        local icon = Instance.new("TextLabel")
        icon.Name = "V7Icon"
        icon.Parent = settingsTab
        icon.Position = UDim2.fromOffset(0,-2)
        icon.Size = UDim2.fromOffset(31,31)
        icon.BackgroundTransparency = 1
        icon.Text = "⚙"
        icon.TextColor3 = Color3.fromRGB(92,97,108)
        icon.Font = Enum.Font.GothamBold
        icon.TextSize = 18
        icon.TextXAlignment = Enum.TextXAlignment.Center
        icon.TextYAlignment = Enum.TextYAlignment.Center
        icon.ZIndex = 103

        local label = Instance.new("TextLabel")
        label.Name = "V7Label"
        label.Parent = settingsTab
        label.Position = UDim2.fromOffset(36,0)
        label.Size = UDim2.new(1,-40,1,0)
        label.BackgroundTransparency = 1
        label.Text = "PARAMÈTRES"
        label.TextColor3 = Color3.fromRGB(116,121,132)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextTransparency = 1
        label.ZIndex = 103

        local settingsMarker, settingsGlow
        for _, child in ipairs(settingsSidebar:GetChildren()) do
            if child:IsA("Frame") and child.Size == UDim2.fromOffset(2,22) then
                if child.BackgroundTransparency < 0.5 and not settingsMarker then
                    settingsMarker = child
                elseif child.BackgroundTransparency >= 0.5 and not settingsGlow then
                    settingsGlow = child
                end
            end
        end

        local settingsActive = false
        local function setSettingsActive(active)
            settingsActive = active
            local scale = (MainFrameScale and MainFrameScale.Scale) or 1
            local expanded = (settingsSidebar.AbsoluteSize.X / scale) >= 100
            settingsTab.BackgroundTransparency = (expanded and active) and 0.72 or 1
            icon.TextColor3 = active and Color3.fromRGB(132,165,230) or Color3.fromRGB(92,97,108)
            if active then
                if settingsMarker then
                    settingsMarker.Position = UDim2.fromOffset(0, settingsTab.Position.Y.Offset + 5)
                end
                if settingsGlow then
                    settingsGlow.Position = UDim2.fromOffset(0, settingsTab.Position.Y.Offset + 5)
                end
            end
        end

        local function showSettingsPage()
            -- Paramètres et BINDS sont exclusifs : un seul panneau visible à la fois.
            for _, name in ipairs({"Content","OmegaOthersPage","OmegaESPPage","OmegaAutresPage","AimbotPage","OmegaBindsPage"}) do
                local page = settingsBody:FindFirstChild(name)
                if page and page:IsA("GuiObject") then page.Visible = false end
            end
            if BindPages and BindPages.Page and BindPages.Page:IsA("GuiObject") then
                BindPages.Page.Visible = false
            end
            settingsPage.Visible = true
            _G.PRISONRP_ACTIVE_UI_PAGE = 6
            if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
                pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, 6)
            end
            if type(closeDropdown) == "function" then
                pcall(closeDropdown)
            end
            fitSettingsPage()
            setSettingsActive(true)

            for i = 1, 4 do
                local b = settingsSidebar:FindFirstChild("V7Tab_" .. tostring(i))
                local bi = b and b:FindFirstChild("V7Icon")
                if b then b.BackgroundTransparency = 1 end
                if bi then bi.TextColor3 = Color3.fromRGB(92,97,108) end
            end
            local aim = settingsSidebar:FindFirstChild("V7Tab_Aimbot")
            local ai = aim and aim:FindFirstChild("V7Icon")
            if aim then aim.BackgroundTransparency = 1 end
            if ai then ai.TextColor3 = Color3.fromRGB(92,97,108) end
        end

        settingsTab.MouseButton1Click:Connect(showSettingsPage)
        settingsTab.MouseEnter:Connect(function()
            if type(_G.PRISONRP_V7_SET_EXPANDED) == "function" then
                _G.PRISONRP_V7_SET_EXPANDED(true)
            end
            fitSettingsPage()
        end)

        settingsSidebar:GetPropertyChangedSignal("Size"):Connect(function()
            local scale = (MainFrameScale and MainFrameScale.Scale) or 1
            local open = (settingsSidebar.AbsoluteSize.X / scale) >= 100
            settingsTab.Size = UDim2.fromOffset(open and 130 or 31, 27)
            label.TextTransparency = open and 0 or 1
            settingsTab.Position = UDim2.fromOffset(6, 5 + (5 * 31))
            fitSettingsPage()
            if settingsActive then
                setSettingsActive(true)
            else
                settingsTab.BackgroundTransparency = 1
            end
        end)

        for i = 1, 4 do
            local b = settingsSidebar:FindFirstChild("V7Tab_" .. tostring(i))
            if b then
                b.MouseButton1Click:Connect(function()
                    settingsPage.Visible = false
                    setSettingsActive(false)
                end)
            end
        end

        local aim = settingsSidebar:FindFirstChild("V7Tab_Aimbot")
        if aim then
            aim.MouseButton1Click:Connect(function()
                settingsPage.Visible = false
                setSettingsActive(false)
            end)
        end

        fitSettingsPage()
        task.defer(function()
            task.wait()
            fitSettingsPage()
            loadSettings()

            -- Après le chargement, certaines fonctions finissent leur initialisation
            -- un peu plus tard. On resynchronise donc les switches plusieurs fois.
            -- Le restore visuel principal est effectué dans applyLoadedSettings(),
            -- avec des références valides même hors du pcall principal.
            status.Text = "Choisis une sauvegarde ou réinitialise les paramètres."
        end)
    end
end

-- V196 : garde globale d'exclusivité des 7 pages. Utilisée après chaque clic,
-- changement de taille, restauration de l'interface et changement de sidebar.
_G.PRISONRP_ACTIVE_UI_PAGE = tonumber(_G.PRISONRP_ACTIVE_UI_PAGE) or tonumber(v7Selected) or 1
_G.PRISONRP_ENFORCE_ACTIVE_PAGE = function(pageIndex)
    local body = MainFrame and MainFrame:FindFirstChild("V7Body")
    if not body then return end

    local pageNames = {
        [1] = "Content",
        [2] = "OmegaOthersPage",
        [3] = "OmegaESPPage",
        [4] = "OmegaAutresPage",
        [5] = "AimbotPage",
        [6] = "OmegaSettingsPage",
        [7] = "OmegaBindsPage",
    }
    local selected = math.clamp(math.floor(tonumber(pageIndex) or tonumber(_G.PRISONRP_ACTIVE_UI_PAGE) or 1), 1, 7)
    _G.PRISONRP_ACTIVE_UI_PAGE = selected

    for index, name in pairs(pageNames) do
        local page = body:FindFirstChild(name)
        if page and page:IsA("GuiObject") then
            page.Visible = (index == selected)
        end
    end
end

--==============================================================
-- V188 FINAL : FREECAM puis INVISIBLE dans DÉPLACEMENT
-- Même largeur, mêmes dimensions et même style de switch.
--==============================================================
pcall(function()
    if movementPage then
        if InvisibleCard then
            InvisibleCard.Parent = movementPage
            InvisibleCard.Visible = true
            InvisibleCard.Size = UDim2.new(1, -281, 0, 48)
            InvisibleCard.Position = UDim2.new(0, 0, 0, 252)
            InvisibleCard.Text = "🫥 INVISIBLE"
            InvisibleCard.TextXAlignment = Enum.TextXAlignment.Center
            InvisibleCard.TextYAlignment = Enum.TextYAlignment.Center
            InvisibleCard.ZIndex = 100
            local sw = InvisibleCard:FindFirstChild("GDPCheckbox")
            if sw then
                sw.Visible = true
                sw.ZIndex = 103
            end
        end

        if SpecCard then
            SpecCard.Parent = movementPage
            SpecCard.Visible = true
            SpecCard.Size = UDim2.new(1, -281, 0, 48)
            SpecCard.Position = UDim2.new(0, 0, 0, 198)
            SpecCard.Text = "🎥 FREECAM"
            SpecCard.TextXAlignment = Enum.TextXAlignment.Center
            SpecCard.TextYAlignment = Enum.TextYAlignment.Center
            SpecCard.ZIndex = 100
            local sw = SpecCard:FindFirstChild("GDPCheckbox")
            if sw then
                sw.Visible = true
                sw.ZIndex = 103
            end
        end
    end
end)



-- Fond animé retiré volontairement : le script repart sans système de fond.


_G.PRISONRP_AIMBOT_STOP = function()
    Running = false
    pcall(CancelLock)
    pcall(function()
        if FOVCircle then FOVCircle.Visible = false end
    end)
    for _, c in pairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Connections)
    pcall(function()
        if FOVCircle then FOVCircle:Remove() end
    end)
    _G.PRISONRP_AIMBOT = nil
end



end


--==============================================================
-- V212 : POLISH VISUEL GLOBAL (feedback fiable + palette cohérente)
-- Thème cohérent, focus/hover discrets, coins/bordures homogènes,
-- en-tête réorganisé et barres de défilement uniformes.
--==============================================================
pcall(function()
    if not ScreenGui or not ScreenGui.Parent or not MainFrame or not MainFrame.Parent then
        return
    end

    local TweenService = game:GetService("TweenService")
    local UX = {
        Window = Color3.fromRGB(18, 21, 28),
        Header = Color3.fromRGB(14, 17, 23),
        Surface = Color3.fromRGB(31, 38, 48), -- fond uniforme des cartes
        Panel = Color3.fromRGB(22, 27, 35), -- panneaux plus sombres pour la hiérarchie visuelle
        Input = Color3.fromRGB(25, 30, 39),
        Border = Color3.fromRGB(48, 57, 72),
        Accent = Color3.fromRGB(79, 142, 255),
        Text = Color3.fromRGB(236, 240, 248),
        Muted = Color3.fromRGB(153, 163, 180),
        Good = Color3.fromRGB(40, 150, 80),
    }

    local function directChildOfClass(parent, className)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA(className) then return child end
        end
        return nil
    end

    local function ensureCorner(gui, radius)
        if not gui or directChildOfClass(gui, "UICorner") then return end
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius or 6)
        corner.Parent = gui
    end

    local function ensureStroke(gui, color, transparency, name)
        if not gui then return nil, false end
        local existing = directChildOfClass(gui, "UIStroke")
        if existing then return existing, false end
        local stroke = Instance.new("UIStroke")
        stroke.Name = name or "PRISONRP_UXStroke"
        stroke.Color = color or UX.Border
        stroke.Transparency = transparency == nil and 0.72 or transparency
        stroke.Thickness = 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = gui
        return stroke, true
    end

    -- Contours d'interaction séparés des contours décoratifs ou d'état.
    -- Cela évite qu'un hover restaure une ancienne couleur de bordure après
    -- qu'un switch ou un onglet a changé d'état pendant le survol.
    local function ensureTransientStroke(gui, name, color, transparency, thickness)
        if not gui then return nil end
        local stroke = gui:FindFirstChild(name)
        if stroke and stroke:IsA("UIStroke") then return stroke end
        stroke = Instance.new("UIStroke")
        stroke.Name = name
        stroke.Color = color or UX.Accent
        stroke.Transparency = transparency == nil and 1 or transparency
        stroke.Thickness = thickness or 1.35
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = gui
        return stroke
    end

    -- Conteneur principal : contour fin sans modifier la taille ni les positions.
    MainFrame.BackgroundColor3 = UX.Window
    MainFrame.BorderSizePixel = 0
    ensureCorner(MainFrame, 10)
    ensureStroke(MainFrame, UX.Border, 0.38, "PRISONRP_DesignStroke")

    -- En-tête : plus de chevauchement entre le titre et le raccourci clavier.
    if TitleBar then
        TitleBar.BackgroundColor3 = UX.Header
        TitleBar.BorderSizePixel = 0
        ensureCorner(TitleBar, 10)

        if TitleLabel then
            TitleLabel.Position = UDim2.fromOffset(14, 0)
            TitleLabel.Size = UDim2.fromOffset(210, 44)
            TitleLabel.Text = "⛏ PRISON RP"
            TitleLabel.TextColor3 = UX.Text
            TitleLabel.TextSize = 13
            TitleLabel.Font = Enum.Font.GothamBold
        end
        if RightShiftLabel then
            RightShiftLabel.Position = UDim2.fromOffset(238, 0)
            RightShiftLabel.Size = UDim2.fromOffset(310, 44)
            RightShiftLabel.Text = "RIGHT SHIFT  •  AFFICHER / MASQUER"
            RightShiftLabel.TextColor3 = UX.Muted
            RightShiftLabel.TextSize = 9
            RightShiftLabel.Font = Enum.Font.GothamMedium
        end

        local accentLine = TitleBar:FindFirstChild("PRISONRP_HeaderAccent")
        if not accentLine then
            accentLine = Instance.new("Frame")
            accentLine.Name = "PRISONRP_HeaderAccent"
            accentLine.BorderSizePixel = 0
            accentLine.ZIndex = 119
            accentLine.Parent = TitleBar
        end
        accentLine.Position = UDim2.new(0, 10, 1, -2)
        accentLine.Size = UDim2.new(1, -20, 0, 2)
        accentLine.BackgroundColor3 = UX.Accent

        local statusPill = TitleBar:FindFirstChild("PRISONRP_HeaderStatus")
        if not statusPill then
            statusPill = Instance.new("Frame")
            statusPill.Name = "PRISONRP_HeaderStatus"
            statusPill.Parent = TitleBar
        end
        statusPill.AnchorPoint = Vector2.new(0, 0)
        statusPill.Position = UDim2.new(1, -216, 0, 10)
        statusPill.Size = UDim2.fromOffset(88, 24)
        statusPill.BackgroundColor3 = Color3.fromRGB(25, 43, 36)
        statusPill.BorderSizePixel = 0
        statusPill.ZIndex = 118
        ensureCorner(statusPill, 7)
        ensureStroke(statusPill, Color3.fromRGB(55, 125, 87), 0.42, "PRISONRP_HeaderStatusStroke")

        local statusDot = statusPill:FindFirstChild("PRISONRP_StatusDot")
        if not statusDot then
            statusDot = Instance.new("Frame")
            statusDot.Name = "PRISONRP_StatusDot"
            statusDot.Parent = statusPill
        end
        statusDot.Position = UDim2.fromOffset(8, 8)
        statusDot.Size = UDim2.fromOffset(7, 7)
        statusDot.BackgroundColor3 = UX.Good
        statusDot.BorderSizePixel = 0
        statusDot.ZIndex = 119
        ensureCorner(statusDot, 4)

        local statusText = statusPill:FindFirstChild("PRISONRP_StatusText")
        if not statusText then
            statusText = Instance.new("TextLabel")
            statusText.Name = "PRISONRP_StatusText"
            statusText.Parent = statusPill
        end
        statusText.Position = UDim2.fromOffset(20, 0)
        statusText.Size = UDim2.new(1, -23, 1, 0)
        statusText.BackgroundTransparency = 1
        statusText.Text = "0 / 0"
        statusText.TextColor3 = Color3.fromRGB(176, 235, 200)
        statusText.Font = Enum.Font.GothamBold
        statusText.TextSize = 8
        statusText.TextXAlignment = Enum.TextXAlignment.Left
        statusText.TextYAlignment = Enum.TextYAlignment.Center
        statusText.ZIndex = 119

        -- V219 : compteur dynamique du nombre de joueurs dans le serveur / capacité maximale.
        -- Le compteur remplace le badge de version sans modifier les fonctionnalités du hub.
        local playerService = game:GetService("Players")
        local function updateHeaderPlayerCount()
            if not statusText or not statusText.Parent then return end
            local currentCount = #playerService:GetPlayers()
            local maxCount = tonumber(playerService.MaxPlayers) or currentCount
            maxCount = math.max(currentCount, maxCount)
            statusText.Text = string.format("%d / %d", currentCount, maxCount)
        end

        _G.PRISONRP_UPDATE_PLAYER_COUNT = updateHeaderPlayerCount
        updateHeaderPlayerCount()

        local playerCountConnections = {
            playerService.PlayerAdded:Connect(function()
                task.defer(updateHeaderPlayerCount)
            end),
            playerService.PlayerRemoving:Connect(function()
                task.defer(updateHeaderPlayerCount)
            end),
        }
        ScreenGui.Destroying:Connect(function()
            for _, connection in ipairs(playerCountConnections) do
                pcall(function() connection:Disconnect() end)
            end
            if _G.PRISONRP_UPDATE_PLAYER_COUNT == updateHeaderPlayerCount then
                _G.PRISONRP_UPDATE_PLAYER_COUNT = nil
            end
        end)
    end

    -- Lisibilité des trois informations principales de la page Farm.
    if Content then
        for _, name in ipairs({"StatusLabel", "StatsLabel", "LastFishLabel"}) do
            local label = Content:FindFirstChild(name)
            if label and label:IsA("TextLabel") then
                label.BorderSizePixel = 0
                label.BackgroundColor3 = UX.Surface
                ensureCorner(label, 5)
                ensureStroke(label, UX.Border, 0.72, "PRISONRP_StatusStroke")
            end
        end
    end

    -- Polissage cohérent de l'ensemble des contrôles déjà existants.
    -- Les couleurs d'état ON/OFF et les fonctions de clic restent intactes.
    for _, obj in ipairs(ScreenGui:GetDescendants()) do
        if obj:IsA("ScrollingFrame") then
            obj.ScrollBarImageColor3 = UX.Accent
            if obj.ScrollBarThickness > 0 then
                obj.ScrollBarThickness = math.max(4, obj.ScrollBarThickness)
            end
        elseif obj:IsA("TextBox") then
            obj.BorderSizePixel = 0
            obj.BackgroundColor3 = UX.Input
            obj.TextColor3 = UX.Text
            obj.PlaceholderColor3 = UX.Muted
            ensureCorner(obj, 5)
            local stroke = ensureTransientStroke(obj, "PRISONRP_UXFocusStroke", UX.Accent, 1, 1.35)
            if stroke and not obj:GetAttribute("PRISONRP_UXFocusBound") then
                obj:SetAttribute("PRISONRP_UXFocusBound", true)
                obj.Focused:Connect(function()
                    if not stroke or not stroke.Parent then return end
                    TweenService:Create(stroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Transparency = 0.08,
                        Thickness = 1.6,
                    }):Play()
                end)
                obj.FocusLost:Connect(function()
                    if not stroke or not stroke.Parent then return end
                    TweenService:Create(stroke, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Transparency = 1,
                        Thickness = 1.35,
                    }):Play()
                end)
            end
            if not directChildOfClass(obj, "UIPadding") then
                local padding = Instance.new("UIPadding")
                padding.Name = "PRISONRP_InputPadding"
                padding.PaddingLeft = UDim.new(0, 7)
                padding.PaddingRight = UDim.new(0, 7)
                padding.Parent = obj
            end
        elseif obj:IsA("TextButton") then
            obj.BorderSizePixel = 0
            local hasVisibleFill = obj.BackgroundTransparency < 0.96
            if hasVisibleFill then
                ensureCorner(obj, 6)
            end

            -- IMPORTANT V212 : le retour visuel doit être lié même si le bouton
            -- possédait déjà un UIStroke. V211 ne liait les événements que si
            -- ensureStroke venait de créer un contour, ce qui laissait la majorité
            -- des boutons sans survol après AutoButtonColor = false.
            local stroke = nil
            if hasVisibleFill then
                stroke = ensureTransientStroke(obj, "PRISONRP_UXHoverStroke", UX.Accent, 1, 1.4)
                obj.AutoButtonColor = false
            else
                -- Les boutons transparents (tabs / click blockers) gardent le
                -- feedback natif Roblox ; on évite de leur ajouter un contour visible.
                obj.AutoButtonColor = true
            end

            if stroke and not obj:GetAttribute("PRISONRP_UXHoverBound") then
                obj:SetAttribute("PRISONRP_UXHoverBound", true)
                local baseTransparency = 1
                local baseThickness = 1.4
                local hovered = false
                local pressed = false
                local activeTween = nil

                local function applyStroke(color, transparency, thickness, duration)
                    if not stroke or not stroke.Parent then return end
                    if activeTween then
                        pcall(function() activeTween:Cancel() end)
                        activeTween = nil
                    end
                    activeTween = TweenService:Create(stroke,
                        TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        {Color = color, Transparency = transparency, Thickness = thickness})
                    activeTween:Play()
                end

                local function refreshStroke()
                    if pressed then
                        applyStroke(UX.Accent, 0.02, 2, 0.06)
                    elseif hovered then
                        applyStroke(UX.Accent, 0.08, 1.5, 0.11)
                    else
                        applyStroke(UX.Accent, baseTransparency, baseThickness, 0.13)
                    end
                end

                obj.MouseEnter:Connect(function()
                    hovered = true
                    refreshStroke()
                end)
                obj.MouseLeave:Connect(function()
                    hovered = false
                    pressed = false
                    refreshStroke()
                end)
                obj.MouseButton1Down:Connect(function()
                    pressed = true
                    refreshStroke()
                end)
                obj.MouseButton1Up:Connect(function()
                    pressed = false
                    refreshStroke()
                end)
            end

            -- Les interrupteurs utilisent une piste verte ON / grise OFF ; leur
            -- carte reste toujours neutre. On réapplique le fond neutre si une
            -- ancienne fonction essaie de remettre une couleur différente.
            if obj:FindFirstChild("GDPCheckbox") then
                local normalizing = false
                local function normalizeToggleCard()
                    if normalizing or not obj.Parent then return end
                    if obj:FindFirstChild("GDPCheckbox") and obj.BackgroundColor3 ~= UX.Surface then
                        normalizing = true
                        obj.BackgroundColor3 = UX.Surface
                        normalizing = false
                    end
                end
                normalizeToggleCard()
                if not obj:GetAttribute("PRISONRP_UXCardColorBound") then
                    obj:SetAttribute("PRISONRP_UXCardColorBound", true)
                    obj:GetPropertyChangedSignal("BackgroundColor3"):Connect(normalizeToggleCard)
                end
            end
        elseif obj:IsA("Frame") then
            local lowerName = string.lower(obj.Name)
            local looksLikeCard = lowerName:match("card$")
                or lowerName:match("panel$")
                or lowerName:match("section$")
                or lowerName:find("needbox", 1, true) ~= nil
            if looksLikeCard and obj.BackgroundTransparency < 0.96 then
                obj.BorderSizePixel = 0
                obj.BackgroundColor3 = lowerName:match("panel$") and UX.Panel or UX.Surface
                ensureCorner(obj, 8)
                ensureStroke(obj, UX.Border, 0.62, "PRISONRP_CardStroke")
            end
        end
    end

    -- Auto Buy n'utilise pas de switch GDP : ON vert, OFF couleur carte.
    -- L'observateur neutralise aussi les anciennes affectations rouges au stop.
    if StartBtn and StartBtn.Parent and not StartBtn:GetAttribute("PRISONRP_UXAutoBuyColorBound") then
        StartBtn:SetAttribute("PRISONRP_UXAutoBuyColorBound", true)
        local syncingAutoBuy = false
        local function syncAutoBuyColor()
            if syncingAutoBuy or not StartBtn or not StartBtn.Parent then return end
            local active = buyRequest == true
            local wanted = active and UX.Good or UX.Surface
            if StartBtn.BackgroundColor3 ~= wanted then
                syncingAutoBuy = true
                StartBtn.BackgroundColor3 = wanted
                syncingAutoBuy = false
            end
            StartBtn.TextColor3 = UX.Text
        end
        StartBtn:GetPropertyChangedSignal("BackgroundColor3"):Connect(syncAutoBuyColor)
        StartBtn:GetPropertyChangedSignal("Text"):Connect(function()
            task.defer(syncAutoBuyColor)
        end)
        StartBtn.MouseButton1Click:Connect(function()
            task.defer(syncAutoBuyColor)
            task.delay(0.12, syncAutoBuyColor)
        end)
        syncAutoBuyColor()
    end
end)


--==============================================================
-- V213 : NAVIGATION UNIFIÉE (7 onglets) + EN-TÊTE CONTEXTUEL
-- Harmonise l'état actif des onglets principaux, Aimbot, Paramètres et Binds.
-- Ne modifie pas les fonctions métier ni la logique des interrupteurs.
--==============================================================
pcall(function()
    if not ScreenGui or not ScreenGui.Parent or not MainFrame or not MainFrame.Parent then
        return
    end

    local navBody = MainFrame:FindFirstChild("V7Body")
    local navSidebar = navBody and navBody:FindFirstChild("V7Sidebar")
    if not navBody or not navSidebar then return end

    -- Le contenu Farm comporte un dernier statut minage sous les boutons TP ;
    -- sa zone de défilement doit couvrir toute la dernière ligne sans créer un long vide.
    if Content and Content:IsA("ScrollingFrame") then
        Content.AutomaticCanvasSize = Enum.AutomaticSize.None
        Content.CanvasSize = UDim2.fromOffset(0, 455)
    end

    -- Le panneau Give Money finit juste après ses contrôles : la hauteur réduite
    -- évite qu'il dépasse de la page AUTRES sur la taille normale du hub.
    local autresPageRef = navBody:FindFirstChild("OmegaAutresPage")
    local giveMoneyPanel = autresPageRef and autresPageRef:FindFirstChild("GiveMoneyPanel")
    if giveMoneyPanel and giveMoneyPanel:IsA("GuiObject") then
        giveMoneyPanel.Position = UDim2.new(1, -205, 0, 30)
        giveMoneyPanel.Size = UDim2.fromOffset(205, 410)
    end

    local activeText = Color3.fromRGB(226, 235, 250)
    local idleText = Color3.fromRGB(116, 124, 139)
    local activeIcon = Color3.fromRGB(132, 165, 230)
    local idleIcon = Color3.fromRGB(92, 97, 108)
    local tabNames = {
        [1] = "V7Tab_1",
        [2] = "V7Tab_2",
        [3] = "V7Tab_3",
        [4] = "V7Tab_4",
        [5] = "V7Tab_Aimbot",
        [6] = "V7Tab_Settings",
        [7] = "V7Tab_Binds",
    }
    local pageTitles = {
        [1] = "FARM",
        [2] = "DÉPLACEMENT",
        [3] = "ESP",
        [4] = "AUTRES",
        [5] = "AIMBOT",
        [6] = "PARAMÈTRES",
        [7] = "RACCOURCIS",
    }

    local function findMarkers()
        local marker, glow
        for _, child in ipairs(navSidebar:GetChildren()) do
            if child:IsA("Frame")
                and child.Size.X.Offset == 2
                and child.Size.Y.Offset == 22 then
                if child.BackgroundTransparency < 0.5 and not marker then
                    marker = child
                    marker.Name = "PRISONRP_ActiveTabMarker"
                elseif child.BackgroundTransparency >= 0.5 and not glow then
                    glow = child
                    glow.Name = "PRISONRP_ActiveTabGlow"
                end
            end
        end
        return marker, glow
    end

    local function readActivePage()
        local page = math.floor(tonumber(_G.PRISONRP_ACTIVE_UI_PAGE) or tonumber(v7Selected) or 1)
        return math.clamp(page, 1, 7)
    end

    local function syncNavigation(updateLabelVisibility)
        if not ScreenGui or not ScreenGui.Parent or not navSidebar or not navSidebar.Parent then
            return
        end

        local page = readActivePage()
        if type(_G.PRISONRP_ENFORCE_ACTIVE_PAGE) == "function" then
            pcall(_G.PRISONRP_ENFORCE_ACTIVE_PAGE, page)
        end
        local scale = math.max((MainFrameScale and MainFrameScale.Scale) or 1, 0.01)
        local expanded = (navSidebar.AbsoluteSize.X / scale) >= 100

        for index, name in pairs(tabNames) do
            local tab = navSidebar:FindFirstChild(name)
            if tab and tab:IsA("TextButton") then
                local selected = index == page
                tab.AutoButtonColor = false
                tab.BackgroundColor3 = Color3.fromRGB(25, 29, 37)
                tab.BackgroundTransparency = (expanded and selected) and 0.70 or 1

                local icon = tab:FindFirstChild("V7Icon")
                if icon and icon:IsA("TextLabel") then
                    icon.TextColor3 = selected and activeIcon or idleIcon
                end

                local label = tab:FindFirstChild("V7Label")
                if label and label:IsA("TextLabel") then
                    label.TextColor3 = selected and activeText or idleText
                    if updateLabelVisibility then
                        label.TextTransparency = expanded and 0 or 1
                    end
                end
            end
        end

        local selectedTab = navSidebar:FindFirstChild(tabNames[page])
        local marker, glow = findMarkers()
        if selectedTab then
            local targetPosition = UDim2.fromOffset(0, selectedTab.Position.Y.Offset + 5)
            if marker then marker.Position = targetPosition end
            if glow then glow.Position = targetPosition end
        end

        -- L'en-tête indique la page active au lieu d'afficher une aide statique.
        if RightShiftLabel and RightShiftLabel.Parent then
            local title = pageTitles[page] or "PRISON RP"
            RightShiftLabel.Text = title .. "  •  RIGHT SHIFT : AFFICHER / MASQUER"
            RightShiftLabel.TextColor3 = Color3.fromRGB(153, 163, 180)
            RightShiftLabel.TextSize = 9
            RightShiftLabel.Font = Enum.Font.GothamMedium
            RightShiftLabel.TextTruncate = Enum.TextTruncate.AtEnd
        end

        local titleBar = MainFrame:FindFirstChild("TitleBar")
        local status = titleBar and titleBar:FindFirstChild("PRISONRP_HeaderStatus")
        local statusText = status and status:FindFirstChild("PRISONRP_StatusText")
        if statusText and statusText:IsA("TextLabel") then
            if type(_G.PRISONRP_UPDATE_PLAYER_COUNT) == "function" then
                pcall(_G.PRISONRP_UPDATE_PLAYER_COUNT)
            else
                local playerService = game:GetService("Players")
                local currentCount = #playerService:GetPlayers()
                local maxCount = math.max(currentCount, tonumber(playerService.MaxPlayers) or currentCount)
                statusText.Text = string.format("%d / %d", currentCount, maxCount)
            end
        end
    end

    local function queueNavigationSync(updateLabelVisibility)
        task.defer(function()
            syncNavigation(updateLabelVisibility == true)
        end)
    end

    -- Rebind visuellement après les callbacks historiques : ils gardent la main
    -- sur la navigation fonctionnelle, cette couche ne fait que finaliser le style.
    for _, name in pairs(tabNames) do
        local tab = navSidebar:FindFirstChild(name)
        if tab and tab:IsA("TextButton") and not tab:GetAttribute("PRISONRP_V213_NavBound") then
            tab:SetAttribute("PRISONRP_V213_NavBound", true)
            tab.MouseButton1Click:Connect(function()
                task.defer(function()
                    syncNavigation(true)
                end)
            end)
        end
    end

    -- Le survol anime déjà les libellés dans le contrôleur d'origine ; ici on ne
    -- corrige que le fond de sélection et l'indicateur pendant l'ouverture/fermeture.
    navSidebar:GetPropertyChangedSignal("Size"):Connect(function()
        queueNavigationSync(false)
    end)
    MainFrame:GetPropertyChangedSignal("Size"):Connect(function()
        queueNavigationSync(false)
    end)
    navBody:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        queueNavigationSync(false)
    end)
    if MainFrameScale then
        MainFrameScale:GetPropertyChangedSignal("Scale"):Connect(function()
            queueNavigationSync(false)
        end)
    end

    syncNavigation(true)

    -- Couvre également les changements de page déclenchés par une restauration de
    -- paramètres ou par un autre panneau, sans rafraîchir inutilement chaque frame.
    task.spawn(function()
        local lastPage = nil
        local lastExpanded = nil
        while ScreenGui and ScreenGui.Parent and _G.CombinedHubLoaded do
            local currentPage = readActivePage()
            local scale = math.max((MainFrameScale and MainFrameScale.Scale) or 1, 0.01)
            local expanded = (navSidebar.AbsoluteSize.X / scale) >= 100
            if currentPage ~= lastPage then
                syncNavigation(true)
                lastPage = currentPage
            elseif expanded ~= lastExpanded then
                syncNavigation(false)
            end
            lastExpanded = expanded
            task.wait(0.25)
        end
    end)
end)


-- V193 : afficher uniquement l'interface finale après toute sa construction.
pcall(function()
    if ScreenGui and ScreenGui.Parent then
        _G.CombinedHubReady = true
        ScreenGui.Enabled = true
    end
end)
