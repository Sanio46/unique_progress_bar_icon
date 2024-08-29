-- VERSION 1.1

---@class ModReference
local mod = RegisterMod("UniqueProgressBarIcon", 1)

if not REPENTOGON then return end

local game = Game()
local isaacIcon = Sprite("gfx/ui/coop menu.anm2")

local TRANSITION_FRAME_START = 80
local TRANSITION_FRAME_END = 140
local ICON_SPEED = 0.45
local MAP_ICON_LENGTH = 26

local firstIconPos = 0
local iconOffset = 0
local movingPos = 0
local currentNightmareFrame = 0
local renderLayer = 0
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
local customBlacklist = {}

---@type table<PlayerType, {Anm2: string, Animation: string}>
local customAnims = {
	[PlayerType.PLAYER_LAZARUS2] = { Anm2 = "gfx/ui/coop_lazarus_b.anm2", Animation = "Normal" },
	[PlayerType.PLAYER_LAZARUS2_B] = { Anm2 = "gfx/ui/coop_lazarus_b.anm2", Animation = "Tainted" }
}

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

---If you want to do your own thing. Sets whether the icon will be rendered or not.
---@param playerType PlayerType
---@param bool boolean True to stop rendering, false to render as normal again.
function UniqueProgressBarIcon.StopPlayerTypeRender(playerType, bool)
	customBlacklist[playerType] = bool
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
	currentNightmareFrame = 0
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
	local endPos = levelEnd
	local totalLength
	local barLength
	if useRepDirection then
		direction = repDirection
		if direction == ICON_DIRECTION.FORWARD then
			endPos = endPos + 1
		elseif direction == ICON_DIRECTION.BACKWARD then
			endPos = endPos - 1
		end
	elseif game:GetLevel():GetStageType() >= StageType.STAGETYPE_REPENTANCE then
		endPos = endPos + 1
	end
	local startPos = endPos - 1
	if direction == ICON_DIRECTION.BACKWARD then
		startPos = endPos + 1
	elseif direction == ICON_DIRECTION.STILL then
		startPos = endPos
	end
	if game:IsGreedMode() then             --Greed Mode's stage length never changes
		barLength = 7
	elseif levelEnd == LevelStage.STAGE8 then --Home
		startPos = 2
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
					startPos = startPos - 1
				elseif levelStage >= LevelStage.STAGE4_3 then
					barLength = barLength + 1
				end
			end
		end
	end
	totalLength = MAP_ICON_LENGTH * barLength + (barLength - 1) --Icons are separated by 1 pixel
	firstIconPos = (totalLength - MAP_ICON_LENGTH) / 2
	iconOffset = MAP_ICON_LENGTH * (startPos - 1) + (startPos - 1)
	movingPos = 0
end

function mod:OnNightmareShow()
	if NightmareScene.IsDogmaNightmare() then return end
	currentNightmareFrame = 0
	self:CalculateProgressBarLength()
end

mod:AddCallback(ModCallbacks.MC_POST_NIGHTMARE_SCENE_SHOW, mod.OnNightmareShow)

local function resetIsaacIcon()
	isaacIcon:Load("gfx/ui/coop menu.anm2", true)
	isaacIcon:SetFrame("Main", 1)
end

local function loadIsaacIcon()
	renderLayer = 0
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
			if not isaacIcon:IsLoaded() then
				resetIsaacIcon()
			else
				isaacIcon:SetFrame(Isaac.GetPlayer():GetName(), 0)
				if isaacIcon:GetAnimation() ~= Isaac.GetPlayer():GetName() then
					resetIsaacIcon()
				else
					local iconAnimData = isaacIcon:GetCurrentAnimationData()
					if not iconAnimData:GetLayer(0):GetFrame(0) then
						local foundFrame = false
						for _, iconLayerData in ipairs(iconAnimData:GetAllLayers()) do
							if iconLayerData:GetFrame(0) then
								renderLayer = iconLayerData:GetLayerID()
								foundFrame = true
								break
							end
						end
						if not foundFrame then
							resetIsaacIcon()
						end
					end
				end
			end
		else
			resetIsaacIcon()
		end
	end
