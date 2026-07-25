--!strict
-- Sound asset IDs for Mad Max: Wasteland Brawl.
--
-- These are left as placeholders (0) rather than guessed catalog IDs — a
-- fabricated rbxassetid would either fail to load or play the wrong sound,
-- and neither is verifiable from outside Roblox Studio. Per the design
-- doc's own Art Style Notes ("avoid Blender, use Roblox's free toolbox
-- assets"), fill these in from the Studio Toolbox: Home tab > Toolbox >
-- Audio, search the suggested term, right-click a result > Copy Asset ID,
-- and paste the number here. Effects.luau silently skips playing any
-- sound still set to 0, so the game runs fine before you fill these in.

export type SoundSpec = { id: number, volume: number, searchTerm: string }

local SoundIds: { [string]: SoundSpec } = {
	DiceRoll = { id = 0, volume = 0.5, searchTerm = "dice roll" },
	CardPlay = { id = 0, volume = 0.4, searchTerm = "card flip" },
	AttackHit = { id = 0, volume = 0.6, searchTerm = "punch impact" },
	Heal = { id = 0, volume = 0.5, searchTerm = "heal chime" },
	Counter = { id = 0, volume = 0.6, searchTerm = "metal clang" },
	Dodge = { id = 0, volume = 0.4, searchTerm = "whoosh" },
	TrapTrigger = { id = 0, volume = 0.6, searchTerm = "explosion small" },
	Explosion = { id = 0, volume = 0.8, searchTerm = "explosion large" },
	Death = { id = 0, volume = 0.6, searchTerm = "death groan" },
	Victory = { id = 0, volume = 0.7, searchTerm = "victory fanfare" },
	ChaosVote = { id = 0, volume = 0.5, searchTerm = "alarm siren short" },
	Cheer = { id = 0, volume = 0.4, searchTerm = "crowd cheer" },
	ButtonClick = { id = 0, volume = 0.3, searchTerm = "ui click" },
}

return SoundIds
