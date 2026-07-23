--!strict
-- Per-player match state: HP, hand, board position, kills, statuses, buffs.
-- Also broadcasts stat snapshots so every client can render heads-up info
-- (HP bars, card counts above heads, status icons).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

export type Status = {
	id: string,            -- "Burn", "Bleeding", "Slowed", "Trapped", "Blinded", ...
	expiresAt: number?,    -- os.clock() deadline for time-based statuses
	turnsLeft: number?,    -- for turn-based statuses (immobilize)
	dotDamage: number?,
	dotInterval: number?,
	nextTick: number?,
	skipMove: boolean?,
	immobile: boolean?,
	diceModifier: number?,
	sourceUserId: number?,
}

export type Buff = {
	buffId: string,
	stacks: number,
	expiresAt: number,
	damagePercent: number?,
	damageFlat: number?,
	nextAttackPercent: number?,
	tempHP: number?,
	shield: number?,
	blockNextAttack: boolean?,
	deathProof: boolean?,
	trapDodge: boolean?,
	bonusMove: number?,
	doubleTile: boolean?,
	revive: number?,
}

export type PlayerState = {
	player: Player,
	userId: number,
	hp: number,
	maxHp: number,
	tile: number,
	hand: { string },          -- card ids
	disabledCards: { [number]: boolean }, -- hand indices disabled by Shock Mine
	alive: boolean,
	kills: number,
	damageDealt: number,
	cardsPlayed: number,
	scrap: number,
	group: number,             -- turn group 1-4
	statuses: { Status },
	buffs: { Buff },
	skipNextTurn: boolean,
	dodgeNextAttack: boolean,
	lastStackedBuffAt: number,
	finished: boolean,         -- reached tile 60
}

local PlayerDataManager = {}

local states: { [number]: PlayerState } = {}

function PlayerDataManager.setup(player: Player): PlayerState
	local state: PlayerState = {
		player = player,
		userId = player.UserId,
		hp = Config.STARTING_HP,
		maxHp = Config.STARTING_HP,
		tile = 1,
		hand = {},
		disabledCards = {},
		alive = true,
		kills = 0,
		damageDealt = 0,
		cardsPlayed = 0,
		scrap = 0,
		group = 1,
		statuses = {},
		buffs = {},
		skipNextTurn = false,
		dodgeNextAttack = false,
		lastStackedBuffAt = 0,
		finished = false,
	}
	states[player.UserId] = state
	return state
end

function PlayerDataManager.get(userId: number): PlayerState?
	return states[userId]
end

function PlayerDataManager.getAll(): { [number]: PlayerState }
	return states
end

function PlayerDataManager.getAlive(): { PlayerState }
	local out = {}
	for _, state in states do
		if state.alive then
			table.insert(out, state)
		end
	end
	return out
end

function PlayerDataManager.remove(userId: number)
	states[userId] = nil
end

function PlayerDataManager.clearAll()
	table.clear(states)
end

-- Assign alive players round-robin into turn groups.
function PlayerDataManager.assignGroups()
	local alive = PlayerDataManager.getAlive()
	for i, state in alive do
		state.group = ((i - 1) % Config.GROUP_COUNT) + 1
	end
end

----------------------------------------------------------------
-- Statuses & buffs
----------------------------------------------------------------

function PlayerDataManager.addStatus(state: PlayerState, status: Status)
	-- Refresh instead of stacking identical statuses
	for _, existing in state.statuses do
		if existing.id == status.id then
			existing.expiresAt = status.expiresAt
			existing.turnsLeft = status.turnsLeft
			return
		end
	end
	table.insert(state.statuses, status)
end

function PlayerDataManager.hasStatus(state: PlayerState, id: string): boolean
	for _, status in state.statuses do
		if status.id == id then
			return true
		end
	end
	return false
end

function PlayerDataManager.removeStatus(state: PlayerState, id: string)
	for i = #state.statuses, 1, -1 do
		if state.statuses[i].id == id then
			table.remove(state.statuses, i)
		end
	end
end

function PlayerDataManager.getBuff(state: PlayerState, buffId: string): Buff?
	for _, buff in state.buffs do
		if buff.buffId == buffId then
			return buff
		end
	end
	return nil
end

function PlayerDataManager.removeBuff(state: PlayerState, buffId: string)
	for i = #state.buffs, 1, -1 do
		if state.buffs[i].buffId == buffId then
			table.remove(state.buffs, i)
		end
	end
end

-- Sum of active damage buffs, applied as Final = Base * (1 + percent) + flat.
function PlayerDataManager.getDamageModifiers(state: PlayerState): (number, number)
	local percent, flat = 0, 0
	for _, buff in state.buffs do
		if buff.damagePercent then
			percent += buff.damagePercent * buff.stacks
		end
		if buff.damageFlat then
			flat += buff.damageFlat
		end
	end
	return percent, flat
end

-- Expire timed statuses/buffs. Called every heartbeat by GameManager.
function PlayerDataManager.tickTimers(now: number)
	for _, state in states do
		for i = #state.statuses, 1, -1 do
			local status = state.statuses[i]
			if status.expiresAt and now >= status.expiresAt then
				table.remove(state.statuses, i)
			end
		end
		for i = #state.buffs, 1, -1 do
			local buff = state.buffs[i]
			if now >= buff.expiresAt then
				table.remove(state.buffs, i)
			end
		end
	end
end

----------------------------------------------------------------
-- Replication
----------------------------------------------------------------

function PlayerDataManager.broadcastStats()
	local snapshot = {}
	for userId, state in states do
		local statusIds = {}
		for _, status in state.statuses do
			table.insert(statusIds, status.id)
		end
		for _, buff in state.buffs do
			table.insert(statusIds, buff.buffId)
		end
		snapshot[tostring(userId)] = {
			name = state.player.Name,
			hp = state.hp,
			maxHp = state.maxHp,
			cards = #state.hand,
			tile = state.tile,
			alive = state.alive,
			kills = state.kills,
			statuses = statusIds,
		}
	end
	Remotes.get("PlayerStatsUpdate"):FireAllClients(snapshot)
end

function PlayerDataManager.sendHand(state: PlayerState)
	Remotes.get("HandUpdate"):FireClient(state.player, state.hand, state.disabledCards)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerDataManager.remove(player.UserId)
end)

return PlayerDataManager
