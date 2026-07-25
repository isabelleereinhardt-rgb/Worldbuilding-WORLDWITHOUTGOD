--!strict
-- Server bootstrap for Mad Max: Wasteland Brawl.
-- Creates remotes, builds the board, wires the managers together
-- (dependency injection avoids circular requires), and routes client requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local PlayerDataManager = require(script.PlayerDataManager)
local BoardManager = require(script.BoardManager)
local CombatManager = require(script.CombatManager)
local CardManager = require(script.CardManager)
local TurnManager = require(script.TurnManager)
local SpectatorManager = require(script.SpectatorManager)
local GameManager = require(script.GameManager)

Remotes.init()
BoardManager.buildBoard()
BoardManager.resetTraps()

----------------------------------------------------------------
-- Wire managers together
----------------------------------------------------------------
BoardManager.inject({
	applyDamage = CombatManager.applyDamage,
	executeTrapCard = CardManager.executeTrapCard,
	drawCards = CardManager.drawCards,
})

CombatManager.inject({
	transferCardsOnKill = CardManager.transferCardsOnKill,
	onPlayerDied = GameManager.onPlayerDied,
})

CardManager.inject({
	skipPlayerTurn = function(state)
		state.skipNextTurn = true
	end,
})

TurnManager.inject({
	playCard = CardManager.playCard,
	checkWinConditions = GameManager.checkWinConditions,
})

SpectatorManager.inject({
	giveCards = CardManager.giveCards,
})

----------------------------------------------------------------
-- Client request routing (server validates everything)
----------------------------------------------------------------

Remotes.get("RequestDraftPick").OnServerEvent:Connect(function(player, cardId)
	if typeof(cardId) ~= "string" then
		return
	end
	local state = PlayerDataManager.get(player.UserId)
	if state and GameManager.getState() == "Draft" then
		CardManager.registerDraftPick(state, cardId)
	end
end)

Remotes.get("RequestPlayCard").OnServerEvent:Connect(function(player, handIndex, targetUserId, tileIndex)
	if typeof(handIndex) ~= "number" then
		return
	end
	if targetUserId ~= nil and typeof(targetUserId) ~= "number" then
		return
	end
	if tileIndex ~= nil and typeof(tileIndex) ~= "number" then
		return
	end
	local state = PlayerDataManager.get(player.UserId)
	if not state or not state.alive then
		return
	end
	-- Cards may only be played during your group's Action Phase
	if not TurnManager.isActionPhaseFor(state) then
		return
	end
	TurnManager.queueAction(state, handIndex, targetUserId, tileIndex)
end)

Remotes.get("RequestReaction").OnServerEvent:Connect(function(player, handIndex)
	if typeof(handIndex) ~= "number" then
		return
	end
	local state = PlayerDataManager.get(player.UserId)
	if not state or not state.alive then
		return
	end
	local cardId = state.hand[handIndex]
	if not cardId then
		return
	end
	if CombatManager.registerReaction(state, cardId) then
		-- Reaction card is consumed immediately
		table.remove(state.hand, handIndex)
		state.cardsPlayed += 1
		PlayerDataManager.sendHand(state)
		PlayerDataManager.broadcastStats()
	end
end)

Remotes.get("RequestChaosVote").OnServerEvent:Connect(function(player, eventId)
	if typeof(eventId) ~= "string" then
		return
	end
	local state = PlayerDataManager.get(player.UserId)
	if state then
		SpectatorManager.registerChaosVote(state, eventId)
	end
end)

Remotes.get("RequestCheer").OnServerEvent:Connect(function(player, targetUserId)
	if typeof(targetUserId) ~= "number" then
		return
	end
	local state = PlayerDataManager.get(player.UserId)
	if state then
		SpectatorManager.cheer(state, targetUserId)
	end
end)

Remotes.get("RequestMVPVote").OnServerEvent:Connect(function(player, targetUserId)
	if typeof(targetUserId) ~= "number" then
		return
	end
	local state = PlayerDataManager.get(player.UserId)
	if state then
		SpectatorManager.registerMVPVote(state, targetUserId)
	end
end)

Remotes.get("RequestCosmeticChaos").OnServerEvent:Connect(function(player)
	local state = PlayerDataManager.get(player.UserId)
	if state then
		SpectatorManager.triggerCosmetic(state)
	end
end)

----------------------------------------------------------------
-- Kick off the lobby loop
----------------------------------------------------------------
GameManager.tryStartCountdown()

print("[MadMax] Wasteland Brawl server initialized — board built, systems wired.")
