--!strict
-- Card dealing, the 3-pick draft, playing cards, and every card effect.
-- Death by empty hand and kill card-transfer live here too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CardDatabase = require(Shared.CardDatabase)
local Remotes = require(Shared.Remotes)
local PlayerDataManager = require(script.Parent.PlayerDataManager)
local BoardManager = require(script.Parent.BoardManager)
local CombatManager = require(script.Parent.CombatManager)

type PlayerState = PlayerDataManager.PlayerState

local CardManager = {}

-- Injected: TurnManager.skipNextTurn hook is set through GameManager
local deps: { skipPlayerTurn: (PlayerState) -> () }? = nil

function CardManager.inject(d)
	deps = d
end

----------------------------------------------------------------
-- Deck pool
----------------------------------------------------------------

local matchPool: { string } = {}

function CardManager.resetPool()
	matchPool = CardDatabase.buildMatchPool()
	-- Fisher-Yates shuffle
	for i = #matchPool, 2, -1 do
		local j = math.random(i)
		matchPool[i], matchPool[j] = matchPool[j], matchPool[i]
	end
end

local function drawFromPool(): string?
	return table.remove(matchPool)
end

-- Weighted random card id for draft pools / random fills.
local function weightedRandomCardId(): string
	local total = 0
	for _, weight in Config.DRAFT_WEIGHTS do
		total += weight
	end
	local roll = math.random() * total
	local cumulative = 0
	local chosenRarity = "Common"
	for rarity, weight in Config.DRAFT_WEIGHTS do
		cumulative += weight
		if roll <= cumulative then
			chosenRarity = rarity
			break
		end
	end
	local ids = CardDatabase.getByRarity(chosenRarity)
	return ids[math.random(#ids)]
end

----------------------------------------------------------------
-- Hand management
----------------------------------------------------------------

-- Add cards, burning any excess over the hand limit for Scrap.
function CardManager.giveCards(state: PlayerState, cardIds: { string })
	for _, cardId in cardIds do
		if #state.hand < Config.HAND_LIMIT then
			table.insert(state.hand, cardId)
		else
			state.scrap += Config.SCRAP_PER_BURNED_CARD
			Remotes.get("ActionFeed"):FireAllClients(
				`♻ {state.player.Name} burned an excess card for {Config.SCRAP_PER_BURNED_CARD} Scrap`)
		end
	end
	PlayerDataManager.sendHand(state)
	PlayerDataManager.broadcastStats()
end

function CardManager.drawCards(state: PlayerState, amount: number)
	local drawn = {}
	for _ = 1, amount do
		local cardId = drawFromPool() or weightedRandomCardId()
		table.insert(drawn, cardId)
	end
	CardManager.giveCards(state, drawn)
end

local function removeFromHand(state: PlayerState, handIndex: number): string?
	local cardId = state.hand[handIndex]
	if not cardId then
		return nil
	end
	table.remove(state.hand, handIndex)
	-- Re-index disabled markers after removal
	local newDisabled = {}
	for index, disabled in state.disabledCards do
		if index < handIndex then
			newDisabled[index] = disabled
		elseif index > handIndex then
			newDisabled[index - 1] = disabled
		end
	end
	state.disabledCards = newDisabled
	return cardId
end

-- Design doc: running out of cards = death.
local function checkEmptyHandDeath(state: PlayerState)
	if state.alive and #state.hand == 0 then
		Remotes.get("ActionFeed"):FireAllClients(`🃏 {state.player.Name} ran out of cards!`)
		CombatManager.killPlayer(state, nil)
	end
end

-- On kill: victim's entire hand transfers to the killer (excess burns).
function CardManager.transferCardsOnKill(killer: PlayerState?, victim: PlayerState)
	local loot = victim.hand
	victim.hand = {}
	victim.disabledCards = {}
	PlayerDataManager.sendHand(victim)
	if killer and killer.alive and #loot > 0 then
		CardManager.giveCards(killer, loot)
	end
end

----------------------------------------------------------------
-- Draft (match start)
----------------------------------------------------------------

local draftPicks: { [number]: string? } = {} -- userId -> picked card this phase

function CardManager.registerDraftPick(state: PlayerState, cardId: string)
	draftPicks[state.userId] = cardId
end

-- Runs the full 3-round draft, then fills to 10 cards. Yields.
function CardManager.runDraft()
	local players = PlayerDataManager.getAlive()

	for pick = 1, Config.DRAFT_PICKS do
		-- Fresh weighted pool each pick phase
		local pool = {}
		for _ = 1, Config.DRAFT_POOL_SIZE do
			table.insert(pool, weightedRandomCardId())
		end
		table.clear(draftPicks)
		for _, state in players do
			Remotes.get("DraftPoolUpdate"):FireClient(state.player, pool, pick, Config.DRAFT_PICK_TIME)
		end

		local deadline = os.clock() + Config.DRAFT_PICK_TIME
		while os.clock() < deadline do
			local allPicked = true
			for _, state in players do
				if not draftPicks[state.userId] then
					allPicked = false
					break
				end
			end
			if allPicked then
				break
			end
			task.wait(0.1)
		end

		for _, state in players do
			local chosen = draftPicks[state.userId]
			-- Auto-pick for players who timed out; validate real picks are in the pool
			if not chosen or not table.find(pool, chosen) then
				chosen = pool[math.random(#pool)]
			end
			CardManager.giveCards(state, { chosen })
		end
	end

	-- Random fill to 10 total
	for _, state in players do
		CardManager.drawCards(state, Config.DRAFT_RANDOM_FILL)
	end
end

----------------------------------------------------------------
-- Playing cards
----------------------------------------------------------------

-- Validates and executes a card played during the Action Phase.
function CardManager.playCard(state: PlayerState, handIndex: number, targetUserId: number?, tileIndex: number?): boolean
	assert(deps, "CardManager.inject not called")
	if not state.alive then
		return false
	end
	if state.disabledCards[handIndex] then
		return false
	end
	local cardId = state.hand[handIndex]
	local card = cardId and CardDatabase.get(cardId)
	if not card then
		return false
	end

	local effect = card.effect
	local effectType = effect.type

	-- Validate targeting BEFORE consuming the card
	local target: PlayerState? = nil
	if effectType == "attack" or effectType == "duel" then
		target = CombatManager.getNearestEnemy(state)
		if not target then
			return false
		end
		-- Click-to-confirm: the client sends the target it clicked; it must be the nearest
		if targetUserId and targetUserId ~= target.userId then
			return false
		end
	elseif effectType == "skipTurn" then
		-- Global targeting: any alive player
		target = targetUserId and PlayerDataManager.get(targetUserId) or nil
		if not target or not target.alive then
			return false
		end
	elseif effectType == "steal" then
		target = CombatManager.getNearestEnemy(state)
		if not target then
			return false
		end
	elseif effectType == "conditionalHeal" then
		if state.hp >= (effect.threshold :: number) then
			return false -- Last Stand only works when low
		end
	elseif effectType == "buff" then
		if not CardManager.canApplyBuff(state, effect) then
			return false
		end
	elseif effectType == "trap" then
		if effect.placement == "tile" then
			-- Place on own tile by default, or an adjacent tile the client chose
			local placeAt = tileIndex or state.tile
			if math.abs(placeAt - state.tile) > 1 then
				return false
			end
			if not BoardManager.placeTrap(placeAt, card.id, state.userId) then
				return false -- tile already trapped
			end
		else
			target = CombatManager.getNearestEnemy(state)
			if not target then
				return false
			end
		end
	end

	removeFromHand(state, handIndex)
	state.cardsPlayed += 1
	PlayerDataManager.sendHand(state)
	Remotes.get("CardPlayed"):FireAllClients(state.userId, card.id, target and target.userId or nil)

	CardManager.executeEffect(state, card, target)

	checkEmptyHandDeath(state)
	PlayerDataManager.broadcastStats()
	return true
end

function CardManager.canApplyBuff(state: PlayerState, effect: { [string]: any }): boolean
	local buffId = effect.buffId :: string?
	if not buffId then
		return true -- non-buff effects routed here (move etc.)
	end
	local existing = PlayerDataManager.getBuff(state, buffId)
	local now = os.clock()

	-- War Paint does not stack with Adrenaline Rush (and vice versa)
	local conflicts = effect.conflictsWith :: string?
	if conflicts and PlayerDataManager.getBuff(state, conflicts) then
		return false
	end
	if buffId == "AdrenalineRush" and PlayerDataManager.getBuff(state, "WarPaint") then
		return false
	end

	if existing then
		local maxStacks = effect.maxStacks :: number? or 1
		if existing.stacks >= maxStacks then
			return false
		end
		-- Stacking cooldown (2 min after using stacked buffs)
		if now - state.lastStackedBuffAt < Config.STACKED_BUFF_COOLDOWN and state.lastStackedBuffAt > 0 then
			return false
		end
		return true
	end

	-- Max 2 distinct buff effects active at once
	if #state.buffs >= Config.MAX_ACTIVE_BUFFS then
		return false
	end
	return true
end

----------------------------------------------------------------
-- Effect execution
----------------------------------------------------------------

function CardManager.executeEffect(state: PlayerState, card: CardDatabase.Card, target: PlayerState?)
	assert(deps, "CardManager.inject not called")
	local effect = card.effect
	local effectType = effect.type

	if effectType == "attack" then
		if target then
			CombatManager.performAttack(state, target, card.id)
		end

	elseif effectType == "heal" then
		state.hp = math.min(state.hp + (effect.amount :: number), state.maxHp)
		if effect.draw then
			CardManager.drawCards(state, effect.draw :: number)
		end
		Remotes.get("ActionFeed"):FireAllClients(`💚 {state.player.Name} healed {effect.amount} HP with {card.name}`)

	elseif effectType == "conditionalHeal" then
		state.hp = math.max(state.hp, effect.healTo :: number)
		Remotes.get("ActionFeed"):FireAllClients(`💚 {state.player.Name} made a Last Stand at {state.hp} HP!`)

	elseif effectType == "draw" then
		CardManager.drawCards(state, effect.amount :: number)

	elseif effectType == "steal" then
		if target then
			local stolen = {}
			for _ = 1, effect.amount :: number do
				if #target.hand > 0 then
					local index = math.random(#target.hand)
					table.insert(stolen, target.hand[index])
					table.remove(target.hand, index)
				end
			end
			PlayerDataManager.sendHand(target)
			CardManager.giveCards(state, stolen)
			Remotes.get("ActionFeed"):FireAllClients(
				`🌪 {state.player.Name} stole {#stolen} card(s) from {target.player.Name}!`)
			checkEmptyHandDeath(target)
		end

	elseif effectType == "dodge" then
		-- Playable proactively: arms a dodge for the next attack
		state.dodgeNextAttack = true
		Remotes.get("ActionFeed"):FireAllClients(`💨 {state.player.Name} is ready to juke!`)

	elseif effectType == "buff" then
		CardManager.applyBuff(state, card)

	elseif effectType == "move" then
		BoardManager.movePlayer(state, effect.tiles :: number)
		task.wait(0.5)
		BoardManager.applyTileEffect(state)

	elseif effectType == "chargeMove" then
		-- Road Warrior's Charge: damage everyone passed, then move
		local from = state.tile
		local to = math.clamp(from + (effect.tiles :: number), 1, Config.FINAL_TILE)
		for _, other in PlayerDataManager.getAlive() do
			if other.userId ~= state.userId and other.tile > from and other.tile <= to then
				CombatManager.applyDamage(other, effect.damage :: number, state)
			end
		end
		BoardManager.movePlayer(state, effect.tiles :: number)
		Remotes.get("ActionFeed"):FireAllClients(`🏍 {state.player.Name} charged down the road!`)

	elseif effectType == "aoeAttack" then
		local victims = CombatManager.getPlayersInRadius(state.tile, effect.radius :: number, state.userId)
		for _, victim in victims do
			CombatManager.applyDamage(victim, effect.damage :: number, state)
		end
		Remotes.get("ActionFeed"):FireAllClients(
			`💥 {state.player.Name} unleashed {card.name} hitting {#victims} player(s)!`)

	elseif effectType == "globalDamage" then
		for _, other in PlayerDataManager.getAlive() do
			if other.userId ~= state.userId then
				CombatManager.applyDamage(other, effect.damage :: number, state)
			end
		end
		Remotes.get("ActionFeed"):FireAllClients(`☠ {state.player.Name} spread the Wasteland Plague!`)

	elseif effectType == "emp" then
		local removed = BoardManager.disableTrapsInRadius(state.tile, effect.radius :: number)
		local nearest = CombatManager.getNearestEnemy(state)
		if nearest then
			CombatManager.applyDamage(nearest, effect.damage :: number, state)
		end
		Remotes.get("ActionFeed"):FireAllClients(`⚡ {state.player.Name}'s EMP disabled {removed} trap(s)!`)

	elseif effectType == "skipTurn" then
		if target then
			target.skipNextTurn = true
			CombatManager.applyStatusFromSpec(target, { id = "TimeWarp", duration = 60 }, state.userId)
			Remotes.get("ActionFeed"):FireAllClients(`🌀 {state.player.Name} warped {target.player.Name}'s next turn away!`)
		end

	elseif effectType == "duel" then
		if target then
			local damage = effect.damage :: number
			CombatManager.applyDamage(state, damage, target)
			CombatManager.applyDamage(target, damage, state)
			if state.alive and target.alive then
				local loser = state.hp < target.hp and state or target
				local winner = loser == state and target or state
				CombatManager.applyDamage(loser, effect.loserExtra :: number, winner)
			end
			Remotes.get("ActionFeed"):FireAllClients(
				`⚔ THUNDERDOME! {state.player.Name} vs {target.player.Name}!`)
		end

	elseif effectType == "trap" then
		if effect.placement == "player" and target then
			-- Player-placed traps trigger on the victim's next action
			CardManager.executeTrapCard(card.id, target, target.tile)
		end
		-- Tile traps were placed during validation in playCard
	end
end

function CardManager.applyBuff(state: PlayerState, card: CardDatabase.Card)
	local effect = card.effect
	local buffId = effect.buffId :: string
	local now = os.clock()
	local existing = PlayerDataManager.getBuff(state, buffId)

	if existing then
		existing.stacks += 1
		existing.expiresAt = now + (effect.duration :: number)
		state.lastStackedBuffAt = now
	else
		local buff: PlayerDataManager.Buff = {
			buffId = buffId,
			stacks = 1,
			expiresAt = now + (effect.duration :: number),
			damagePercent = effect.damagePercent,
			damageFlat = effect.damageFlat,
			nextAttackPercent = effect.nextAttackPercent,
			tempHP = effect.tempHP,
			shield = effect.shield,
			blockNextAttack = effect.blockNextAttack,
			deathProof = effect.deathProof,
			trapDodge = effect.trapDodge,
			bonusMove = effect.bonusMove,
			doubleTile = effect.doubleTile,
			revive = effect.revive,
		}
		table.insert(state.buffs, buff)
	end
	Remotes.get("ActionFeed"):FireAllClients(`💪 {state.player.Name} activated {card.name}!`)
	PlayerDataManager.broadcastStats()
end

-- Execute a trap card's payload against a victim (from tile step or player-placed).
function CardManager.executeTrapCard(cardId: string, victim: PlayerState, tileIndex: number)
	local card = CardDatabase.get(cardId)
	if not card or not victim.alive then
		return
	end
	local effect = card.effect
	local owner = nil -- environmental credit handled by CombatManager via status source

	if effect.aoeRadius then
		local victims = CombatManager.getPlayersInRadius(tileIndex, effect.aoeRadius :: number, nil)
		for _, aoeVictim in victims do
			if (effect.damage :: number) > 0 then
				CombatManager.applyDamage(aoeVictim, effect.damage :: number, owner)
			end
			if effect.status then
				CombatManager.applyStatusFromSpec(aoeVictim, effect.status :: { [string]: any }, nil)
			end
		end
	else
		if (effect.damage :: number) > 0 then
			CombatManager.applyDamage(victim, effect.damage :: number, owner)
		end
		if effect.status and victim.alive then
			CombatManager.applyStatusFromSpec(victim, effect.status :: { [string]: any }, nil)
		end
	end

	if effect.pullback and victim.alive then
		BoardManager.movePlayer(victim, -(effect.pullback :: number))
	end

	if effect.disableCards and victim.alive and #victim.hand > 0 then
		local index = math.random(#victim.hand)
		victim.disabledCards[index] = true
		PlayerDataManager.sendHand(victim)
	end

	Remotes.get("ActionFeed"):FireAllClients(`🪤 {victim.player.Name} triggered {card.name}!`)
end

return CardManager
