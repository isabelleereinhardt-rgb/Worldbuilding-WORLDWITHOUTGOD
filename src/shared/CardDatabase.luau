--!strict
-- All 70 cards from the game design document.
-- Each card is data-only; CardManager/CombatManager interpret the `effect` table.
--
-- Rarities: Common (6 unique x5 = 30), Uncommon (10), Trap (10), Support (10), Rare (10)
-- Total pool: 70 cards.

export type CardEffect = {
	type: string,
	[string]: any,
}

export type Card = {
	id: string,
	name: string,
	rarity: string, -- "Common" | "Uncommon" | "Trap" | "Support" | "Rare"
	description: string,
	copies: number, -- copies of this card in the match pool
	isReaction: boolean?, -- playable during the 1s reaction window
	effect: CardEffect,
}

local Cards: { [string]: Card } = {}

local function define(card: Card)
	Cards[card.id] = card
end

----------------------------------------------------------------
-- COMMON ATTACK CARDS (x5 each = 30 total)
----------------------------------------------------------------
define({
	id = "RustySpanner", name = "Rusty Spanner", rarity = "Common", copies = 5,
	description = "Basic melee attack. 10 damage.",
	effect = { type = "attack", damage = 10, visual = "WrenchSwing" },
})
define({
	id = "ScrapShard", name = "Scrap Shard", rarity = "Common", copies = 5,
	description = "Thrown projectile. 15 damage.",
	effect = { type = "attack", damage = 15, visual = "ShardThrow" },
})
define({
	id = "SpikedWheel", name = "Spiked Wheel", rarity = "Common", copies = 5,
	description = "Rolling attack. 20 damage.",
	effect = { type = "attack", damage = 20, visual = "WheelRoll" },
})
define({
	id = "ChainsawSwipe", name = "Chainsaw Swipe", rarity = "Common", copies = 5,
	description = "Heavy melee. 25 damage.",
	effect = { type = "attack", damage = 25, visual = "ChainsawSlash" },
})
define({
	id = "MolotovToss", name = "Molotov Toss", rarity = "Common", copies = 5,
	description = "15 damage + Burn (5 dmg every 2s for 4s).",
	effect = { type = "attack", damage = 15, visual = "FireBottle",
		status = { id = "Burn", dotDamage = 5, dotInterval = 2, duration = 4 } },
})
define({
	id = "CrossbowBolt", name = "Crossbow Bolt", rarity = "Common", copies = 5,
	description = "Ranged precision shot. 20 damage.",
	effect = { type = "attack", damage = 20, visual = "BoltFire" },
})

----------------------------------------------------------------
-- UNCOMMON UTILITY CARDS (10 total)
----------------------------------------------------------------
define({
	id = "BattlefieldBandage", name = "Battlefield Bandage", rarity = "Uncommon", copies = 1,
	description = "Heal 10 HP instantly.",
	effect = { type = "heal", amount = 10 },
})
define({
	id = "ScrapMedkit", name = "Scrap Medkit", rarity = "Uncommon", copies = 1,
	description = "Heal 20 HP instantly.",
	effect = { type = "heal", amount = 20 },
})
define({
	id = "JukeMove", name = "Juke Move", rarity = "Uncommon", copies = 1, isReaction = true,
	description = "Dodge the next attack. Consumed on dodge.",
	effect = { type = "dodge" },
})
define({
	id = "Counterspin", name = "Counterspin", rarity = "Uncommon", copies = 1, isReaction = true,
	description = "Counter an incoming attack for 15 damage. Must play during the 1s reaction window.",
	effect = { type = "counter", damage = 15 },
})
define({
	id = "DeflectorPlate", name = "Deflector Plate", rarity = "Uncommon", copies = 1, isReaction = true,
	description = "Reflect 50% of an incoming attack's damage back at the attacker.",
	effect = { type = "reflect", percent = 0.5 },
})
define({
	id = "SecondWind", name = "Second Wind", rarity = "Uncommon", copies = 1,
	description = "Heal 15 HP and draw 1 card.",
	effect = { type = "heal", amount = 15, draw = 1 },
})
define({
	id = "SmokeBomb", name = "Smoke Bomb", rarity = "Uncommon", copies = 1, isReaction = true,
	description = "Cancel the attack currently targeting you. Escape card.",
	effect = { type = "cancel" },
})
define({
	id = "QuickHands", name = "Quick Hands", rarity = "Uncommon", copies = 1,
	description = "Draw 2 cards instantly.",
	effect = { type = "draw", amount = 2 },
})
define({
	id = "Salvage", name = "Salvage", rarity = "Uncommon", copies = 1,
	description = "Steal 1 random card from the nearest enemy.",
	effect = { type = "steal", amount = 1, target = "nearest" },
})
define({
	id = "LastStand", name = "Last Stand", rarity = "Uncommon", copies = 1,
	description = "If below 20 HP, heal to 35 HP. Only works when low.",
	effect = { type = "conditionalHeal", threshold = 20, healTo = 35 },
})

