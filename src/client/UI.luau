--!strict
-- Builds the full in-game HUD programmatically and returns references.
-- Layout follows the design doc mockup:
--   Top bar: match timer + players alive
--   Bottom: card hand (fanned row), turn/phase banner above it
--   Bottom-left: HP + status icons; Right edge: action feed
--   Overlays: draft screen, reaction prompt, scoreboard

local Players = game:GetService("Players")

local UI = {}

-- Wasteland palette
local COLORS = {
	panel = Color3.fromRGB(38, 32, 26),
	panelBorder = Color3.fromRGB(120, 90, 40),
	rust = Color3.fromRGB(183, 98, 45),
	sand = Color3.fromRGB(216, 176, 121),
	blood = Color3.fromRGB(170, 40, 30),
	text = Color3.fromRGB(235, 225, 205),
	accent = Color3.fromRGB(240, 200, 60),
	hp = Color3.fromRGB(90, 180, 80),
	hpLow = Color3.fromRGB(200, 60, 40),
}

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(150, 150, 150),
	Uncommon = Color3.fromRGB(80, 160, 220),
	Trap = Color3.fromRGB(200, 130, 40),
	Support = Color3.fromRGB(110, 200, 110),
	Rare = Color3.fromRGB(200, 90, 220),
}

UI.RarityColors = RARITY_COLORS

local function makePanel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = COLORS.panel
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.panelBorder
	stroke.Thickness = 2
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

