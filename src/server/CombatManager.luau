--!strict
-- Damage calculation, nearest-enemy targeting, the 1-second reaction window,
-- death handling and kill rewards.
--
-- Damage formula (design doc): Final = Base * (1 + Buff%) - Shield/Armor

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CardDatabase = require(Shared.CardDatabase)
local Remotes = require(Shared.Remotes)
local PlayerDataManager = require(script.Parent.PlayerDataManager)

type PlayerState = PlayerDataManager.PlayerState

local CombatManager = {}

-- Injected by init.server (CardManager functions, GameManager death hook)
local deps: {
	transferCardsOnKill: (killer: PlayerState?, victim: PlayerState) -> (),
	onPlayerDied: (victim: PlayerState, killer: PlayerState?) -> (),
}? = nil

function CombatManager.inject(d)
	deps = d
end

----------------------------------------------------------------
-- Targeting
----------------------------------------------------------------

-- Nearest enemy by tile distance; ties broken by lower HP, then random.
function CombatManager.getNearestEnemy(state: PlayerState): PlayerState?
	local best: PlayerState? = nil
	local bestDistance = math.huge
	for _, other in PlayerDataManager.getAlive() do
		if other.userId ~= state.userId then
			local distance = math.abs(other.tile - state.tile)
			if distance < bestDistance then
				best, bestDistance = other, distance
			elseif distance == bestDistance and best then
				if other.hp < best.hp or (other.hp == best.hp and math.random(2) == 1) then
					best = other
				end
			end
		end
	end
	return best
end

function CombatManager.getPlayersInRadius(centerTile: number, radius: number, excludeUserId: number?): { PlayerState }
	local out = {}
	for _, state in PlayerDataManager.getAlive() do
		if state.userId ~= excludeUserId and math.abs(state.tile - centerTile) <= radius then
			table.insert(out, state)
		end
	end
	return out
end

----------------------------------------------------------------
-- Damage & death
----------------------------------------------------------------

-- Raw damage application: consumes shields/temp HP, honors Iron Will and
-- Phoenix Flame, and triggers death. `source` credits the kill.
function CombatManager.applyDamage(victim: PlayerState, amount: number, source: PlayerState?)
	if not victim.alive or amount <= 0 then
		return
	end

	-- Shields absorb first (Shield Wall / Iron Fortress), then temp HP (Armor Plating)
	for _, buff in victim.buffs do
		if amount <= 0 then break end
		if buff.shield and buff.shield > 0 then
			local absorbed = math.min(buff.shield, amount)
			buff.shield -= absorbed
			amount -= absorbed
		end
	end
	for _, buff in victim.buffs do
		if amount <= 0 then break end
		if buff.tempHP and buff.tempHP > 0 then
			local absorbed = math.min(buff.tempHP, amount)
			buff.tempHP -= absorbed
			amount -= absorbed
		end
	end

	if amount <= 0 then
		PlayerDataManager.broadcastStats()
		return
	end

	local newHp = victim.hp - amount
	local ironWill = PlayerDataManager.getBuff(victim, "IronWill")
	if newHp <= 0 and ironWill and ironWill.deathProof then
		newHp = 1
	end
	victim.hp = math.max(newHp, 0)

	if source then
		source.damageDealt += amount
	end

	if victim.hp <= 0 then
		CombatManager.killPlayer(victim, source)
	else
		PlayerDataManager.broadcastStats()
	end
end