----------------------------------------------------------------
-- TRAP CARDS (10 total)
----------------------------------------------------------------
define({
	id = "OilSlick", name = "Oil Slick", rarity = "Trap", copies = 1,
	description = "Trap on tile: 10 damage + victim skips their next move phase.",
	effect = { type = "trap", placement = "tile", damage = 10,
		status = { id = "Slowed", skipMove = true, duration = 15 } },
})
define({
	id = "SpikeNet", name = "Spike Net", rarity = "Trap", copies = 1,
	description = "Trap on player: 15 damage + immobilize for 1 turn.",
	effect = { type = "trap", placement = "player", damage = 15,
		status = { id = "Trapped", immobile = true, turns = 1 } },
})
define({
	id = "FlareTrip", name = "Flare Trip", rarity = "Trap", copies = 1,
	description = "Trap on tile: 5 damage + blind (UI obscured for 5s).",
	effect = { type = "trap", placement = "tile", damage = 5,
		status = { id = "Blinded", duration = 5 } },
})
define({
	id = "BearTrap", name = "Bear Trap", rarity = "Trap", copies = 1,
	description = "Trap on tile: 20 damage + immobilize for 1 turn.",
	effect = { type = "trap", placement = "tile", damage = 20,
		status = { id = "Trapped", immobile = true, turns = 1 } },
})
define({
	id = "ExplosiveBarrel", name = "Explosive Barrel", rarity = "Trap", copies = 1,
	description = "Trap on tile: 25 damage, AOE in a 2-tile radius.",
	effect = { type = "trap", placement = "tile", damage = 25, aoeRadius = 2 },
})
define({
	id = "RazorWire", name = "Razor Wire", rarity = "Trap", copies = 1,
	description = "Trap on tile: 10 damage + Bleed (5 dmg over 5s).",
	effect = { type = "trap", placement = "tile", damage = 10,
		status = { id = "Bleeding", dotDamage = 1, dotInterval = 1, duration = 5 } },
})
define({
	id = "ShockMine", name = "Shock Mine", rarity = "Trap", copies = 1,
	description = "Trap on tile: 15 damage + disables 1 random card in the victim's hand.",
	effect = { type = "trap", placement = "tile", damage = 15, disableCards = 1 },
})
define({
	id = "PoisonGas", name = "Poison Gas", rarity = "Trap", copies = 1,
	description = "Trap on tile: 5 damage per second for 3 seconds, AOE.",
	effect = { type = "trap", placement = "tile", damage = 0, aoeRadius = 1,
		status = { id = "Poisoned", dotDamage = 5, dotInterval = 1, duration = 3 } },
})
define({
	id = "TarPit", name = "Tar Pit", rarity = "Trap", copies = 1,
	description = "Trap on tile: 5 damage + slow and -1 to victim's next dice roll.",
	effect = { type = "trap", placement = "tile", damage = 5,
		status = { id = "Slowed", diceModifier = -1, duration = 20 } },
})
define({
	id = "ChainSnare", name = "Chain Snare", rarity = "Trap", copies = 1,
	description = "Trap on player: 10 damage + pulls the target back 2 tiles.",
	effect = { type = "trap", placement = "player", damage = 10, pullback = 2 },
})

