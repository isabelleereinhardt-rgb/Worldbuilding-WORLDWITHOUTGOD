--!strict
-- Card feel: hit flashes, particle bursts, screen shake, and sound triggers.
-- Every function is self-contained and cleans up after itself (Debris-style
-- task.delay + Destroy), so callers just fire-and-forget.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundIds = require(Shared.SoundIds)

local CameraController = require(script.Parent.CameraController)

local Effects = {}

----------------------------------------------------------------
-- Sound
----------------------------------------------------------------

function Effects.playSound(name: string)
	local spec = SoundIds[name]
	if not spec or spec.id == 0 then
		return -- no asset filled in yet; see src/shared/SoundIds.luau
	end
	local sound = Instance.new("Sound")
	sound.SoundId = `rbxassetid://{spec.id}`
	sound.Volume = spec.volume
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 5)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function characterOf(userId: number): Model?
	local player = Players:GetPlayerByUserId(userId)
	return player and player.Character
end

local function rootOf(userId: number): BasePart?
	local character = characterOf(userId)
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- A short-lived ParticleEmitter burst at a world position.
local function burst(position: Vector3, color: Color3, count: number, spread: number, lifetime: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(0.6, 0.1)
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(spread * 0.5, spread)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)

	Debris:AddItem(anchor, lifetime + 0.5)
end

-- A brief red/green tint flash on a character's parts (damage/heal feedback).
local function flashCharacter(character: Model, color: Color3, duration: number)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local originalColor = part.Color
			part.Color = color
			local tween = TweenService:Create(part, TweenInfo.new(duration), { Color = originalColor })
			tween:Play()
		end
	end
end

----------------------------------------------------------------
-- Public triggers (called from init.client.luau event handlers)
----------------------------------------------------------------

function Effects.diceRolled()
	Effects.playSound("DiceRoll")
end

function Effects.cardPlayed()
	Effects.playSound("CardPlay")
end

-- A landed attack: hit flash + burst on the defender, screen shake if it's you.
function Effects.attackHit(defenderUserId: number, damage: number)
	Effects.playSound("AttackHit")
	local character = characterOf(defenderUserId)
	local root = rootOf(defenderUserId)
	if character then
		flashCharacter(character, Color3.fromRGB(220, 50, 40), 0.25)
	end
	if root then
		burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(200, 60, 30), 14, 8, 0.5)
	end
	if defenderUserId == Players.LocalPlayer.UserId then
		CameraController.shake(math.clamp(damage / 8, 1, 6), 0.3)
	end
end

function Effects.healed(userId: number)
	Effects.playSound("Heal")
	local character = characterOf(userId)
	local root = rootOf(userId)
	if character then
		flashCharacter(character, Color3.fromRGB(90, 220, 100), 0.3)
	end
	if root then
		burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(90, 220, 100), 12, 6, 0.6)
	end
end

function Effects.countered(userId: number)
	Effects.playSound("Counter")
	local root = rootOf(userId)
	if root then
		burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(240, 200, 60), 10, 7, 0.4)
	end
end

function Effects.dodged(_userId: number)
	Effects.playSound("Dodge")
end

function Effects.trapTriggered(position: Vector3)
	Effects.playSound("TrapTrigger")
	burst(position + Vector3.new(0, 1.5, 0), Color3.fromRGB(200, 120, 30), 20, 10, 0.6)
	if Players.LocalPlayer.Character then
		local myRoot = Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if myRoot and (myRoot.Position - position).Magnitude < 30 then
			CameraController.shake(3, 0.35)
		end
	end
end

function Effects.aoeExplosion(position: Vector3)
	Effects.playSound("Explosion")
	burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(230, 90, 30), 30, 14, 0.8)
	if Players.LocalPlayer.Character then
		local myRoot = Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if myRoot and (myRoot.Position - position).Magnitude < 40 then
			CameraController.shake(5, 0.5)
		end
	end
end

function Effects.playerDied(userId: number)
	Effects.playSound("Death")
	local root = rootOf(userId)
	if root then
		burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(120, 120, 120), 18, 9, 1)
	end
	if userId == Players.LocalPlayer.UserId then
		CameraController.shake(6, 0.6)
	end
end

function Effects.victory()
	Effects.playSound("Victory")
end

function Effects.chaosVoteOpened()
	Effects.playSound("ChaosVote")
end

function Effects.cheered()
	Effects.playSound("Cheer")
end

function Effects.buttonClick()
	Effects.playSound("ButtonClick")
end

-- Cosmetic-only burst a dead spectator triggered for fun (no gameplay effect).
function Effects.cosmeticChaos(userId: number)
	local root = rootOf(userId)
	local position = root and root.Position or Vector3.new(0, 10, 0)
	local colors = {
		Color3.fromRGB(240, 200, 60), Color3.fromRGB(90, 220, 100),
		Color3.fromRGB(90, 160, 220), Color3.fromRGB(220, 90, 200),
	}
	burst(position + Vector3.new(0, 4, 0), colors[math.random(#colors)], 40, 16, 1.2)
end

return Effects
