--!strict
-- Client controller: renders server state into the HUD, handles card clicks,
-- draft picks, the 1-second reaction window, targeting, spectator mode.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CardDatabase = require(Shared.CardDatabase)
local Remotes = require(Shared.Remotes)

local UI = require(script.UI)
local CameraController = require(script.CameraController)

local localPlayer = Players.LocalPlayer
local hud = UI.build()
CameraController.enable()

----------------------------------------------------------------
-- Local state
----------------------------------------------------------------
local currentHand: { string } = {}
local disabledCards: { [number]: boolean } = {}
local myTurnActive = false
local reactionActive = false
local latestStats: { [string]: any } = {}
local isDead = false
local targetingHandIndex: number? = nil -- waiting for a click on a player (global cards)

local STATUS_ICONS: { [string]: string } = {
	Burn = "🔥", Bleeding = "🩸", Poisoned = "☠", Slowed = "💨",
	Trapped = "🪤", Blinded = "😵", TimeWarp = "🌀",
	AdrenalineRush = "🔥", WarPaint = "🎨", BattleCry = "📣",
	ArmorPlating = "🛡", ShieldWall = "🛡", IronFortress = "🏰",
	IronWill = "🛡✨", Overcharge = "⚡", NitroBoost = "🏎",
	ScavengersLuck = "🍀", PhoenixFlame = "🕊", TimeWarpVortex = "🌀",
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%d:%02d", minutes, secs)
end

local function addFeedLine(message: string)
	local line = Instance.new("TextLabel")
	line.Size = UDim2.new(1, -8, 0, 0)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.SourceSansSemibold
	line.TextSize = 15
	line.TextWrapped = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = Color3.fromRGB(230, 220, 200)
	line.Text = message
	line.LayoutOrder = os.clock() * 100
	line.Parent = hud.feedFrame
	-- Keep the feed short
	local children = hud.feedFrame:GetChildren()
	local labels = {}
	for _, child in children do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	if #labels > 25 then
		table.sort(labels, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		labels[1]:Destroy()
	end
	hud.feedFrame.CanvasPosition = Vector2.new(0, 1e6)
end

-- Which alive enemy is nearest to me (mirrors server logic, for UI hints)?
local function getNearestEnemyUserId(): number?
	local myStats = latestStats[tostring(localPlayer.UserId)]
	if not myStats then
		return nil
	end
	local best: string? = nil
	local bestDistance = math.huge
	for userIdStr, stats in latestStats do
		if userIdStr ~= tostring(localPlayer.UserId) and stats.alive then
			local distance = math.abs(stats.tile - myStats.tile)
			if distance < bestDistance then
				best, bestDistance = userIdStr, distance
			end
		end
	end
	return best and tonumber(best) or nil
end

----------------------------------------------------------------
-- Hand rendering
----------------------------------------------------------------

local function playCardFromHand(handIndex: number)
	local cardId = currentHand[handIndex]
	local card = cardId and CardDatabase.get(cardId)
	if not card then
		return
	end

	-- During a reaction window, clicking a reaction card sends a reaction
	if reactionActive and card.isReaction then
		Remotes.get("RequestReaction"):FireServer(handIndex)
		return
	end
	if not myTurnActive then
		addFeedLine("⏳ Wait for your Action Phase!")
		return
	end

	if card.effect.type == "skipTurn" then
		-- Global targeting: next click on a player picks the target
		targetingHandIndex = handIndex
		addFeedLine("🎯 Click any player to target them with " .. card.name)
		return
	end

	local targetUserId = nil
	if card.effect.type == "attack" or card.effect.type == "duel" then
		targetUserId = getNearestEnemyUserId()
	end
	Remotes.get("RequestPlayCard"):FireServer(handIndex, targetUserId, nil)
end

local function renderHand()
	for _, child in hud.handFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for index, cardId in currentHand do
		local card = CardDatabase.get(cardId)
		if not card then
			continue
		end
		local damageText = card.effect.damage and `⚔ {card.effect.damage} dmg` or card.rarity
		local button = UI.makeCardButton(card.name, card.rarity, card.description, damageText)
		button.LayoutOrder = index
		if disabledCards[index] then
			button.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
			button.AutoButtonColor = false
		else
			local capturedIndex = index
			button.Activated:Connect(function()
				playCardFromHand(capturedIndex)
			end)
		end
		button.Parent = hud.handFrame
	end
	hud.handCountLabel.Text = `🃏 YOUR HAND ({#currentHand}/10)`
end

----------------------------------------------------------------
-- Global-target click handling (Time Warp Vortex etc.)
----------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not targetingHandIndex then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(input.Position.X, input.Position.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500)
	if result and result.Instance then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local targetPlayer = model and Players:GetPlayerFromCharacter(model)
		if targetPlayer and targetPlayer ~= localPlayer then
			Remotes.get("RequestPlayCard"):FireServer(targetingHandIndex, targetPlayer.UserId, nil)
			targetingHandIndex = nil
		end
	end
end)

----------------------------------------------------------------
-- Overhead billboards: card count + HP above every player
----------------------------------------------------------------
local overheads: { [number]: BillboardGui } = {}

local function updateOverheads()
	local nearestUserId = getNearestEnemyUserId()
	for userIdStr, stats in latestStats do
		local userId = tonumber(userIdStr) :: number
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local head = character and character:FindFirstChild("Head")
		if not head then
			continue
		end

		local billboard = overheads[userId]
		if not billboard or billboard.Parent ~= head then
			if billboard then
				billboard:Destroy()
			end
			billboard = Instance.new("BillboardGui")
			billboard.Name = "WastelandOverhead"
			billboard.Size = UDim2.fromOffset(140, 44)
			billboard.StudsOffset = Vector3.new(0, 2.4, 0)
			billboard.AlwaysOnTop = true
			local label = Instance.new("TextLabel")
			label.Name = "Info"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.SourceSansBold
			label.TextSize = 15
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.4
			label.Parent = billboard
			billboard.Parent = head
			overheads[userId] = billboard
		end

		local label = billboard:FindFirstChild("Info") :: TextLabel
		local statusIcons = ""
		for _, statusId in (stats.statuses or {}) do
			statusIcons ..= (STATUS_ICONS[statusId] or "")
		end
		local targetMark = (userId == nearestUserId and userId ~= localPlayer.UserId) and "🎯 " or ""
		if stats.alive then
			label.Text = `{targetMark}{stats.name}\n❤{stats.hp} 🃏{stats.cards} {statusIcons}`
		else
			label.Text = `👻 {stats.name}`
		end
	end
end

----------------------------------------------------------------
-- Remote event handlers
----------------------------------------------------------------

Remotes.get("GameStateChanged").OnClientEvent:Connect(function(state: string)
	hud.lobbyLabel.Visible = state == "Lobby"
	hud.draftFrame.Visible = state == "Draft"
	hud.phaseBanner.Visible = state == "Playing"
	if state == "Lobby" then
		isDead = false
		hud.scoreboardFrame.Visible = false
		currentHand = {}
		renderHand()
		CameraController.enable()
	elseif state == "Playing" then
		hud.draftFrame.Visible = false
	end
end)

Remotes.get("MatchTimerUpdate").OnClientEvent:Connect(function(timeLeft: number, aliveCount: number)
	hud.timerLabel.Text = `⏱ {formatTime(timeLeft)}`
	hud.playersLabel.Text = `👥 {aliveCount}/16`
	if hud.lobbyLabel.Visible then
		hud.lobbyLabel.Text = `🎴 MATCH STARTING IN {math.floor(timeLeft)}...`
	end
end)

Remotes.get("DraftPoolUpdate").OnClientEvent:Connect(function(pool: { string }, pickNumber: number, timeLeft: number)
	hud.draftFrame.Visible = true
	hud.draftTitle.Text = `🎴 DRAFT PICK {pickNumber}/3 — choose 1 card ({timeLeft}s)`
	for _, child in hud.draftGrid:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local picked = false
	for _, cardId in pool do
		local card = CardDatabase.get(cardId)
		if not card then
			continue
		end
		local damageText = card.effect.damage and `⚔ {card.effect.damage} dmg` or card.rarity
		local button = UI.makeCardButton(card.name, card.rarity, card.description, damageText)
		button.Activated:Connect(function()
			if picked then
				return
			end
			picked = true
			Remotes.get("RequestDraftPick"):FireServer(cardId)
			hud.draftTitle.Text = `✅ Picked {card.name} — waiting for other players...`
			for _, other in hud.draftGrid:GetChildren() do
				if other:IsA("TextButton") and other ~= button then
					other.BackgroundTransparency = 0.6
				end
			end
		end)
		button.Parent = hud.draftGrid
	end
end)

Remotes.get("HandUpdate").OnClientEvent:Connect(function(hand: { string }, disabled: { [number]: boolean }?)
	currentHand = hand
	disabledCards = disabled or {}
	renderHand()
end)

Remotes.get("PlayerStatsUpdate").OnClientEvent:Connect(function(snapshot)
	latestStats = snapshot
	local myStats = snapshot[tostring(localPlayer.UserId)]
	if myStats then
		local fraction = math.clamp(myStats.hp / myStats.maxHp, 0, 1)
		hud.hpBarFill.Size = UDim2.new(fraction, 0, 1, 0)
		hud.hpBarFill.BackgroundColor3 = fraction > 0.3
			and Color3.fromRGB(90, 180, 80)
			or Color3.fromRGB(200, 60, 40)
		hud.hpLabel.Text = `❤ {myStats.hp}/{myStats.maxHp}`
		local icons = ""
		for _, statusId in (myStats.statuses or {}) do
			icons ..= `{STATUS_ICONS[statusId] or "•"} {statusId}  `
		end
		hud.statusLabel.Text = icons

		-- Blinded: obscure the screen briefly
		local blinded = table.find(myStats.statuses or {}, "Blinded") ~= nil
		local existingBlind = hud.gui:FindFirstChild("BlindOverlay")
		if blinded and not existingBlind then
			local overlay = Instance.new("Frame")
			overlay.Name = "BlindOverlay"
			overlay.Size = UDim2.fromScale(1, 1)
			overlay.BackgroundColor3 = Color3.new(0, 0, 0)
			overlay.BackgroundTransparency = 0.25
			overlay.ZIndex = 10
			overlay.Parent = hud.gui
		elseif not blinded and existingBlind then
			existingBlind:Destroy()
		end
	end
	updateOverheads()
end)

Remotes.get("TurnPhaseUpdate").OnClientEvent:Connect(function(groupIndex: number, phase: string, timeLeft: number, myTurn: boolean)
	myTurnActive = myTurn and phase == "Action"
	hud.phaseBanner.Visible = true
	local phaseNames: { [string]: string } = {
		Roll = "🎲 ROLL PHASE",
		Movement = "🏃 MOVEMENT",
		TileEffect = "⚡ TILE EFFECTS",
		Action = "🃏 ACTION PHASE — PLAY CARDS!",
		Resolution = "⚔ RESOLVING...",
	}
	if myTurn then
		hud.phaseLabel.Text = `YOUR TURN! {phaseNames[phase] or phase}`
		hud.phaseLabel.TextColor3 = Color3.fromRGB(240, 200, 60)
	else
		hud.phaseLabel.Text = `Group {groupIndex}: {phaseNames[phase] or phase}`
		hud.phaseLabel.TextColor3 = Color3.fromRGB(180, 170, 150)
	end

	-- Countdown for timed phases
	if timeLeft > 0 then
		task.spawn(function()
			local deadline = os.clock() + timeLeft
			while os.clock() < deadline do
				local remaining = deadline - os.clock()
				hud.phaseTimeLabel.Text = `⏱ {math.ceil(remaining)}s`
				task.wait(0.2)
			end
			hud.phaseTimeLabel.Text = ""
		end)
	end
end)

Remotes.get("DiceRolled").OnClientEvent:Connect(function(userId: number, roll: number)
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.Name or "?"
	if userId == localPlayer.UserId then
		addFeedLine(`🎲 You rolled a {roll}!`)
	else
		addFeedLine(`🎲 {name} rolled {roll}`)
	end
end)

Remotes.get("ReactionWindow").OnClientEvent:Connect(function(attackerUserId: number, cardId: string, window: number)
	local attacker = Players:GetPlayerByUserId(attackerUserId)
	local card = CardDatabase.get(cardId)
	reactionActive = true
	hud.reactionFrame.Visible = true
	hud.reactionLabel.Text = `⚠ {attacker and attacker.Name or "?"} plays {card and card.name or cardId} — COUNTER NOW!`
	task.delay(window, function()
		reactionActive = false
		hud.reactionFrame.Visible = false
	end)
end)

Remotes.get("ActionFeed").OnClientEvent:Connect(addFeedLine)

Remotes.get("CardPlayed").OnClientEvent:Connect(function(userId: number, cardId: string)
	local player = Players:GetPlayerByUserId(userId)
	local card = CardDatabase.get(cardId)
	if player and card and userId ~= localPlayer.UserId then
		addFeedLine(`🃏 {player.Name} played {card.name}`)
	end
end)

Remotes.get("TileEffectTriggered").OnClientEvent:Connect(function(userId: number, tileIndex: number, effectType: string, value: number?)
	if userId == localPlayer.UserId then
		if effectType == "Heal" then
			addFeedLine(`💚 Tile {tileIndex}: healed {value} HP`)
		elseif effectType == "Damage" then
			addFeedLine(`💥 Tile {tileIndex}: took {value} damage`)
		elseif effectType == "BonusCard" then
			addFeedLine(`🎁 Tile {tileIndex}: drew a bonus card!`)
		end
	end
end)

Remotes.get("PlayerDied").OnClientEvent:Connect(function(victimUserId: number)
	if victimUserId == localPlayer.UserId then
		isDead = true
		addFeedLine("👻 You died! Spectating — click a player to follow them.")
		-- Spectate the first alive player
		for userIdStr, stats in latestStats do
			if stats.alive and userIdStr ~= tostring(localPlayer.UserId) then
				local alivePlayer = Players:GetPlayerByUserId(tonumber(userIdStr) :: number)
				if alivePlayer and alivePlayer.Character then
					CameraController.followCharacter(alivePlayer.Character)
					break
				end
			end
		end
	end
end)

Remotes.get("MatchEnded").OnClientEvent:Connect(function(results)
	hud.scoreboardFrame.Visible = true
	hud.phaseBanner.Visible = false
	hud.scoreboardTitle.Text = `🏆 {results.winnerName} WINS — {results.reason}`
	for _, child in hud.scoreboardList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for rank, row in (results.scoreboard :: { any }) do
		local line = Instance.new("TextLabel")
		line.Size = UDim2.new(1, 0, 0, 26)
		line.BackgroundTransparency = 1
		line.Font = Enum.Font.SourceSansBold
		line.TextSize = 18
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextColor3 = rank == 1 and Color3.fromRGB(240, 200, 60) or Color3.fromRGB(220, 210, 190)
		local crown = rank == 1 and "👑 " or `{rank}. `
		line.Text = `{crown}{row.name} — {row.kills} kills, {row.damageDealt} dmg, {row.cardsPlayed} cards, +{row.scrap} Scrap`
		line.LayoutOrder = rank
		line.Parent = hud.scoreboardList
		if rank >= 12 then
			break
		end
	end
end)

print("[MadMax] Client controller ready.")
