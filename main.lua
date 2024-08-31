-- VERSION 1.2.1

_G.UniqueProgressBarIcon = RegisterMod("UniqueProgressBarIcon", 1)

---@class ModReference
local mod = UniqueProgressBarIcon

if not REPENTOGON then return end

local saveManager = require("src_upbi.save_manager")
saveManager.Init(UniqueProgressBarIcon)
UniqueProgressBarIcon.SaveManager = saveManager
require("src_upbi.imGui")
local api = include("src_upbi.api")

local game = Game()

local TRANSITION_FRAME_START = 80
local TRANSITION_FRAME_END = 140
local ICON_SPEED = 0.45
local MAP_ICON_LENGTH = 26

local firstIconPos = 0
local iconMapOffset = 0
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

---@class IsaacIcon
---@field PlayerType PlayerType
---@field Icon Sprite
---@field Offset Vector
---@field RenderLayer integer
---@field PrimaryTwin PlayerType | nil
---@field TwinData IsaacIcon | nil
---@field StopRender boolean
---@field ControllerIndex integer
---@field ShadowPosition Vector | nil
---@field IconPosition Vector | nil

---@type IsaacIcon[]
local isaacIcons = {}

local shadowLocations = Sprite("gfx/ui/stage/progress_coop_positions.anm2", true)

--#region progress bar position calculation

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
	iconMapOffset = MAP_ICON_LENGTH * (startPos - 1) + (startPos - 1)
	movingPos = 0
end

function mod:OnNightmareShow()
	if NightmareScene.IsDogmaNightmare() then return end
	currentNightmareFrame = 0
	self:CalculateProgressBarLength()
end

mod:AddCallback(ModCallbacks.MC_POST_NIGHTMARE_SCENE_SHOW, mod.OnNightmareShow)

--#endregion

--#region rendering

---@param player EntityPlayer
---@overload fun(playerType: PlayerType)
local function tryCreateModdedCoopIcon(player)
	local playerType = type(player) == "number" and player or player:GetPlayerType()
	local coopSprite = EntityConfig.GetPlayer(playerType):GetModdedCoopMenuSprite()
	if not coopSprite then return end
	local testSprite, wasLoadSuccessful = Sprite(coopSprite:GetFilename(), true)
	if not wasLoadSuccessful then return end
	coopSprite = testSprite
	local name = EntityConfig.GetPlayer(playerType):GetName()
	coopSprite:SetFrame(name, 0)
	if coopSprite:GetAnimation() ~= name then return end
	local iconAnimData = coopSprite:GetCurrentAnimationData()
	local renderLayer = 0
	if not iconAnimData:GetLayer(0):GetFrame(0) then
		local foundFrame = false
		for _, iconLayerData in ipairs(iconAnimData:GetAllLayers()) do
			if iconLayerData:GetFrame(0) then
				renderLayer = iconLayerData:GetLayerID()
				foundFrame = true
				break
			end
		end
		if not foundFrame then return end
	end
	return coopSprite, renderLayer
end

---@param player EntityPlayer
local function shouldIconBeCreated(player)
	local settingsSave = saveManager.GetSettingsSave()
	if not settingsSave then return false end
	if player.Variant == PlayerVariant.CO_OP_BABY then
		return settingsSave["DisplayCo-opBabies"]
	end
	local playerType = player:GetPlayerType()
	if api.CustomBlacklist[playerType] == true then return false end
	if not player.Parent
		and not api.RegisteredTwins[playerType]
	then
		if GetPtrHash(Isaac.GetPlayer()) ~= GetPtrHash(player)
			and not settingsSave["DisplayCo-opPlayers"]
		then
			return false
		end
		return true
	end
	if api.RegisteredTwins[playerType] then
		if not settingsSave.DisplayTwins then
			for _, otherPlayer in ipairs(PlayerManager.GetPlayers()) do
				if otherPlayer:GetPlayerType() == api.RegisteredTwins[playerType]
					and player.ControllerIndex == otherPlayer.ControllerIndex
				then
					return false
				end
			end
			return true
		end
		return true
	end
	if player.Parent and settingsSave.DisplayStrawmen and not api.RegisteredTwins[playerType] then
		return true
	end
	return false
