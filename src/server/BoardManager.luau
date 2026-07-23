--!strict
-- Builds the physical 60-tile snake board in Workspace and handles
-- movement + tile effects. Tiles are colored by type, zones by theme.
-- Board logic lives in TileDatabase; the parts here are just visuals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local TileDatabase = require(Shared.TileDatabase)
local Remotes = require(Shared.Remotes)
local PlayerDataManager = require(script.Parent.PlayerDataManager)

type PlayerState = PlayerDataManager.PlayerState

local BoardManager = {}

-- Traps placed by cards during the match: tileIndex -> {cardId, ownerUserId}
local placedTraps: { [number]: { cardId: string, ownerUserId: number } } = {}
-- Pre-placed environmental traps on "Trap" tiles are armed at match start
local armedTiles: { [number]: boolean } = {}

local tileParts: { [number]: BasePart } = {}
local boardFolder: Folder? = nil

-- Injected by init.server to avoid circular requires
local deps: {
	applyDamage: (PlayerState, number, PlayerState?) -> (),
	executeTrapCard: (string, PlayerState, number) -> (),
	drawCards: (PlayerState, number) -> (),
}? = nil

function BoardManager.inject(d)
	deps = d
end

----------------------------------------------------------------
-- Zone theming
----------------------------------------------------------------
local ZONE_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(216, 176, 121), -- sandy desert
	[2] = Color3.fromRGB(126, 118, 110), -- industrial gray-brown
	[3] = Color3.fromRGB(94, 53, 45),    -- scorched arena red
}

local TILE_TYPE_COLORS: { [string]: Color3 } = {
	Heal = Color3.fromRGB(88, 175, 92),
	Damage = Color3.fromRGB(196, 74, 62),
	BonusCard = Color3.fromRGB(92, 140, 210),
	Trap = Color3.fromRGB(180, 120, 40),
	Finish = Color3.fromRGB(240, 200, 60),
}

----------------------------------------------------------------
-- Board construction (snake layout)
----------------------------------------------------------------

-- World position of tile i in a snake pattern: rows alternate direction.
local function tilePosition(index: number): Vector3
	local perRow = Config.TILES_PER_ROW
	local pitch = Config.TILE_SIZE + Config.TILE_GAP
	local row = math.floor((index - 1) / perRow)
	local col = (index - 1) % perRow
	if row % 2 == 1 then
		col = perRow - 1 - col -- reverse odd rows for the snake
	end
	return Vector3.new(col * pitch, Config.TILE_HEIGHT / 2, row * pitch)
end

function BoardManager.buildBoard()
	if boardFolder then
		boardFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "GameBoard"
	folder.Parent = workspace
	boardFolder = folder
	table.clear(tileParts)

	for _, tile in TileDatabase.Tiles do
		local part = Instance.new("Part")
		part.Name = `Tile_{tile.index}`
		part.Size = Vector3.new(Config.TILE_SIZE, Config.TILE_HEIGHT, Config.TILE_SIZE)
		part.Position = tilePosition(tile.index)
		part.Anchored = true
		part.Material = tile.zone == 1 and Enum.Material.Sand
			or tile.zone == 2 and Enum.Material.CorrodedMetal
			or Enum.Material.Basalt
		part.Color = TILE_TYPE_COLORS[tile.type] or ZONE_COLORS[tile.zone]
		part.Parent = folder

		local label = Instance.new("SurfaceGui")
		label.Face = Enum.NormalId.Top
		label.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		label.PixelsPerStud = 20
		label.Parent = part

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.SourceSansBold
		text.TextScaled = true
		text.TextColor3 = Color3.new(0, 0, 0)
		text.TextTransparency = 0.4
		text.Text = tile.type == "Finish" and "🏁 " .. tile.index or tostring(tile.index)
		text.Parent = label

		tileParts[tile.index] = part
	end

	-- Spawn platform behind tile 1
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "BoardSpawn"
	spawnPad.Size = Vector3.new(Config.TILE_SIZE * 3, 1, Config.TILE_SIZE)
	spawnPad.Position = tilePosition(1) - Vector3.new(0, 0, Config.TILE_SIZE + Config.TILE_GAP)
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Color = Color3.fromRGB(60, 60, 60)
	spawnPad.Parent = folder
end

function BoardManager.getTilePart(index: number): BasePart?
	return tileParts[index]
end

function BoardManager.getTileWorldPosition(index: number): Vector3
	local part = tileParts[index]
	if part then
		return part.Position + Vector3.new(0, 3, 0)
	end
	return tilePosition(index) + Vector3.new(0, 3, 0)
end

----------------------------------------------------------------
-- Trap placement (card-placed and environmental)
----------------------------------------------------------------

function BoardManager.resetTraps()
	table.clear(placedTraps)
	table.clear(armedTiles)
	for _, tile in TileDatabase.Tiles do
		if tile.type == "Trap" then
			armedTiles[tile.index] = true
		end
	end
end