local function makeLabel(parent: Instance, name: string, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.TextColor3 = COLORS.text
	label.TextSize = textSize
	label.Parent = parent
	return label
end

export type HUDRefs = {
	gui: ScreenGui,
	timerLabel: TextLabel,
	playersLabel: TextLabel,
	phaseBanner: Frame,
	phaseLabel: TextLabel,
	phaseTimeLabel: TextLabel,
	hpBarFill: Frame,
	hpLabel: TextLabel,
	statusLabel: TextLabel,
	handFrame: Frame,
	handCountLabel: TextLabel,
	feedFrame: ScrollingFrame,
	draftFrame: Frame,
	draftGrid: Frame,
	draftTitle: TextLabel,
	reactionFrame: Frame,
	reactionLabel: TextLabel,
	scoreboardFrame: Frame,
	scoreboardList: Frame,
	scoreboardTitle: TextLabel,
	lobbyLabel: TextLabel,
}

function UI.build(): HUDRefs
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "WastelandHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui

	----------------------------------------------------------------
	-- Top bar: timer + players alive
	----------------------------------------------------------------
	local topBar = makePanel(gui, "TopBar")
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.Position = UDim2.new(0.5, 0, 0, 8)
	topBar.Size = UDim2.new(0, 380, 0, 44)

	local timerLabel = makeLabel(topBar, "Timer", 30)
	timerLabel.Size = UDim2.new(0.5, 0, 1, 0)
	timerLabel.Text = "⏱ 6:00"

	local playersLabel = makeLabel(topBar, "Players", 30)
	playersLabel.Position = UDim2.new(0.5, 0, 0, 0)
	playersLabel.Size = UDim2.new(0.5, 0, 1, 0)
	playersLabel.Text = "👥 0/16"

	----------------------------------------------------------------
	-- Turn/phase banner (above the hand)
	----------------------------------------------------------------
	local phaseBanner = makePanel(gui, "PhaseBanner")
	phaseBanner.AnchorPoint = Vector2.new(0.5, 1)
	phaseBanner.Position = UDim2.new(0.5, 0, 1, -170)
	phaseBanner.Size = UDim2.new(0, 420, 0, 40)
	phaseBanner.Visible = false

	local phaseLabel = makeLabel(phaseBanner, "Phase", 26)
	phaseLabel.Size = UDim2.new(0.75, 0, 1, 0)
	phaseLabel.Text = "WAITING..."

	local phaseTimeLabel = makeLabel(phaseBanner, "PhaseTime", 26)
	phaseTimeLabel.Position = UDim2.new(0.75, 0, 0, 0)
	phaseTimeLabel.Size = UDim2.new(0.25, 0, 1, 0)
	phaseTimeLabel.TextColor3 = COLORS.accent
	phaseTimeLabel.Text = ""

	----------------------------------------------------------------
	-- Bottom-left: HP bar + status icons
	----------------------------------------------------------------
	local statsPanel = makePanel(gui, "StatsPanel")
	statsPanel.AnchorPoint = Vector2.new(0, 1)
	statsPanel.Position = UDim2.new(0, 10, 1, -10)
	statsPanel.Size = UDim2.new(0, 260, 0, 74)

	local hpBarBack = Instance.new("Frame")
	hpBarBack.Name = "HPBack"
	hpBarBack.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	hpBarBack.BorderSizePixel = 0
	hpBarBack.Position = UDim2.new(0, 10, 0, 10)
	hpBarBack.Size = UDim2.new(1, -20, 0, 22)
	hpBarBack.Parent = statsPanel
	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 6)
	hpCorner.Parent = hpBarBack

	local hpBarFill = Instance.new("Frame")
	hpBarFill.Name = "HPFill"
	hpBarFill.BackgroundColor3 = COLORS.hp
	hpBarFill.BorderSizePixel = 0
	hpBarFill.Size = UDim2.new(1, 0, 1, 0)
	hpBarFill.Parent = hpBarBack
	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0, 6)
	hpFillCorner.Parent = hpBarFill

	local hpLabel = makeLabel(hpBarBack, "HPText", 18)
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.ZIndex = 2
	hpLabel.Text = "❤ 100/100"

	local statusLabel = makeLabel(statsPanel, "Statuses", 20)
	statusLabel.Position = UDim2.new(0, 10, 0, 36)
	statusLabel.Size = UDim2.new(1, -20, 0, 30)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = ""

	----------------------------------------------------------------
	-- Bottom-center: card hand
	----------------------------------------------------------------
	local handFrame = Instance.new("Frame")
	handFrame.Name = "Hand"
	handFrame.AnchorPoint = Vector2.new(0.5, 1)
	handFrame.Position = UDim2.new(0.5, 0, 1, -10)
	handFrame.Size = UDim2.new(0, 900, 0, 150)
	handFrame.BackgroundTransparency = 1
	handFrame.Parent = gui

	local handLayout = Instance.new("UIListLayout")
	handLayout.FillDirection = Enum.FillDirection.Horizontal
	handLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	handLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	handLayout.Padding = UDim.new(0, 6)
	handLayout.Parent = handFrame

	local handCountLabel = makeLabel(gui, "HandCount", 22)
	handCountLabel.AnchorPoint = Vector2.new(0.5, 1)
	handCountLabel.Position = UDim2.new(0.5, 0, 1, -162)
	handCountLabel.Size = UDim2.new(0, 200, 0, 24)
	handCountLabel.Text = ""

	----------------------------------------------------------------
	-- Right edge: action feed
	----------------------------------------------------------------
	local feedFrame = Instance.new("ScrollingFrame")
	feedFrame.Name = "ActionFeed"
	feedFrame.AnchorPoint = Vector2.new(1, 0)
	feedFrame.Position = UDim2.new(1, -10, 0, 70)
	feedFrame.Size = UDim2.new(0, 300, 0, 260)
	feedFrame.BackgroundColor3 = COLORS.panel
	feedFrame.BackgroundTransparency = 0.45
	feedFrame.BorderSizePixel = 0
	feedFrame.ScrollBarThickness = 4
	feedFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	feedFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	feedFrame.Parent = gui

	local feedLayout = Instance.new("UIListLayout")
	feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	feedLayout.Padding = UDim.new(0, 2)
	feedLayout.Parent = feedFrame

	----------------------------------------------------------------
	-- Draft overlay
	----------------------------------------------------------------
	local draftFrame = makePanel(gui, "Draft")
	draftFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	draftFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	draftFrame.Size = UDim2.new(0, 760, 0, 480)
	draftFrame.Visible = false
	draftFrame.ZIndex = 5

	local draftTitle = makeLabel(draftFrame, "Title", 30)
	draftTitle.Size = UDim2.new(1, 0, 0, 46)
	draftTitle.Text = "🎴 DRAFT YOUR ARSENAL — PICK 1"
	draftTitle.ZIndex = 5

	local draftGrid = Instance.new("Frame")
	draftGrid.Name = "Grid"
	draftGrid.Position = UDim2.new(0, 10, 0, 50)
	draftGrid.Size = UDim2.new(1, -20, 1, -60)
	draftGrid.BackgroundTransparency = 1
	draftGrid.ZIndex = 5
	draftGrid.Parent = draftFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 140, 0, 128)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = draftGrid

	----------------------------------------------------------------
	-- Reaction prompt (1-second counter window)
	----------------------------------------------------------------
	local reactionFrame = makePanel(gui, "Reaction")
	reactionFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	reactionFrame.Position = UDim2.new(0.5, 0, 0.35, 0)
	reactionFrame.Size = UDim2.new(0, 420, 0, 70)
	reactionFrame.Visible = false
	reactionFrame.ZIndex = 6
	local reactionStroke = reactionFrame:FindFirstChildOfClass("UIStroke")
	if reactionStroke then
		reactionStroke.Color = COLORS.blood
		reactionStroke.Thickness = 3
	end

	local reactionLabel = makeLabel(reactionFrame, "Text", 24)
	reactionLabel.Size = UDim2.new(1, 0, 1, 0)
	reactionLabel.TextColor3 = COLORS.accent
	reactionLabel.Text = "⚠ INCOMING ATTACK — play a counter card!"
	reactionLabel.ZIndex = 6

	----------------------------------------------------------------
	-- Scoreboard overlay
	----------------------------------------------------------------
	local scoreboardFrame = makePanel(gui, "Scoreboard")
	scoreboardFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	scoreboardFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	scoreboardFrame.Size = UDim2.new(0, 520, 0, 440)
	scoreboardFrame.Visible = false
	scoreboardFrame.ZIndex = 7

	local scoreboardTitle = makeLabel(scoreboardFrame, "Title", 32)
	scoreboardTitle.Size = UDim2.new(1, 0, 0, 56)
	scoreboardTitle.TextColor3 = COLORS.accent
	scoreboardTitle.Text = "🏆 MATCH OVER"
	scoreboardTitle.ZIndex = 7

	local scoreboardList = Instance.new("Frame")
	scoreboardList.Name = "List"
	scoreboardList.Position = UDim2.new(0, 16, 0, 60)
	scoreboardList.Size = UDim2.new(1, -32, 1, -76)
	scoreboardList.BackgroundTransparency = 1
	scoreboardList.ZIndex = 7
	scoreboardList.Parent = scoreboardFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scoreboardList

	----------------------------------------------------------------
	-- Lobby status label
	----------------------------------------------------------------
	local lobbyLabel = makeLabel(gui, "LobbyStatus", 28)
	lobbyLabel.AnchorPoint = Vector2.new(0.5, 0)
	lobbyLabel.Position = UDim2.new(0.5, 0, 0, 60)
	lobbyLabel.Size = UDim2.new(0, 600, 0, 40)
	lobbyLabel.TextColor3 = COLORS.accent
	lobbyLabel.Text = "🎴 MAD MAX: WASTELAND BRAWL — waiting for warriors..."

	return {
		gui = gui,
		timerLabel = timerLabel,
		playersLabel = playersLabel,
		phaseBanner = phaseBanner,
		phaseLabel = phaseLabel,
		phaseTimeLabel = phaseTimeLabel,
		hpBarFill = hpBarFill,
		hpLabel = hpLabel,
		statusLabel = statusLabel,
		handFrame = handFrame,
		handCountLabel = handCountLabel,
		feedFrame = feedFrame,
		draftFrame = draftFrame,
		draftGrid = draftGrid,
		draftTitle = draftTitle,
		reactionFrame = reactionFrame,
		reactionLabel = reactionLabel,
		scoreboardFrame = scoreboardFrame,
		scoreboardList = scoreboardList,
		scoreboardTitle = scoreboardTitle,
		lobbyLabel = lobbyLabel,
	}
