--!strict
-- The 60-tile board layout.
-- Distribution per the design doc: 39 safe, 5 heal, 6 damage, 4 bonus card, 6 trap.
-- Heal tiles sit mostly in Zones 1-2, damage tiles escalate toward Zone 3,
-- trap tiles concentrate in Zones 2-3. Tile 60 is the finish line (instant win).

local Config = require(script.Parent.Config)

export type Tile = {
	index: number,
	type: string, -- "Safe" | "Heal" | "Damage" | "BonusCard" | "Trap" | "Finish"
	zone: number, -- 1, 2, or 3
	-- Optional effect payload
	healMin: number?,
	healMax: number?,
	damageMin: number?,
	damageMax: number?,
}

local SPECIAL_TILES: { [number]: string } = {
	-- Heal tiles (restore 10-20 HP), mostly Zones 1-2
	[5] = "Heal", [12] = "Heal", [18] = "Heal", [27] = "Heal", [38] = "Heal",
	-- Damage tiles (10-15 damage), escalating toward Zone 3
	[22] = "Damage", [31] = "Damage", [41] = "Damage",
	[48] = "Damage", [53] = "Damage", [57] = "Damage",
	-- Bonus card tiles (draw 1), scattered
	[9] = "BonusCard", [25] = "BonusCard", [36] = "BonusCard", [50] = "BonusCard",
	-- Trap tiles (a pre-placed environmental trap arms here), Zones 2-3
	[29] = "Trap", [34] = "Trap", [43] = "Trap",
	[47] = "Trap", [52] = "Trap", [56] = "Trap",
}

local function zoneOf(index: number): number
	for i, zone in Config.ZONES do
		if index >= zone.first and index <= zone.last then
			return i
		end
	end
	return #Config.ZONES
end

local Tiles: { Tile } = {}
for i = 1, Config.TOTAL_TILES do
	local tileType = SPECIAL_TILES[i] or "Safe"
	if i == Config.FINAL_TILE then
		tileType = "Finish"
	end
	local tile: Tile = {
		index = i,
		type = tileType,
		zone = zoneOf(i),
	}
	if tileType == "Heal" then
		tile.healMin, tile.healMax = 10, 20
	elseif tileType == "Damage" then
		tile.damageMin, tile.damageMax = 10, 15
	end
	Tiles[i] = tile
end

local TileDatabase = {}

TileDatabase.Tiles = Tiles

function TileDatabase.get(index: number): Tile?
	return Tiles[index]
end

function TileDatabase.zoneInfo(zoneIndex: number)
	return Config.ZONES[zoneIndex]
end

return TileDatabase