end

function mod:OnNightmareRender()
	if NightmareScene.IsDogmaNightmare() then return end
	local progressSprite = NightmareScene.GetProgressBarSprite()
	local animData = progressSprite:GetCurrentAnimationData()
	local layerData = animData:GetLayer(0)
	if not layerData then return end
	local frameData = layerData:GetFrame(progressSprite:GetFrame())
	if not frameData then return end
	local playerType = Isaac.GetPlayer():GetPlayerType()
	if currentNightmareFrame == 0 then
		loadIsaacIcon()
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
	if not customBlacklist[playerType] then
		isaacIcon:RenderLayer(renderLayer,
			Vector((Isaac.GetScreenWidth() / 2) - firstIconPos + iconOffset + movingPos, 20 + currentCustomOffset))
	end
	if Isaac.GetFrameCount() % 2 == 0 then
		isaacIcon:Update()
	end
end

mod:AddCallback(ModCallbacks.MC_POST_NIGHTMARE_SCENE_RENDER, mod.OnNightmareRender)

if currentNightmareFrame > 0 then
	currentNightmareFrame = 0
end

function mod:TestCoopIcon()
	if currentNightmareFrame == 0 then
		loadIsaacIcon()
		currentNightmareFrame = 1
	end
	local center = Vector(Isaac.GetScreenWidth() / 2, (Isaac.GetScreenHeight() / 2))
	isaacIcon:RenderLayer(renderLayer, center)
	Isaac.RenderText(isaacIcon:GetAnimation(), center.X - 20, center.Y + 10, 1, 1, 1, 1)
end

--mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.TestCoopIcon)

local loadedIconForStageAPI = false

function mod:RenderForStageAPI(name)
	if not StageAPI or name ~= "StageAPI-RenderAboveHUD" then return end
	local stageAnimData = StageAPI.TransitionAnimationData
	---@type Sprite
	local stageAPIIcon = stageAnimData.Sprites.IsaacIndicator
	---@type Vector
	local renderPos = stageAnimData.IsaacIndicatorPos
	if loadedIconForStageAPI and (stageAnimData.State == 3 or game:GetRoom():GetFrameCount() > 0) then
		loadedIconForStageAPI = false
	end
	if not renderPos or stageAnimData.State ~= 2 then return end
	if stageAnimData.State == 2 and stageAnimData.Frame > 150 and not loadedIconForStageAPI then
		stageAPIIcon:GetLayer(0):SetVisible(false)
		loadIsaacIcon()
		loadedIconForStageAPI = true
	end
	local animData = stageAPIIcon:GetCurrentAnimationData()
	local layerData = animData:GetLayer(0)
	if not layerData then return end
	local frameData = layerData:GetFrame(stageAPIIcon:GetFrame())
	if not frameData then return end
	local playerType = Isaac.GetPlayer():GetPlayerType()
	isaacIcon.Scale = frameData:GetScale()
	isaacIcon.Offset = frameData:GetPos()
	if stageAnimData.NightmareLastFrame and (stageAnimData.Sprites.Nightmare:GetFrame() >= stageAnimData.NightmareLastFrame - 20) then
		local alpha = 1 - StageAPI.BlackScreenOverlay.Color.A
		isaacIcon.Color = Color(alpha, alpha, alpha, 1)
	else
		isaacIcon.Color = stageAPIIcon.Color
	end
	if not customBlacklist[playerType] then
		isaacIcon:RenderLayer(renderLayer, Vector(renderPos.X, renderPos.Y - 3 + currentCustomOffset))
	end
	if Isaac.GetFrameCount() % 2 == 0 then
		isaacIcon:Update()
	end
end

mod:AddCallback(ModCallbacks.MC_GET_SHADER_PARAMS, mod.RenderForStageAPI)

return mod