function CombatManager.killPlayer(victim: PlayerState, killer: PlayerState?)
	assert(deps, "CombatManager.inject not called")
	if not victim.alive then
		return
	end

	-- Phoenix Flame: revive instead of dying
	local phoenix = PlayerDataManager.getBuff(victim, "PhoenixFlame")
	if phoenix and phoenix.revive then
		victim.hp = phoenix.revive
		PlayerDataManager.removeBuff(victim, "PhoenixFlame")
		Remotes.get("ActionFeed"):FireAllClients(`🔥 {victim.player.Name} rose from the ashes with {victim.hp} HP!`)
		PlayerDataManager.broadcastStats()
		return
	end

	victim.alive = false
	victim.hp = 0

	if killer then
		killer.kills += 1
		killer.scrap += Config.SCRAP_PER_KILL
	end
	deps.transferCardsOnKill(killer, victim)

	-- Ghost mode: semi-transparent avatar
	local character = victim.player.Character
	if character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = 0.7
				part.CanCollide = false
			elseif part:IsA("Decal") then
				part.Transparency = 0.7
			end
		end
	end

	Remotes.get("PlayerDied"):FireAllClients(victim.userId, killer and killer.userId or nil)
	Remotes.get("ActionFeed"):FireAllClients(
		killer and `💀 {killer.player.Name} eliminated {victim.player.Name}!`
			or `💀 {victim.player.Name} was eliminated!`
	)
	PlayerDataManager.broadcastStats()
	deps.onPlayerDied(victim, killer)
end

----------------------------------------------------------------
-- Attacks with reaction window
----------------------------------------------------------------

-- Pending reactions keyed by defender userId
local pendingReactions: { [number]: { reacted: boolean, reactionCardId: string? } } = {}

function CombatManager.registerReaction(defender: PlayerState, cardId: string): boolean
	local pending = pendingReactions[defender.userId]
	if not pending or pending.reacted then
		return false
	end
	local card = CardDatabase.get(cardId)
	if not card or not card.isReaction then
		return false
	end
	pending.reacted = true
	pending.reactionCardId = cardId
	return true
end