end

---@param player EntityPlayer
---@return IsaacIcon
---@overload fun(playerType: PlayerType)
function UniqueProgressBarIcon.CreateIcon(player)
	local playerType = type(player) == "number" and player or player:GetPlayerType()
	local iconData = {
		PlayerType = playerType,
		Icon = nil,
		Offset = Vector.Zero,
		RenderLayer = 0,
		StopRender = false,
		ControllerIndex =
			type(player) == "number" and 0 or player.ControllerIndex
	}
	local anm2ToLoad = "gfx/ui/coop menu.anm2"
	local animToPlay = "Main"
	local frameToSet = 0
	local loadedModdedSprite = false
	local settingsSave = saveManager.GetSettingsSave()
	if not settingsSave then return iconData end

	if player.Variant == PlayerVariant.CO_OP_BABY then
		local babyType = player.Variant == BabySubType.BABY_GLITCH and player:GetGlitchBabySubType() or player.SubType
		iconData.RenderLayer = 1
		iconData.Offset = Vector(0, 2)
		if babyType >= BabySubType.BABY_SPIDER and babyType <= BabySubType.BABY_BOUND then
			frameToSet = babyType + 1
		elseif api.CustomCoopBabies[babyType] then
			local customAnimation = api.CustomCoopBabies[babyType]
			local newSprite = Sprite(customAnimation.Anm2, true)
			newSprite:SetFrame(newSprite:GetDefaultAnimation(), customAnimation.Frame)
			iconData.RenderLayer = 0
			iconData.Icon = newSprite
			loadedModdedSprite = true
		end
	elseif player:IsCoopGhost() and settingsSave["DeadplayersasCo-opghosts"] then
		local newSprite = Sprite("gfx/ui/unique_coop_ghost_icons.anm2", true)
		local defaultSkinColor = EntityConfig.GetPlayer(playerType):GetSkinColor()
		local skinColorFrame = {
			[SkinColor.SKIN_BLUE] = 1,
			[SkinColor.SKIN_BLACK] = 2,
			[SkinColor.SKIN_GREY] = 3
		}
		newSprite:SetFrame("Main", skinColorFrame[defaultSkinColor] or 0)
		loadedModdedSprite = true
		iconData.Icon = newSprite
	elseif api.CustomAnims[playerType] then
		local customAnimation = api.CustomAnims[playerType]
		if customAnimation.Sprite then
			customAnimation.Sprite:SetFrame(customAnimation.Sprite:GetAnimation(), 0)
			iconData.Icon = customAnimation.Sprite
			loadedModdedSprite = true
		elseif customAnimation.Animation and customAnimation.Anm2 then
			anm2ToLoad = customAnimation.Anm2
			animToPlay = customAnimation.Animation
		end
	elseif playerType >= PlayerType.PLAYER_ISAAC and playerType < PlayerType.NUM_PLAYER_TYPES then
		frameToSet = playerType + 1
	else
		local newSprite, renderLayer = tryCreateModdedCoopIcon(player)
		if newSprite then
			loadedModdedSprite = true
			iconData.Icon = newSprite
			iconData.RenderLayer = renderLayer
		end
	end
	if not loadedModdedSprite then
		local coopIcon = Sprite(anm2ToLoad, true)
		coopIcon:SetFrame(animToPlay, frameToSet)
		iconData.Icon = coopIcon
	end
	if api.CustomYOffsets[playerType] then
		iconData.Offset = Vector(iconData.Offset.X, api.CustomYOffsets[playerType])
	end
	if api.RegisteredTwins[playerType] then
		iconData.PrimaryTwin = api.RegisteredTwins[playerType]
	end
	iconData.StopRender = api.StopRender[playerType] == true
	return iconData
end

