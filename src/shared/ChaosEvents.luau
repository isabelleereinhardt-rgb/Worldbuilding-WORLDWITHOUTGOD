--!strict
-- Chaos Mode vote options, straight from the design doc's spectator section.
-- Two kinds:
--   "modifier" events set a timed global multiplier that other systems read
--   (ChaosManager.getTrapDamageMultiplier/getHealMultiplier/getMovementBonus).
--   "oneShot" events fire once immediately when the vote resolves.

export type ChaosEvent = {
	id: string,
	label: string,
	kind: "modifier" | "oneShot",
	duration: number?, -- seconds, for "modifier" events
	trapDamageMultiplier: number?,
	healMultiplier: number?,
	movementBonus: number?,
}

local ChaosEvents: { [string]: ChaosEvent } = {
	DoubleTrapDamage = {
		id = "DoubleTrapDamage",
		label = "All traps deal double damage for 30 seconds",
		kind = "modifier",
		duration = 30,
		trapDamageMultiplier = 2,
	},
	ExtraCard = {
		id = "ExtraCard",
		label = "Everyone draws 1 extra card",
		kind = "oneShot",
	},
	MovementBoost = {
		id = "MovementBoost",
		label = "All movement +2 tiles this round",
		kind = "modifier",
		duration = 30,
		movementBonus = 2,
	},
	ReducedHealing = {
		id = "ReducedHealing",
		label = "Healing effects reduced by 50%",
		kind = "modifier",
		duration = 30,
		healMultiplier = 0.5,
	},
	RandomRareCard = {
		id = "RandomRareCard",
		label = "A random player gets a Rare card",
		kind = "oneShot",
	},
}

local ChaosEventsModule = {}

ChaosEventsModule.Events = ChaosEvents

function ChaosEventsModule.get(id: string): ChaosEvent?
	return ChaosEvents[id]
end

function ChaosEventsModule.getAllIds(): { string }
	local ids = {}
	for id in ChaosEvents do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return ChaosEventsModule