end

-- A clickable card frame used in both the hand and the draft grid.
function UI.makeCardButton(cardName: string, rarity: string, description: string, damageText: string?): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 96, 0, 132)
	button.BackgroundColor3 = COLORS.panel
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = RARITY_COLORS[rarity] or COLORS.panelBorder
	stroke.Thickness = 2.5
	stroke.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 4, 0, 4)
	nameLabel.Size = UDim2.new(1, -8, 0, 40)
	nameLabel.Font = Enum.Font.Bangers
	nameLabel.TextSize = 17
	nameLabel.TextWrapped = true
	nameLabel.TextColor3 = COLORS.text
	nameLabel.Text = cardName
	nameLabel.Parent = button

	local descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 4, 0, 46)
	descLabel.Size = UDim2.new(1, -8, 1, -70)
	descLabel.Font = Enum.Font.SourceSans
	descLabel.TextSize = 12
	descLabel.TextWrapped = true
	descLabel.TextColor3 = Color3.fromRGB(200, 190, 175)
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.Text = description
	descLabel.Parent = button

	local footer = Instance.new("TextLabel")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 4, 1, -4)
	footer.Size = UDim2.new(1, -8, 0, 18)
	footer.Font = Enum.Font.SourceSansBold
	footer.TextSize = 13
	footer.TextColor3 = RARITY_COLORS[rarity] or COLORS.text
	footer.Text = damageText or rarity
	footer.Parent = button

	return button
end

return UI