function mod:LoadIsaacIcons()
	---@type IsaacIcon[]
	local iconList = {}
	for _, player in ipairs(PlayerManager.GetPlayers()) do
		if not shouldIconBeCreated(player) then goto continue end
		local iconData = UniqueProgressBarIcon.CreateIcon(player)
		Isaac.RunCallback(UniqueProgressBarIcon.Callbacks.POST_CREATE_ICON, iconData, player)
		--iconData.Icon.Color = Color(0,0,0,0.5)
		table.insert(iconList, iconData)
		::continue::
	end
	--If all players have been accounted for and its over 4, try and condense twins
	if #iconList > 4 then
		for index = #iconList, 1, -1 do
			local iconData = iconList[index]
			for j, iconData2 in ipairs(iconList) do
				if iconData2.PlayerType == iconData.PrimaryTwin
					and iconData2.ControllerIndex == iconData.ControllerIndex
					and not iconData2.TwinData
					and not iconData.TwinData
				then
					iconList[j].TwinData = iconData
					table.remove(iconList, index)
					break
				end
			end
		end
	end
	--Hard cap at 4
	isaacIcons = {
		iconList[1],
		iconList[2],
		iconList[3],
		iconList[4]
	}
end

--shadowLocations.Color = Color(1,1,1,1,1,1,1)

---@param iconData IsaacIcon
---@param renderPos Vector
---@param playerNum integer
local function renderIsaacIcon(iconData, renderPos, playerNum)
	local sprite = iconData.Icon
	if iconData.StopRender == true then return end
	local nullLayer = shadowLocations:GetNullFrame("player" .. playerNum)
	if not nullLayer then return end
	local renderX, renderY = renderPos.X, renderPos.Y
	local shadowPosition = nullLayer:GetPos()
	local scale = 1
	if tonumber(shadowLocations:GetAnimation()) > 2 then
		scale = 0.5
		shadowLocations.Scale = Vector(shadowLocations.Scale.X - scale, shadowLocations.Scale.Y - scale)
		sprite.Scale = Vector(sprite.Scale.X - scale, sprite.Scale.Y - scale)
	end
	renderX, renderY = (renderX + ((iconData.Offset.X + shadowPosition.X) * scale)),
		(renderY + ((iconData.Offset.Y + shadowPosition.Y) * scale))
	if iconData.TwinData then
		renderX = renderX - 2
	end
	local layer = iconData.RenderLayer
	local shadowX, shadowY = renderX, renderY + 3
	shadowY = shadowY - (iconData.Offset.Y * scale)
	iconData.ShadowPosition = Vector(shadowX, shadowY)
	iconData.IconPosition = Vector(renderX, renderY) --Mostly used just to expose the icon position in case other mods wanna use it
	shadowLocations:Render(iconData.ShadowPosition)
	sprite:RenderLayer(layer, iconData.IconPosition)

	if Isaac.GetFrameCount() % 2 == 0 then
		sprite:Update()
	end
end

---@param spr Sprite
---@return AnimationFrame | nil, AnimationFrame | nil
local function getIconFrameData(spr)
	local animData1 = spr:GetCurrentAnimationData()
	local layerData1 = animData1:GetLayer(0)
	if not layerData1 then return end
	local frameData1 = layerData1:GetFrame(spr:GetFrame())
	if not frameData1 then return end
	local animData2 = spr:GetCurrentAnimationData()
	local layerData2 = animData2:GetLayer(1)
	local frameData2 = layerData2:GetFrame(spr:GetFrame())
	return frameData1, frameData2
end

---@param icon Sprite
local function adjustIconColorForStageAPI(icon)
	local stageAnimData = StageAPI.TransitionAnimationData
	local stageAPIIcon = stageAnimData.Sprites.IsaacIndicator
	if stageAnimData.NightmareLastFrame and (stageAnimData.Sprites.Nightmare:GetFrame() >= stageAnimData.NightmareLastFrame - 20) then
		local alpha = 1 - StageAPI.BlackScreenOverlay.Color.A
		icon.Color = Color(alpha, alpha, alpha, 1)
	else
		icon.Color = stageAPIIcon.Color
	end
end

