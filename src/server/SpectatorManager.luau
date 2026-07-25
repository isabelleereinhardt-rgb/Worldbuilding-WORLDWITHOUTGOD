--!strict
-- Everything a dead player can do: Chaos Mode voting every 60s, cheering
-- alive players for Scrap, an MVP popularity vote, and cosmetic-only chaos
-- triggers for fun. Also owns the timed global modifiers Chaos Mode applies
-- (trap damage, healing, movement) so other managers can read them without
-- depending on this module's voting loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ChaosEvents = require(Shared.ChaosEvents)
local CardDatabase = require(Shared.CardDatabase)
local Remotes = require(Shared.Remotes)
local PlayerDataManager = require(script.Parent.PlayerDataManager)

type PlayerState = PlayerDataManager.PlayerState

local SpectatorManager = {}

-- Injected: CardManager.giveCards to hand out one-shot event rewards
local deps: { giveCards: (PlayerState, { string }) -> () }? = nil

function SpectatorManager.inject(d)
	deps = d
end

----------------------------------------------------------------
-- Active modifiers (read by CombatManager/CardManager/BoardManager/TurnManager)
----------------------------------------------------------------

local modifiers: { [string]: { multiplier: number?, bonus: number?, expiresAt: number, label: string } } = {}

local function setModifier(key: string, data: { multiplier: number?, bonus: number?, expiresAt: number, label: string })
	modifiers[key] = data
end

local function getModifier(key: string): { multiplier: number?, bonus: number?, expiresAt: number, label: string }?
	local mod = modifiers[key]
	if mod and os.clock() >= mod.expiresAt then
		modifiers[key] = nil
		return nil
	end
	return mod
end

function SpectatorManager.getTrapDamageMultiplier(): number
	local mod = getModifier("trapDamage")
	return mod and mod.multiplier or 1
end

function SpectatorManager.getHealMultiplier(): number
	local mod = getModifier("heal")
	return mod and mod.multiplier or 1
end

function SpectatorManager.getMovementBonus(): number
	local mod = getModifier("movement")
	return mod and mod.bonus or 0
end

function SpectatorManager.broadcastActiveModifiers()
	local now = os.clock()
	local list = {}
	for _, mod in modifiers do
		if now < mod.expiresAt then
			table.insert(list, { label = mod.label, timeLeft = math.ceil(mod.expiresAt - now) })
		end
	end
	Remotes.get("ChaosModifiersUpdate"):FireAllClients(list)
end

----------------------------------------------------------------
-- Applying a resolved Chaos Mode event
----------------------------------------------------------------

