--!strict
-- Simultaneous group turns: players split into 4 groups; each group runs
-- Roll (2s) -> Movement (3s) -> Tile Effect (2s) -> Action (10s) -> Resolution.
-- Groups cycle so any player waits ~40s between turns instead of 2.5 min.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PlayerDataManager = require(script.Parent.PlayerDataManager)
local BoardManager = require(script.Parent.BoardManager)

type PlayerState = PlayerDataManager.PlayerState

local TurnManager = {}

local currentGroup = 0
local currentPhase = "Idle"
local running = false

-- Cards queued during the Action Phase, resolved in the Resolution Phase.
-- Each entry: {state, handIndex, targetUserId, tileIndex}
local actionQueue: { { state: PlayerState, handIndex: number, targetUserId: number?, tileIndex: number? } } = {}

local deps: {
	playCard: (PlayerState, number, number?, number?) -> boolean,
	checkWinConditions: () -> boolean,
}? = nil

function TurnManager.inject(d)
	deps = d
end

function TurnManager.getCurrentGroup(): number
	return currentGroup
end

function TurnManager.getCurrentPhase(): string
	return currentPhase
end

function TurnManager.isActionPhaseFor(state: PlayerState): boolean
	return running and currentPhase == "Action" and state.group == currentGroup and state.alive
end

-- Client card plays land here during the Action Phase.
function TurnManager.queueAction(state: PlayerState, handIndex: number, targetUserId: number?, tileIndex: number?)
	table.insert(actionQueue, {
		state = state,
		handIndex = handIndex,
		targetUserId = targetUserId,
		tileIndex = tileIndex,
	})
end

local function broadcastPhase(phase: string, timeLeft: number)
	currentPhase = phase
	for _, state in PlayerDataManager.getAlive() do
		local myTurn = state.group == currentGroup
		Remotes.get("TurnPhaseUpdate"):FireClient(state.player, currentGroup, phase, timeLeft, myTurn)
	end
	-- Spectators see the phase too
	for _, state in PlayerDataManager.getAll() do
		if not state.alive then
			Remotes.get("TurnPhaseUpdate"):FireClient(state.player, currentGroup, phase, timeLeft, false)
		end
	end
end

local function groupMembers(group: number): { PlayerState }
	local out = {}
	for _, state in PlayerDataManager.getAlive() do
		if state.group == group then
			table.insert(out, state)
		end
	end
	return out
end

-- One full turn for one group. Yields for the duration of the phases.
local function runGroupTurn(group: number)
	assert(deps, "TurnManager.inject not called")
	currentGroup = group
	local members = groupMembers(group)
	if #members == 0 then
		return
	end

	-- Skip players hit by Time Warp Vortex
	local active: { PlayerState } = {}
	for _, state in members do
		if state.skipNextTurn then
			state.skipNextTurn = false
			PlayerDataManager.removeStatus(state, "TimeWarp")
			Remotes.get("ActionFeed"):FireAllClients(`🌀 {state.player.Name}'s turn was skipped!`)
		else
			table.insert(active, state)
		end
	end
	if #active == 0 then
		return
	end

	----------------------------------------------------------------
	-- 1. Roll Phase (2s): everyone in the group rolls simultaneously
	----------------------------------------------------------------
	broadcastPhase("Roll", Config.PHASE_TIMES.Roll)
	local rolls: { [PlayerState]: number } = {}
	for _, state in active do
		local roll = math.random(Config.DICE_MIN, Config.DICE_MAX)
		-- Tar Pit: -1 to next dice roll
		for _, status in state.statuses do
			if status.diceModifier then
				roll = math.max(roll + status.diceModifier, 1)
				status.diceModifier = nil
			end
		end
		-- Nitro Boost: +2 movement
		local nitro = PlayerDataManager.getBuff(state, "NitroBoost")
		if nitro and nitro.bonusMove then
			roll += nitro.bonusMove
			nitro.bonusMove = nil
		end
		rolls[state] = roll
		Remotes.get("DiceRolled"):FireAllClients(state.userId, roll)
	end
	task.wait(Config.PHASE_TIMES.Roll)

	----------------------------------------------------------------
	-- 2. Movement Phase (3s): mandatory movement
	----------------------------------------------------------------
	broadcastPhase("Movement", Config.PHASE_TIMES.Movement)
	for _, state in active do
		if not state.alive then
			continue
		end
		local blocked = false
		for _, status in state.statuses do
			if status.immobile or status.skipMove then
				blocked = true
				-- Consume turn-based immobilizes
				if status.turnsLeft then
					status.turnsLeft -= 1
					if status.turnsLeft <= 0 then
						PlayerDataManager.removeStatus(state, status.id)
					end
				elseif status.skipMove then
					PlayerDataManager.removeStatus(state, status.id)
				end
				break
			end
		end
		if blocked then
			Remotes.get("ActionFeed"):FireAllClients(`🪤 {state.player.Name} is stuck and can't move!`)
		else
			BoardManager.movePlayer(state, rolls[state] or 0)
		end
	end
	task.wait(Config.PHASE_TIMES.Movement)

	----------------------------------------------------------------
	-- 3. Tile Effect Phase (2s)
	----------------------------------------------------------------
	broadcastPhase("TileEffect", Config.PHASE_TIMES.TileEffect)
	for _, state in active do
		if state.alive then
			BoardManager.applyTileEffect(state)
			-- Reaching the final tile is an instant win — checked right away
			if state.tile >= Config.FINAL_TILE then
				state.finished = true
			end
		end
	end
	PlayerDataManager.broadcastStats()
	if deps.checkWinConditions() then
		return
	end
	task.wait(Config.PHASE_TIMES.TileEffect)

	----------------------------------------------------------------
	-- 4. Action Phase (10s): play cards
	----------------------------------------------------------------
	table.clear(actionQueue)
	broadcastPhase("Action", Config.PHASE_TIMES.Action)
	local deadline = os.clock() + Config.PHASE_TIMES.Action
	while os.clock() < deadline do
		-- Resolve queued plays as they come in so counters/reactions feel live
		local action = table.remove(actionQueue, 1)
		if action then
			if TurnManager.isActionPhaseFor(action.state) or action.state.alive then
				deps.playCard(action.state, action.handIndex, action.targetUserId, action.tileIndex)
			end
		else
			task.wait(0.05)
		end
	end

	----------------------------------------------------------------
	-- 5. Resolution Phase: drain anything still queued
	----------------------------------------------------------------
	broadcastPhase("Resolution", Config.PHASE_TIMES.Resolution)
	while #actionQueue > 0 do
		local action = table.remove(actionQueue, 1)
		if action and action.state.alive then
			deps.playCard(action.state, action.handIndex, action.targetUserId, action.tileIndex)
		end
	end
	task.wait(0.5)

	deps.checkWinConditions()
end

-- Main loop: cycle through groups until the match ends.
function TurnManager.start()
	running = true
	task.spawn(function()
		local group = 0
		while running do
			group = (group % Config.GROUP_COUNT) + 1
			runGroupTurn(group)
			if not running then
				break
			end
			task.wait(0.5)
		end
	end)
end

function TurnManager.stop()
	running = false
	currentPhase = "Idle"
	currentGroup = 0
	table.clear(actionQueue)
end

return TurnManager