-- Full attack flow: announce, open 1s reaction window, resolve.
-- Yields for the reaction window; callers run inside the Resolution phase.
function CombatManager.performAttack(attacker: PlayerState, defender: PlayerState, cardId: string)
	local card = CardDatabase.get(cardId)
	if not card then
		return
	end
	local baseDamage = card.effect.damage :: number

	-- Passive dodge from a previously played Juke Move
	if defender.dodgeNextAttack then
		defender.dodgeNextAttack = false
		Remotes.get("CombatResult"):FireAllClients({
			attacker = attacker.userId, defender = defender.userId,
			cardId = cardId, result = "Dodged",
		})
		Remotes.get("ActionFeed"):FireAllClients(`💨 {defender.player.Name} dodged {attacker.player.Name}'s {card.name}!`)
		return
	end

	-- Iron Fortress full block
	local fortress = PlayerDataManager.getBuff(defender, "IronFortress")
	if fortress and fortress.blockNextAttack then
		fortress.blockNextAttack = nil
		Remotes.get("CombatResult"):FireAllClients({
			attacker = attacker.userId, defender = defender.userId,
			cardId = cardId, result = "Blocked",
		})
		Remotes.get("ActionFeed"):FireAllClients(`🛡 {defender.player.Name}'s Iron Fortress blocked {card.name}!`)
		return
	end

	-- Open the 1-second reaction window
	pendingReactions[defender.userId] = { reacted = false }
	local deadline = os.clock() + Config.REACTION_WINDOW
	Remotes.get("ReactionWindow"):FireClient(defender.player, attacker.userId, cardId, Config.REACTION_WINDOW)
	while os.clock() < deadline do
		local pending = pendingReactions[defender.userId]
		if pending and pending.reacted then
			break
		end
		task.wait(0.05)
	end

	local pending = pendingReactions[defender.userId]
	pendingReactions[defender.userId] = nil
	local reactionCardId = pending and pending.reactionCardId

	-- Damage after attacker's buffs: Base * (1 + percent) + flat, then Overcharge
	local percent, flat = PlayerDataManager.getDamageModifiers(attacker)
	local damage = math.floor(baseDamage * (1 + percent) + flat)
	local overcharge = PlayerDataManager.getBuff(attacker, "Overcharge")
	if overcharge and overcharge.nextAttackPercent then
		damage = math.floor(damage * (1 + overcharge.nextAttackPercent))
		PlayerDataManager.removeBuff(attacker, "Overcharge")
	end

	if reactionCardId == "SmokeBomb" then
		Remotes.get("ActionFeed"):FireAllClients(`💨 {defender.player.Name} smoke-bombed away from {card.name}!`)
		Remotes.get("CombatResult"):FireAllClients({
			attacker = attacker.userId, defender = defender.userId,
			cardId = cardId, result = "Cancelled", reaction = reactionCardId,
		})
		return
	elseif reactionCardId == "JukeMove" then
		Remotes.get("ActionFeed"):FireAllClients(`💨 {defender.player.Name} juked {attacker.player.Name}'s {card.name}!`)
		Remotes.get("CombatResult"):FireAllClients({
			attacker = attacker.userId, defender = defender.userId,
			cardId = cardId, result = "Dodged", reaction = reactionCardId,
		})
		return
	elseif reactionCardId == "Counterspin" then
		local counterCard = CardDatabase.get("Counterspin")
		local counterDamage = counterCard and counterCard.effect.damage :: number or 15
		Remotes.get("ActionFeed"):FireAllClients(`🌀 {defender.player.Name} countered {card.name} for {counterDamage}!`)
		Remotes.get("CombatResult"):FireAllClients({
			attacker = attacker.userId, defender = defender.userId,
			cardId = cardId, result = "Countered", reaction = reactionCardId,
		})
		CombatManager.applyDamage(attacker, counterDamage, defender)
		return
	elseif reactionCardId == "DeflectorPlate" then
		local reflected = math.floor(damage * 0.5)
		Remotes.get("ActionFeed"):FireAllClients(`🛡 {defender.player.Name} deflected {reflected} damage back!`)
		Remotes.get("CombatResult"):FireAllClients({
			attacker = attacker.userId, defender = defender.userId,
			cardId = cardId, result = "Reflected", damage = damage - reflected, reaction = reactionCardId,
		})
		CombatManager.applyDamage(attacker, reflected, defender)
		CombatManager.applyDamage(defender, damage - reflected, attacker)
	else
		-- Clean hit
		Remotes.get("CombatResult"):FireAllClients({
			attacker = attacker.userId, defender = defender.userId,
			cardId = cardId, result = "Hit", damage = damage,
		})
		Remotes.get("ActionFeed"):FireAllClients(`⚔ {attacker.player.Name} hit {defender.player.Name} with {card.name} for {damage}!`)
		CombatManager.applyDamage(defender, damage, attacker)
	end

	-- Rider status effects (e.g. Molotov burn)
	local statusSpec = card.effect.status
	if statusSpec and defender.alive then
		CombatManager.applyStatusFromSpec(defender, statusSpec, attacker.userId)
	end
end

-- Convert a card's status spec into a live Status and schedule DOT ticks.
function CombatManager.applyStatusFromSpec(victim: PlayerState, spec: { [string]: any }, sourceUserId: number?)
	local now = os.clock()
	local status: PlayerDataManager.Status = {
		id = spec.id,
		expiresAt = spec.duration and now + spec.duration or nil,
		turnsLeft = spec.turns,
		dotDamage = spec.dotDamage,
		dotInterval = spec.dotInterval,
		nextTick = spec.dotInterval and now + spec.dotInterval or nil,
		skipMove = spec.skipMove,
		immobile = spec.immobile,
		diceModifier = spec.diceModifier,
		sourceUserId = sourceUserId,
	}
	PlayerDataManager.addStatus(victim, status)
	PlayerDataManager.broadcastStats()
end

-- Called on heartbeat: apply damage-over-time statuses.
function CombatManager.tickDOTs(now: number)
	for _, state in PlayerDataManager.getAll() do
		if state.alive then
			for _, status in state.statuses do
				if status.dotDamage and status.nextTick and now >= status.nextTick then
					status.nextTick = now + (status.dotInterval or 1)
					local source = status.sourceUserId and PlayerDataManager.get(status.sourceUserId) or nil
					CombatManager.applyDamage(state, status.dotDamage, source)
				end
			end
		end
	end
end

return CombatManager
