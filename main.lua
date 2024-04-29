-- VERSION 1.0.3

---@class ModReference
local mod = RegisterMod("UniqueProgressBarIcon", 1)

if not REPENTOGON then return end

local game = Game()
local isaacIcon = Sprite("gfx/ui/coop menu.anm2")

local TRANSITION_FRAME_START = 80
local TRANSITION_FRAME_END = 140
local ICON_SPEED = 0.45
local MAP_ICON_LENGTH = 26

local firstIconPos
local iconOffset
local movingPos = 0
local currentNightmareFrame = 0
local ICON_DIRECTION = {
	FORWARD = 0,
	BACKWARD = 1,
	STILL = 2
}

local direction = ICON_DIRECTION.FORWARD
local repDirection = ICON_DIRECTION.STILL
local useRepDirection = false
local UNKNOWN_STAGE_FRAME = 17

---@type table<PlayerType, integer>
local customOffsets = {}
local currentCustomOffset = 0

---@type table<PlayerType, {Anm2: string, Animation: string}>
local customAnims = {}

UniqueProgressBarIcon = {}

---@param num string
---@param errorVar any
---@param expectedType string
---@param customMessage? string
local function UniqueProgressBarError(num, errorVar, expectedType, customMessage)
	local messageStart = "[UniqueProgressBarIcon] " ..
		"Bad Argument #" .. num .. " in UniqueProgressBarIcon.AddPlayerTypeYOffset "
	local messageAppend = customMessage ~= nil and customMessage or
		"Attempt to index a " .. type(errorVar) .. " value, field '" .. tostring(errorVar) ..
		"', expected " .. expectedType .. "."
	error(messageStart .. messageAppend)
end

---@param playerType PlayerType
local function UniqueIsaacPlayerTypeCheck(playerType)
	if not playerType
		or type(playerType) ~= "number"
	then
		UniqueProgressBarError("1", playerType, "PlayerType")
		return false
	elseif not EntityConfig.GetPlayer(playerType) then
		UniqueProgressBarError("1", playerType, "PlayerType",
			"(PlayerType is not in valid range between 0 and " .. EntityConfig:GetMaxPlayerType() .. ").")
		return false
	end
	return true
end

---Offset the Y position of an icon for a specific PlayerType.
---@param playerType PlayerType
---@param offset integer
function UniqueProgressBarIcon.AddIconYOffset(playerType, offset)
	if not UniqueIsaacPlayerTypeCheck(playerType) then return end
	if not offset
		or type(offset) ~= "number"
	then
		UniqueProgressBarError("2", offset, "number")
	end
	customOffsets[playerType] = offset
end

---Set a different icon to use for a specific PlayerType instead of their default co-op icon. Set the anm2 file it needs to play and its respective animation.
---@param playerType PlayerType
---@param anm2 string
---@param animation string
function UniqueProgressBarIcon.SetIcon(playerType, anm2, animation)
	if not UniqueIsaacPlayerTypeCheck(playerType) then return end
	if not anm2
		or type(anm2) ~= "string"
	then
		UniqueProgressBarError("2", anm2, "string")
		return
	elseif not animation
		or type(animation) ~= "string"
	then
		UniqueProgressBarError("3", animation, "string")
		return
	end
	local sprite, wasLoaded = Sprite(anm2, true)
	if not wasLoaded then
		UniqueProgressBarError("2", anm2, "string", "(Anm2 failed to load).")
	end
	sprite:Play(animation)
	if not sprite:IsPlaying(animation) then
		UniqueProgressBarError("3", animation, "string", "(Animation name is invalid).")
	end
	customAnims[playerType] = { Anm2 = anm2, Animation = animation }
end

---Reset the icon set by UniqueProgressBarIcon.SetIcon()
---@param playerType PlayerType
function UniqueProgressBarIcon.ResetIcon(playerType)
	if not UniqueIsaacPlayerTypeCheck(playerType) then return end
	customAnims[playerType] = nil
end

local function isTransitioningToSameFloorRepAlt(currentStage, nextStage, currentStageType, nextStageType)
	if currentStage ~= nextStage or currentStage > LevelStage.STAGE3_2 then return false end

	if currentStageType < StageType.STAGETYPE_REPENTANCE
		and nextStageType >= StageType.STAGETYPE_REPENTANCE
	then
		repDirection = ICON_DIRECTION.FORWARD
		return true
	elseif currentStageType >= StageType.STAGETYPE_REPENTANCE
		and nextStageType < StageType.STAGETYPE_REPENTANCE
	then
		repDirection = ICON_DIRECTION.BACKWARD
		return true
	end
end

---@param nextStage LevelStage
---@param nextStageType StageType
function mod:OnLevelSelect(nextStage, nextStageType)
	local currentStage = game:GetLevel():GetStage()
	local currentStageType = game:GetLevel():GetStageType()
	if isTransitioningToSameFloorRepAlt(currentStage, nextStage, currentStageType, nextStageType) then
		useRepDirection = true
	else
		useRepDirection = false
	end
	if currentStage < nextStage then
		direction = ICON_DIRECTION.FORWARD
	elseif currentStage > nextStage then
		direction = ICON_DIRECTION.BACKWARD
	elseif currentStage == nextStage then
		direction = ICON_DIRECTION.STILL
	end
end

