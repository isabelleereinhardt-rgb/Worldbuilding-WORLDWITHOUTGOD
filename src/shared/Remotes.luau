--!strict
-- Central registry of RemoteEvents/RemoteFunctions.
-- Server calls Remotes.init() once; clients call Remotes.get() and wait.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENT_NAMES = {
	-- Server -> Client
	"GameStateChanged",   -- (state: string, data: table?)
	"MatchTimerUpdate",   -- (timeLeft: number, alivePlayers: number)
	"DraftPoolUpdate",    -- (pool: {cardId}, pickNumber: number, timeLeft: number)
	"HandUpdate",         -- (hand: {cardId}, disabled: {index: boolean}?)
	"PlayerStatsUpdate",  -- (statsByUserId: {[userId]: {hp, maxHp, cards, tile, alive, kills, statuses}})
	"TurnPhaseUpdate",    -- (groupIndex: number, phase: string, timeLeft: number, myTurn: boolean)
	"DiceRolled",         -- (userId: number, roll: number)
	"PlayerMoved",        -- (userId: number, fromTile: number, toTile: number, path: {number})
	"TileEffectTriggered",-- (userId: number, tileIndex: number, effectType: string, value: number?)
	"CardPlayed",         -- (userId: number, cardId: string, targetUserId: number?)
	"ReactionWindow",     -- (attackerUserId: number, cardId: string, deadline: number)
	"CombatResult",       -- (info: table)
	"TrapPlaced",         -- (tileIndex: number?, targetUserId: number?, cardId: string, ownerUserId: number)
	"TrapTriggered",      -- (tileIndex: number?, victimUserId: number, cardId: string)
	"PlayerDied",         -- (victimUserId: number, killerUserId: number?)
	"MatchEnded",         -- (results: {winnerUserId, reason, scoreboard, crowdFavorite})
	"ActionFeed",         -- (message: string)

	-- Spectator: Server -> Client
	"ChaosVoteOptions",   -- (options: {id, label}[], timeLeft: number)
	"ChaosVoteResult",    -- (eventId: string, label: string, voteCounts: {[id]: number})
	"ChaosModifiersUpdate", -- (modifiers: {id, label, timeLeft}[])
	"CosmeticChaosTriggered", -- (userId: number) -- purely visual, spectator-triggered
	"MVPVoteUpdate",      -- (voteCounts: {[userId]: number})

	-- Client -> Server
	"RequestDraftPick",   -- (cardId: string)
	"RequestPlayCard",    -- (handIndex: number, targetUserId: number?, tileIndex: number?)
	"RequestReaction",    -- (handIndex: number)
	"RequestBranchChoice",-- (choice: string)  reserved for branching paths

	-- Spectator: Client -> Server
	"RequestChaosVote",   -- (eventId: string)
	"RequestCheer",       -- (targetUserId: number)
	"RequestMVPVote",     -- (targetUserId: number)
	"RequestCosmeticChaos", -- () -- dead players only, cooldown enforced server-side
}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
		if not folder then
			local newFolder = Instance.new("Folder")
			newFolder.Name = "Remotes"
			newFolder.Parent = ReplicatedStorage
			folder = newFolder
		end
		return folder :: Folder
	else
		return ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
end

-- Server-side: create every remote up front.
function Remotes.init()
	local folder = getFolder()
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		assert(remote, `Remote "{name}" does not exist — did you call Remotes.init()?`)
		return remote :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