local function applyEvent(event: ChaosEvents.ChaosEvent)
	assert(deps, "SpectatorManager.inject not called")
	local now = os.clock()

	if event.kind == "modifier" then
		local duration = event.duration :: number
		if event.trapDamageMultiplier then
			setModifier("trapDamage", { multiplier = event.trapDamageMultiplier, expiresAt = now + duration, label = event.label })
		end
		if event.healMultiplier then
			setModifier("heal", { multiplier = event.healMultiplier, expiresAt = now + duration, label = event.label })
		end
		if event.movementBonus then
			setModifier("movement", { bonus = event.movementBonus, expiresAt = now + duration, label = event.label })
		end
	elseif event.id == "ExtraCard" then
		local commons = CardDatabase.getByRarity("Common")
		for _, state in PlayerDataManager.getAlive() do
			deps.giveCards(state, { commons[math.random(#commons)] })
		end
	elseif event.id == "RandomRareCard" then
		local alive = PlayerDataManager.getAlive()
		if #alive > 0 then
			local lucky = alive[math.random(#alive)]
			local rares = CardDatabase.getByRarity("Rare")
			deps.giveCards(lucky, { rares[math.random(#rares)] })
			Remotes.get("ActionFeed"):FireAllClients(`🍀 {lucky.player.Name} was blessed with a Rare card!`)
		end
	end

	Remotes.get("ActionFeed"):FireAllClients(`🗳 CHAOS MODE: {event.label}`)
	SpectatorManager.broadcastActiveModifiers()
end

----------------------------------------------------------------
-- Chaos Mode voting loop (spectators only)
----------------------------------------------------------------

local currentVotes: { [number]: string } = {} -- userId -> eventId
local votingOpen = false
local running = false

function SpectatorManager.registerChaosVote(state: PlayerState, eventId: string)
	if votingOpen and not state.alive and ChaosEvents.get(eventId) then
		currentVotes[state.userId] = eventId
	end
end

local function spectators(): { PlayerState }
	local out = {}
	for _, state in PlayerDataManager.getAll() do
		if not state.alive then
			table.insert(out, state)
		end
	end
	return out
end

local function runVote()
	local allIds = ChaosEvents.getAllIds()
	-- Shuffle and take N options
	for i = #allIds, 2, -1 do
		local j = math.random(i)
		allIds[i], allIds[j] = allIds[j], allIds[i]
	end
	local options = {}
	for i = 1, math.min(Config.CHAOS_OPTIONS_SHOWN, #allIds) do
		local event = ChaosEvents.get(allIds[i])
		if event then
			table.insert(options, { id = event.id, label = event.label })
		end
	end
	if #options == 0 then
		return
	end

	table.clear(currentVotes)
	votingOpen = true
	Remotes.get("ChaosVoteOptions"):FireAllClients(options, Config.CHAOS_VOTE_DURATION)

	local deadline = os.clock() + Config.CHAOS_VOTE_DURATION
	while os.clock() < deadline do
		task.wait(0.25)
	end
	votingOpen = false

	-- Tally
	local counts: { [string]: number } = {}
	for _, eventId in currentVotes do
		counts[eventId] = (counts[eventId] or 0) + 1
	end
	local winnerId: string? = nil
	local winnerCount = -1
	for _, option in options do
		local count = counts[option.id] or 0
		if count > winnerCount then
			winnerId, winnerCount = option.id, count
		end
	end
	if not winnerId then
		return
	end
	local winningEvent = ChaosEvents.get(winnerId)
	if not winningEvent then
		return
	end

	Remotes.get("ChaosVoteResult"):FireAllClients(winnerId, winningEvent.label, counts)
	applyEvent(winningEvent)
end

-- Runs for the whole "Playing" phase; call SpectatorManager.stop() at match end.
function SpectatorManager.start()
	running = true
	table.clear(modifiers)
	task.spawn(function()
		while running do
			local waited = 0
			while running and waited < Config.CHAOS_VOTE_INTERVAL do
				task.wait(1)
				waited += 1
			end
			if running then
				runVote()
			end
		end
	end)
end

function SpectatorManager.stop()
	running = false
	votingOpen = false
	table.clear(modifiers)
	table.clear(currentVotes)
end

----------------------------------------------------------------
-- Cheer system
----------------------------------------------------------------

local lastCheerAt: { [number]: number } = {}

function SpectatorManager.cheer(spectator: PlayerState, targetUserId: number)
	if spectator.alive then
		return -- only spectators cheer; alive players are busy fighting
	end
	local now = os.clock()
	if now - (lastCheerAt[spectator.userId] or 0) < Config.CHEER_COOLDOWN then
		return
	end
	local target = PlayerDataManager.get(targetUserId)
	if not target or not target.alive then
		return
	end
	lastCheerAt[spectator.userId] = now
	spectator.scrap += Config.SCRAP_CHEER_BONUS
	target.scrap += Config.SCRAP_CHEER_TARGET_BONUS
	Remotes.get("ActionFeed"):FireAllClients(`📣 {spectator.player.Name} cheered for {target.player.Name}!`)
	PlayerDataManager.broadcastStats()
end

----------------------------------------------------------------
-- MVP popularity vote (flavor only — doesn't affect the real MVP stat)
----------------------------------------------------------------

local mvpVotes: { [number]: number } = {} -- voterUserId -> targetUserId

function SpectatorManager.registerMVPVote(voter: PlayerState, targetUserId: number)
	local target = PlayerDataManager.get(targetUserId)
	if not target then
		return
	end
	mvpVotes[voter.userId] = targetUserId
	local counts: { [number]: number } = {}
	for _, votedFor in mvpVotes do
		counts[votedFor] = (counts[votedFor] or 0) + 1
	end
	Remotes.get("MVPVoteUpdate"):FireAllClients(counts)
end

function SpectatorManager.getCrowdFavoriteName(): string?
	local counts: { [number]: number } = {}
	for _, votedFor in mvpVotes do
		counts[votedFor] = (counts[votedFor] or 0) + 1
	end
	local bestUserId: number? = nil
	local bestCount = 0
	for userId, count in counts do
		if count > bestCount then
			bestUserId, bestCount = userId, count
		end
	end
	if not bestUserId then
		return nil
	end
	local state = PlayerDataManager.get(bestUserId)
	return state and state.player.Name or nil
end

function SpectatorManager.resetMVPVotes()
	table.clear(mvpVotes)
end

----------------------------------------------------------------
-- Cosmetic-only chaos (dead players can trigger for fun, no gameplay effect)
----------------------------------------------------------------

local lastCosmeticAt: { [number]: number } = {}
local COSMETIC_COOLDOWN = 3

function SpectatorManager.triggerCosmetic(state: PlayerState)
	if state.alive then
		return
	end
	local now = os.clock()
	if now - (lastCosmeticAt[state.userId] or 0) < COSMETIC_COOLDOWN then
		return
	end
	lastCosmeticAt[state.userId] = now
	Remotes.get("CosmeticChaosTriggered"):FireAllClients(state.userId)
end

return SpectatorManager