--Set to IMPORTANT as this callback ignores if you set a stage behind or as the same as current stage, always moving forwards instead.
--Don't want the icon check to be altered by other mods altering it.
mod:AddPriorityCallback(ModCallbacks.MC_PRE_LEVEL_SELECT, CallbackPriority.IMPORTANT, mod.OnLevelSelect)

function mod:CalculateProgressBarLength()
	local levelEnd = game:GetLevel():GetStage()
	local totalLength
	local barLength
	if useRepDirection then
		direction = repDirection
		if direction == ICON_DIRECTION.FORWARD then
			levelEnd = levelEnd + 1
		elseif direction == ICON_DIRECTION.BACKWARD then
			levelEnd = levelEnd - 1
		end
	elseif game:GetLevel():GetStageType() >= StageType.STAGETYPE_REPENTANCE then
		levelEnd = levelEnd + 1
	end
	local levelStart = levelEnd - 1
	if direction == ICON_DIRECTION.BACKWARD then
		levelStart = levelEnd + 1
	elseif direction == ICON_DIRECTION.STILL then
		levelStart = levelEnd
	end
	if game:IsGreedMode() then             --Greed Mode's stage length never changes
		barLength = 7
	elseif levelEnd == LevelStage.STAGE8 then --Home
		levelStart = 2
		levelEnd = 1
		barLength = 1
		direction = ICON_DIRECTION.BACKWARD
	elseif game:GetChallengeParams():GetEndStage() == LevelStage.STAGE3_2 or not Isaac.GetPersistentGameData():Unlocked(Achievement.WOMB) then
		barLength = 6
	else
		barLength = 8
		local progressBar = NightmareScene.GetProgressBarMap()
		for levelStage = LevelStage.STAGE4_2, LevelStage.STAGE7 do
			local frame = progressBar[levelStage + 1]
			if levelEnd >= levelStage then
				if levelStage == LevelStage.STAGE4_2 and frame == 25 then
					barLength = barLength + 1
				elseif levelStage == LevelStage.STAGE4_3 and frame == UNKNOWN_STAGE_FRAME then
					levelStart = levelStart - 1
				elseif levelStage >= LevelStage.STAGE4_3 then
					barLength = barLength + 1
				end
			end
		end
	end

	totalLength = MAP_ICON_LENGTH * barLength + (barLength - 1) --Icons are separated by 1 pixel
	firstIconPos = (totalLength - MAP_ICON_LENGTH) / 2
	iconOffset = MAP_ICON_LENGTH * (levelStart - 1) + (levelStart - 1)
	iconOffset = direction == ICON_DIRECTION.BACKWARD and iconOffset or iconOffset - 1
	movingPos = 0
end

function mod:OnNightmareShow()
	if NightmareScene.IsDogmaNightmare() then return end
	currentNightmareFrame = 0
	self:CalculateProgressBarLength()
end

mod:AddCallback(ModCallbacks.MC_POST_NIGHTMARE_SCENE_SHOW, mod.OnNightmareShow)

function mod:OnNightmareRender()
	if NightmareScene.IsDogmaNightmare() then return end
	local progressSprite = NightmareScene.GetProgressBarSprite()
	local animData = progressSprite:GetCurrentAnimationData()
	local layerData = animData:GetLayer(0)
	if not layerData then return end
	local frameData = layerData:GetFrame(progressSprite:GetFrame())
	if not frameData then return end
	if currentNightmareFrame == 0 then
		local playerType = Isaac.GetPlayer():GetPlayerType()
		if customOffsets[playerType] then
			currentCustomOffset = customOffsets[playerType]
		else
			currentCustomOffset = 0
		end
		if customAnims[playerType] then
			local customAnimation = customAnims[playerType]
			isaacIcon:Load(customAnimation.Anm2, true)
			isaacIcon:Play(customAnimation.Animation, true)
		elseif playerType >= PlayerType.PLAYER_ISAAC and playerType < PlayerType.NUM_PLAYER_TYPES then
			isaacIcon:Load("gfx/ui/coop menu.anm2", true)
			isaacIcon:SetFrame("Main", playerType + 1)
		else
			local coopSprite = EntityConfig.GetPlayer(playerType):GetModdedCoopMenuSprite()
			if coopSprite then
				isaacIcon:Load(coopSprite:GetFilename(), true)
				isaacIcon:SetFrame(Isaac.GetPlayer():GetName(), 0)
			else
				isaacIcon:Load("gfx/ui/coop menu.anm2", true)
				isaacIcon:SetFrame("Main", 1)
			end
		end
	end
	isaacIcon.Scale = frameData:GetScale()
	isaacIcon.Offset = frameData:GetPos()
	currentNightmareFrame = currentNightmareFrame + 1
	if currentNightmareFrame >= TRANSITION_FRAME_START and currentNightmareFrame <= TRANSITION_FRAME_END then
		if direction == ICON_DIRECTION.FORWARD then
			movingPos = movingPos + ICON_SPEED
		elseif direction == ICON_DIRECTION.BACKWARD then
			movingPos = movingPos - ICON_SPEED
		end
	end
	isaacIcon:RenderLayer(0,
		Vector((Isaac.GetScreenWidth() / 2) - firstIconPos + iconOffset + movingPos, 20 + currentCustomOffset))
	if Isaac.GetFrameCount() % 2 == 0 then
		isaacIcon:Update()
	end
end

mod:AddCallback(ModCallbacks.MC_POST_NIGHTMARE_SCENE_RENDER, mod.OnNightmareRender)

return mod