----------------------------------------------------------------
-- SUPPORT & BUFF CARDS (10 total)
----------------------------------------------------------------
define({
	id = "AdrenalineRush", name = "Adrenaline Rush", rarity = "Support", copies = 1,
	description = "+10% attack damage for 30s. Stacks up to 2 (2 min cooldown after stacking).",
	effect = { type = "buff", buffId = "AdrenalineRush", damagePercent = 0.10,
		duration = 30, maxStacks = 2 },
})
define({
	id = "ArmorPlating", name = "Armor Plating", rarity = "Support", copies = 1,
	description = "+10 temporary HP for 20 seconds. Does not stack.",
	effect = { type = "buff", buffId = "ArmorPlating", tempHP = 10, duration = 20 },
})
define({
	id = "NitroBoost", name = "Nitro Boost", rarity = "Support", copies = 1,
	description = "Dodge the next trap and move 2 extra tiles. One use each.",
	effect = { type = "buff", buffId = "NitroBoost", trapDodge = true, bonusMove = 2, duration = 60 },
})
define({
	id = "WarPaint", name = "War Paint", rarity = "Support", copies = 1,
	description = "+15% attack damage for 20s. Does not stack with Adrenaline Rush.",
	effect = { type = "buff", buffId = "WarPaint", damagePercent = 0.15,
		duration = 20, conflictsWith = "AdrenalineRush" },
})
define({
	id = "ScavengersLuck", name = "Scavenger's Luck", rarity = "Support", copies = 1,
	description = "Your next positive tile effect is doubled.",
	effect = { type = "buff", buffId = "ScavengersLuck", doubleTile = true, duration = 60 },
})
define({
	id = "BattleCry", name = "Battle Cry", rarity = "Support", copies = 1,
	description = "All your attacks deal +5 damage for 15 seconds.",
	effect = { type = "buff", buffId = "BattleCry", damageFlat = 5, duration = 15 },
})
define({
	id = "IronWill", name = "Iron Will", rarity = "Support", copies = 1,
	description = "Cannot be reduced below 1 HP for 10 seconds.",
	effect = { type = "buff", buffId = "IronWill", deathProof = true, duration = 10 },
})
define({
	id = "TacticalRetreat", name = "Tactical Retreat", rarity = "Support", copies = 1,
	description = "Move backward up to 3 tiles instantly. Escape danger.",
	effect = { type = "move", tiles = -3 },
})
define({
	id = "Overcharge", name = "Overcharge", rarity = "Support", copies = 1,
	description = "Your next attack deals +50% damage. Consumed on use.",
	effect = { type = "buff", buffId = "Overcharge", nextAttackPercent = 0.5, duration = 60 },
})
define({
	id = "ShieldWall", name = "Shield Wall", rarity = "Support", copies = 1,
	description = "Block the next 15 damage. Lasts until depleted.",
	effect = { type = "buff", buffId = "ShieldWall", shield = 15, duration = 120 },
})

----------------------------------------------------------------
-- RARE CARDS (10 total)
----------------------------------------------------------------
define({
	id = "SavageRampage", name = "Savage Rampage", rarity = "Rare", copies = 1,
	description = "Deal 30 damage to ALL players within 2 tiles. Auto-targets.",
	effect = { type = "aoeAttack", damage = 30, radius = 2 },
})
define({
	id = "WastelandBlessing", name = "Wasteland Blessing", rarity = "Rare", copies = 1,
	description = "Heal 50 HP.",
	effect = { type = "heal", amount = 50 },
})
define({
	id = "EMPShockwave", name = "EMP Shockwave", rarity = "Rare", copies = 1,
	description = "Disable all traps within a 3-tile radius + 20 damage to the nearest enemy.",
	effect = { type = "emp", radius = 3, damage = 20 },
})
define({
	id = "IronFortress", name = "Iron Fortress", rarity = "Rare", copies = 1,
	description = "+30 HP shield and completely block the next attack.",
	effect = { type = "buff", buffId = "IronFortress", shield = 30, blockNextAttack = true, duration = 120 },
})
define({
	id = "TimeWarpVortex", name = "Time Warp Vortex", rarity = "Rare", copies = 1,
	description = "Skip any player's next turn. Global targeting.",
	effect = { type = "skipTurn", target = "any" },
})
define({
	id = "ThunderdomeChallenge", name = "Thunderdome Challenge", rarity = "Rare", copies = 1,
	description = "Duel the nearest enemy: both take 20 damage, the player with lower HP takes 20 more.",
	effect = { type = "duel", damage = 20, loserExtra = 20 },
})
define({
	id = "ScrapTornado", name = "Scrap Tornado", rarity = "Rare", copies = 1,
	description = "Steal 2 random cards from the nearest enemy.",
	effect = { type = "steal", amount = 2, target = "nearest" },
})
define({
	id = "RoadWarriorsCharge", name = "Road Warrior's Charge", rarity = "Rare", copies = 1,
	description = "Move 5 tiles forward and deal 25 damage to anyone you pass.",
	effect = { type = "chargeMove", tiles = 5, damage = 25 },
})
define({
	id = "WastelandPlague", name = "Wasteland Plague", rarity = "Rare", copies = 1,
	description = "All enemies lose 10 HP. Global.",
	effect = { type = "globalDamage", damage = 10 },
})
define({
	id = "PhoenixFlame", name = "Phoenix Flame", rarity = "Rare", copies = 1,
	description = "If you die this turn, revive with 30 HP instead. Play preemptively.",
	effect = { type = "buff", buffId = "PhoenixFlame", revive = 30, duration = 30 },
})

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
local CardDatabase = {}

CardDatabase.Cards = Cards

function CardDatabase.get(cardId: string): Card?
	return Cards[cardId]
end

-- Returns a flat array of card ids representing the full 70-card match pool
-- (commons appear 5 times each, everything else once).
function CardDatabase.buildMatchPool(): { string }
	local pool = {}
	for id, card in Cards do
		for _ = 1, card.copies do
			table.insert(pool, id)
		end
	end
	return pool
end

-- All card ids of one rarity.
function CardDatabase.getByRarity(rarity: string): { string }
	local out = {}
	for id, card in Cards do
		if card.rarity == rarity then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

return CardDatabase