function BoardManager.placeTrap(tileIndex: number, cardId: string, ownerUserId: number): boolean
	if placedTraps[tileIndex] then
		return false
	end
	placedTraps[tileIndex] = { cardId = cardId, ownerUserId = ownerUserId }
	Remotes.get("TrapPlaced"):FireAllClients(tileIndex, nil, cardId, ownerUserId)

	-- Visible trap marker (design doc: no hidden traps)
	local part = tileParts[tileIndex]
	if part then
		local marker = Instance.new("BillboardGui")
		marker.Name = "TrapMarker"
		marker.Size = UDim2.fromOffset(40, 40)
		marker.StudsOffset = Vector3.new(0, 3, 0)
		marker.AlwaysOnTop = true
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.fromScale(1, 1)
		icon.BackgroundTransparency = 1
		icon.Text = "🪤"
		icon.TextScaled = true
		icon.Parent = marker
		marker.Parent = part
	end
	return true
end

function BoardManager.removeTrap(tileIndex: number)
	placedTraps[tileIndex] = nil
	armedTiles[tileIndex] = nil
	local part = tileParts[tileIndex]
	if part then
		local marker = part:FindFirstChild("TrapMarker")
		if marker then
			marker:Destroy()
		end
	end
end

-- EMP Shockwave: disable all traps within a tile radius.
function BoardManager.disableTrapsInRadius(centerTile: number, radius: number): number
	local removed = 0
	for tileIndex in placedTraps do
		if math.abs(tileIndex - centerTile) <= radius then
			BoardManager.removeTrap(tileIndex)
			removed += 1
		end
	end
	for tileIndex in armedTiles do
		if math.abs(tileIndex - centerTile) <= radius then
			armedTiles[tileIndex] = nil
			removed += 1
		end
	end
	return removed
end

----------------------------------------------------------------
-- Movement
----------------------------------------------------------------

-- Walk a player token tile-by-tile. Returns the path travelled.
function BoardManager.movePlayer(state: PlayerState, tiles: number): { number }
	local from = state.tile
	local target = math.clamp(from + tiles, 1, Config.FINAL_TILE)
	local path = {}
	local step = target >= from and 1 or -1
	local current = from
	while current ~= target do
		current += step
		table.insert(path, current)
	end
	state.tile = target

	Remotes.get("PlayerMoved"):FireAllClients(state.userId, from, target, path)

	-- Physically walk the character along the path
	local character = state.player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		task.spawn(function()
			for _, tileIndex in path do
				local tween = TweenService:Create(
					hrp,
					TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.new(BoardManager.getTileWorldPosition(tileIndex)) }
				)
				tween:Play()
				tween.Completed:Wait()
			end
		end)
	end
	return path
end

function BoardManager.teleportToTile(state: PlayerState, tileIndex: number)
	state.tile = math.clamp(tileIndex, 1, Config.FINAL_TILE)
	local character = state.player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = CFrame.new(BoardManager.getTileWorldPosition(state.tile))
	end
end

----------------------------------------------------------------
-- Tile effects
----------------------------------------------------------------

-- Runs when a player ends their movement on a tile.
function BoardManager.applyTileEffect(state: PlayerState)
	assert(deps, "BoardManager.inject not called")
	local tile = TileDatabase.get(state.tile)
	if not tile then
		return
	end

	local luck = PlayerDataManager.getBuff(state, "ScavengersLuck")
	local multiplier = 1
	if luck and (tile.type == "Heal" or tile.type == "BonusCard") then
		multiplier = 2
		PlayerDataManager.removeBuff(state, "ScavengersLuck")
	end

	-- Card-placed trap takes priority, then environmental trap tile
	local placed = placedTraps[state.tile]
	if placed then
		local nitro = PlayerDataManager.getBuff(state, "NitroBoost")
		if nitro and nitro.trapDodge then
			nitro.trapDodge = nil
			Remotes.get("ActionFeed"):FireAllClients(`{state.player.Name} nitro-dodged a trap!`)
		else
			local trapTile = state.tile
			BoardManager.removeTrap(trapTile)
			Remotes.get("TrapTriggered"):FireAllClients(trapTile, state.userId, placed.cardId)
			-- 1-second visible delay before the trap fires (design doc)
			task.delay(1, function()
				if state.alive then
					deps.executeTrapCard(placed.cardId, state, trapTile)
				end
			end)
		end
		return
	end

	if tile.type == "Heal" then
		local amount = math.random(tile.healMin :: number, tile.healMax :: number) * multiplier
		state.hp = math.min(state.hp + amount, state.maxHp)
		Remotes.get("TileEffectTriggered"):FireAllClients(state.userId, tile.index, "Heal", amount)
	elseif tile.type == "Damage" then
		local amount = math.random(tile.damageMin :: number, tile.damageMax :: number)
		deps.applyDamage(state, amount, nil)
		Remotes.get("TileEffectTriggered"):FireAllClients(state.userId, tile.index, "Damage", amount)
	elseif tile.type == "BonusCard" then
		deps.drawCards(state, 1 * multiplier)
		Remotes.get("TileEffectTriggered"):FireAllClients(state.userId, tile.index, "BonusCard", multiplier)
	elseif tile.type == "Trap" and armedTiles[tile.index] then
		local nitro = PlayerDataManager.getBuff(state, "NitroBoost")
		if nitro and nitro.trapDodge then
			nitro.trapDodge = nil
			Remotes.get("ActionFeed"):FireAllClients(`{state.player.Name} nitro-dodged a trap!`)
		else
			armedTiles[tile.index] = nil
			local damage = math.random(10, 20)
			Remotes.get("TrapTriggered"):FireAllClients(tile.index, state.userId, "Environmental")
			task.delay(1, function()
				if state.alive then
					deps.applyDamage(state, damage, nil)
				end
			end)
		end
	end
end

return BoardManager