---@param renderPos Vector
function mod:RenderIsaacIcons(renderPos, isStageAPI)
	local iconSprite = NightmareScene.GetProgressBarSprite()
	if isStageAPI then
		iconSprite = StageAPI.TransitionAnimationData.Sprites.IsaacIndicator
	end
	local iconFrameData, shadowFrameData = getIconFrameData(iconSprite)
	if not iconFrameData or not shadowFrameData then return end
	local iconScale = iconFrameData:GetScale()
	local iconOffset = iconFrameData:GetPos()
	local shadowScale = shadowFrameData:GetScale()

	for playerNum, iconData in ipairs(isaacIcons) do
		if iconData.TwinData then
			shadowLocations.Scale = shadowScale
			local sprite = iconData.TwinData.Icon
			sprite.Offset = iconOffset
			sprite.Scale = iconScale
			if isStageAPI then
				adjustIconColorForStageAPI(sprite)
			end
			renderIsaacIcon(iconData.TwinData, Vector(renderPos.X + 2, renderPos.Y), playerNum)
		end
		shadowLocations.Scale = shadowScale
		local sprite = iconData.Icon
		sprite.Offset = iconOffset
		sprite.Scale = iconScale
		if isStageAPI then
			adjustIconColorForStageAPI(sprite)
		end
		renderIsaacIcon(iconData, renderPos, playerNum)
	end
	Isaac.RunCallback(UniqueProgressBarIcon.Callbacks.POST_ICONS_RENDER, isaacIcons, shadowLocations, renderPos)
end

function mod:OnNightmareRender()
	if NightmareScene.IsDogmaNightmare() then return end
	local renderPos = Vector((Isaac.GetScreenWidth() / 2) - firstIconPos + iconMapOffset + movingPos, 20)

	if currentNightmareFrame == 0 then
		NightmareScene.GetProgressBarSprite():GetLayer(1):SetVisible(false)
		mod:LoadIsaacIcons()
		shadowLocations:SetFrame(tostring(#isaacIcons), 0)
		Isaac.RunCallback(UniqueProgressBarIcon.Callbacks.POST_ICONS_INIT, isaacIcons, shadowLocations)
	end

	currentNightmareFrame = currentNightmareFrame + 1
	if currentNightmareFrame >= TRANSITION_FRAME_START and currentNightmareFrame <= TRANSITION_FRAME_END then
		if direction == ICON_DIRECTION.FORWARD then
			movingPos = movingPos + ICON_SPEED
		elseif direction == ICON_DIRECTION.BACKWARD then
			movingPos = movingPos - ICON_SPEED
		end
	end
	mod:RenderIsaacIcons(renderPos)
end

mod:AddCallback(ModCallbacks.MC_POST_NIGHTMARE_SCENE_RENDER, mod.OnNightmareRender)

if currentNightmareFrame > 0 then
	currentNightmareFrame = 0
end

function mod:TestCoopIcon()
	if currentNightmareFrame == 0 then
		mod:LoadIsaacIcons()
		currentNightmareFrame = 1
	end
	if game:IsPaused() then return end
	for i, iconData in ipairs(isaacIcons) do
		local renderPos = Vector((Isaac.GetScreenWidth() / 2) - ((i - 1) * 32) + ((i - 1) * 64),
			(Isaac.GetScreenHeight() / 2))
		iconData.Icon:RenderLayer(iconData.RenderLayer, renderPos)
		Isaac.RenderText(iconData.Icon:GetAnimation(), renderPos.X, renderPos.Y + 10, 1, 1, 1, 1)
	end
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
	renderPos = Vector(renderPos.X, renderPos.Y - 3)
	if stageAnimData.State == 2 and stageAnimData.Frame > 150 and not loadedIconForStageAPI then
		stageAPIIcon:GetLayer(0):SetVisible(false)
		stageAPIIcon:GetLayer(1):SetVisible(false)
		mod:LoadIsaacIcons()
		loadedIconForStageAPI = true
		shadowLocations:SetFrame(tostring(#isaacIcons), 0)
		Isaac.RunCallback(UniqueProgressBarIcon.Callbacks.POST_ICONS_INIT, isaacIcons, shadowLocations)
	end

	mod:RenderIsaacIcons(renderPos, true)
end

mod:AddCallback(ModCallbacks.MC_GET_SHADER_PARAMS, mod.RenderForStageAPI)

--#endregion

return mod
