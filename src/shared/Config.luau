--!strict
-- Global game configuration for Mad Max: Wasteland Brawl.
-- All tunable numbers live here so balance changes never require touching logic.

local Config = {
	-- Match
	MATCH_DURATION = 360, -- 6 minutes
	MAX_PLAYERS = 16,
	MIN_PLAYERS_TO_START = 2,
	INTERMISSION_TIME = 15,

	-- Player
	STARTING_HP = 100,
	HAND_LIMIT = 10,
	STARTING_HAND_SIZE = 10, -- 3 drafted + 7 random

	-- Board
	TOTAL_TILES = 60,
	FINAL_TILE = 60,

	-- Zones (inclusive tile ranges)
	ZONES = {
		{ name = "Wasteland Desert", first = 1, last = 20, danger = "Low" },
		{ name = "Scrapyard Industrial", first = 21, last = 45, danger = "Medium" },
		{ name = "Thunderdome Arena", first = 46, last = 60, danger = "High" },
	},

	-- Turn system
	GROUP_COUNT = 4,
	PHASE_TIMES = {
		Roll = 2,
		Movement = 3,
		TileEffect = 2,
		Action = 10,
		Resolution = 3,
	},
	REACTION_WINDOW = 1, -- seconds to play a counter card

	-- Dice
	DICE_MIN = 1,
	DICE_MAX = 6,

	-- Draft
	DRAFT_POOL_SIZE = 15,
	DRAFT_PICKS = 3,
	DRAFT_PICK_TIME = 10,
	DRAFT_RANDOM_FILL = 7,
	DRAFT_WEIGHTS = {
		Common = 50,
		Uncommon = 25,
		Trap = 10,
		Support = 10,
		Rare = 5,
	},

	-- Buffs
	MAX_ACTIVE_BUFFS = 2,
	ADRENALINE_MAX_STACKS = 2,
	STACKED_BUFF_COOLDOWN = 120,

	-- Economy (Scrap awarded even in MVP so data is ready for Phase 3)
	SCRAP_PER_KILL = 25,
	SCRAP_MATCH_MIN = 50,
	SCRAP_MATCH_MAX = 100,
	SCRAP_PER_BURNED_CARD = 5,
	SCRAP_CHEER_BONUS = 10, -- Scrap the cheering spectator earns
	SCRAP_CHEER_TARGET_BONUS = 5, -- Scrap the cheered player earns

	-- Board build (visual layout: snake pattern)
	TILES_PER_ROW = 10,
	TILE_SIZE = 12, -- studs, square tiles
	TILE_GAP = 2,
	TILE_HEIGHT = 1,

	-- Spectator: Chaos Mode voting
	CHAOS_VOTE_INTERVAL = 60, -- seconds between votes
	CHAOS_VOTE_DURATION = 15, -- seconds spectators have to vote
	CHAOS_OPTIONS_SHOWN = 3, -- options offered per vote
	CHEER_COOLDOWN = 5, -- seconds between cheers from the same spectator
}

return Config
