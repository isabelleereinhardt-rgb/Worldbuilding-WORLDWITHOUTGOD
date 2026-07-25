--!strict
-- Match state machine: Lobby -> Draft -> Playing -> GameOver -> Lobby.
-- Owns the 6-minute match timer, win conditions, and the heartbeat that
-- ticks DOTs and expires buffs/statuses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local PlayerDataManager = require(script.Parent.PlayerDataManager)
local BoardManager = require(script.Parent.BoardManager)
local CardManager = require(script.Parent.CardManager)
local CombatManager = require(script.Parent.CombatManager)
local TurnManager = require(script.Parent.TurnManager)
local SpectatorManager = require(script.Parent.SpectatorManager)

type PlayerState = PlayerDataManager.PlayerState

local GameManager = {}

local matchState = "Lobby" -- "Lobby" | "Draft" | "Playing" | "GameOver"
local matchEndTime = 0
local matchOver = false

local function setState(state: string, data: { [string]: any }?)
	matchState = state
	Remotes.get("GameStateChanged"):FireAllClients(state, data)
end

function GameManager.getState(): string
	return matchState
end

----------------------------------------------------------------
-- Win conditions
----------------------------------------------------------------

local function buildScoreboard(): { { [string]: any } }
	local rows = {}
	for _, state in PlayerDataManager.getAll() do
		table.insert(rows, {
			userId = state.userId,
			name = state.player.Name,
			kills = state.kills,
			damageDealt = state.damageDealt,
			cardsPlayed = state.cardsPlayed,
			scrap = state.scrap,
			alive = state.alive,
			finished = state.finished,
		})
	end
	table.sort(rows, function(a, b)
		if a.finished ~= b.finished then
			return a.finished
		end
		if a.alive ~= b.alive then
			return a.alive
		end
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.damageDealt > b.damageDealt
	end)
	return rows
end

local function endMatch(winner: PlayerState?, reason: string)
	if matchOver then
		return
	end
	matchOver = true
	TurnManager.stop()
	SpectatorManager.stop()

	-- Match completion Scrap for everyone
	for _, state in PlayerDataManager.getAll() do
		state.scrap += math.random(Config.SCRAP_MATCH_MIN, Config.SCRAP_MATCH_MAX)
	end

	local scoreboard = buildScoreboard()
	setState("GameOver", { reason = reason })
	Remotes.get("MatchEnded"):FireAllClients({
		winnerUserId = winner and winner.userId or nil,
		winnerName = winner and winner.player.Name or "Nobody",
		reason = reason,
		scoreboard = scoreboard,
		crowdFavorite = SpectatorManager.getCrowdFavoriteName(),
	})
	Remotes.get("ActionFeed"):FireAllClients(
		winner and `🏆 {winner.player.Name} wins — {reason}!` or `🏆 Match over — {reason}`)

	task.delay(10, function()
		GameManager.returnToLobby()
	end)
end

-- Returns true if the match ended. Checked after tile effects and resolutions.
function GameManager.checkWinConditions(): boolean
	if matchState ~= "Playing" or matchOver then
		return matchOver
	end

	-- 1) First to the final tile wins instantly
	for _, state in PlayerDataManager.getAlive() do
		if state.finished then
			endMatch(state, "reached the Thunderdome finish line")
			return true
		end
	end

	-- 2) Last player standing
	local alive = PlayerDataManager.getAlive()
	if #alive == 1 then
		endMatch(alive[1], "last warrior standing")
		return true
	elseif #alive == 0 then
		endMatch(nil, "mutual destruction")
		return true
	end

	-- 3) Time up -> most kills (ties broken by damage dealt)
	if os.clock() >= matchEndTime then
		local best: PlayerState? = nil
		for _, state in alive do
			if not best
				or state.kills > best.kills
				or (state.kills == best.kills and state.damageDealt > best.damageDealt) then
				best = state
			end
		end
		endMatch(best, "most kills when time expired")
		return true
	end
	return false
end

----------------------------------------------------------------
-- Match flow
----------------------------------------------------------------

function GameManager.returnToLobby()
	matchOver = false
	PlayerDataManager.clearAll()
	BoardManager.resetTraps()
	SpectatorManager.resetMVPVotes()
	setState("Lobby")
	GameManager.tryStartCountdown()
end

function GameManager.tryStartCountdown()
	task.spawn(function()
		while matchState == "Lobby" do
			local playerCount = #Players:GetPlayers()
			if playerCount >= Config.MIN_PLAYERS_TO_START then
				-- Intermission countdown
				for remaining = Config.INTERMISSION_TIME, 1, -1 do
					if #Players:GetPlayers() < Config.MIN_PLAYERS_TO_START then
						break
					end
					Remotes.get("MatchTimerUpdate"):FireAllClients(remaining, #Players:GetPlayers())
					task.wait(1)
				end
				if #Players:GetPlayers() >= Config.MIN_PLAYERS_TO_START and matchState == "Lobby" then
					GameManager.startMatch()
					return
				end
			else
				task.wait(2)
			end
		end
	end)
end

function GameManager.startMatch()
	matchOver = false

	-- Register up to 16 players
	local roster = Players:GetPlayers()
	for i, player in roster do
		if i > Config.MAX_PLAYERS then
			break
		end
		local state = PlayerDataManager.setup(player)
		BoardManager.teleportToTile(state, 1)
	end
	PlayerDataManager.assignGroups()
	BoardManager.resetTraps()
	CardManager.resetPool()
	PlayerDataManager.broadcastStats()

	-- Draft phase: 3 picks + random fill
	setState("Draft")
	CardManager.runDraft()

	-- Playing phase
	matchEndTime = os.clock() + Config.MATCH_DURATION
	setState("Playing")
	TurnManager.start()
	SpectatorManager.start()

	-- Match timer broadcast
	task.spawn(function()
		while matchState == "Playing" and not matchOver do
			local timeLeft = math.max(matchEndTime - os.clock(), 0)
			Remotes.get("MatchTimerUpdate"):FireAllClients(timeLeft, #PlayerDataManager.getAlive())
			if timeLeft <= 0 then
				GameManager.checkWinConditions()
				break
			end
			task.wait(1)
		end
	end)
end

function GameManager.onPlayerDied(_victim: PlayerState, _killer: PlayerState?)
	GameManager.checkWinConditions()
end

----------------------------------------------------------------
-- Heartbeat: DOT ticks + buff/status expiry
----------------------------------------------------------------

local statsAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	if matchState ~= "Playing" then
		return
	end
	local now = os.clock()
	PlayerDataManager.tickTimers(now)
	CombatManager.tickDOTs(now)

	statsAccumulator += dt
	if statsAccumulator >= 1 then
		statsAccumulator = 0
		PlayerDataManager.broadcastStats()
		SpectatorManager.broadcastActiveModifiers()
	end
end)

-- Leaving mid-match counts as elimination.
-- (PlayerDataManager may have already dropped the state via its own
-- PlayerRemoving handler, so always re-check win conditions.)
Players.PlayerRemoving:Connect(function(player)
	if matchState ~= "Playing" then
		return
	end
	local state = PlayerDataManager.get(player.UserId)
	if state and state.alive then
		state.alive = false
	end
	Remotes.get("ActionFeed"):FireAllClients(`🚪 {player.Name} fled the wasteland`)
	task.defer(GameManager.checkWinConditions)
end)

return GameManager
