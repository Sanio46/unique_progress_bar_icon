-- VERSION 1.1

_G.UniqueProgressBarIcon = RegisterMod("UniqueProgressBarIcon", 1)

---@class ModReference
local mod = UniqueProgressBarIcon

if not REPENTOGON then return end

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

---@type table<PlayerType, integer>
local customYOffsets = {}

---@type IsaacIcon[]
UniqueProgressBarIcon.Icons = {}

local shadowLocations = Sprite("gfx/ui/stage/progress_coop_positions.anm2", true)

---@type table<PlayerType, boolean>
local customBlacklist = {}

---@type table<PlayerType, {Anm2: string | nil, Animation: string | nil, Sprite: Sprite | nil}>
local customAnims = {
	[PlayerType.PLAYER_LAZARUS2] = { Anm2 = "gfx/ui/unique_coop_icons.anm2", Animation = "LazarusRisen" },
	[PlayerType.PLAYER_LAZARUS2_B] = { Anm2 = "gfx/ui/unique_coop_icons.anm2", Animation = "LazarusRisenB" },
	[PlayerType.PLAYER_ESAU] = { Anm2 = "gfx/ui/unique_coop_icons.anm2", Animation = "Esau" }
}

---@type table<PlayerType, PlayerType>
local registeredTwins = {
	[PlayerType.PLAYER_ESAU] = PlayerType.PLAYER_JACOB
}

--#region API

---@param num string
---@param errorVar any
---@param funcName string
---@param expectedType string
---@param customMessage? string
local function UniqueProgressBarError(num, errorVar, funcName, expectedType, customMessage)
	local messageStart = "[UniqueProgressBarIcon] " ..
		"Bad Argument #" .. num .. " in UniqueProgressBarIcon." .. funcName
	local messageAppend = customMessage ~= nil and customMessage or
		"Attempt to index a " .. type(errorVar) .. " value, field '" .. tostring(errorVar) ..
		"', expected " .. expectedType .. "."
	error(messageStart .. messageAppend)
end

---@param playerType PlayerType
local function UniqueIsaacPlayerTypeCheck(playerType, funcName)
	if not playerType
		or type(playerType) ~= "number"
	then
		UniqueProgressBarError("1", playerType, funcName, "PlayerType")
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
	if not UniqueIsaacPlayerTypeCheck(playerType, "AddIconYOffset") then return end
	if not offset
		or type(offset) ~= "number"
	then
		UniqueProgressBarError("2", offset, "AddIconYOffset", "number")
	end
	customYOffsets[playerType] = offset
end

---Set a different icon to use for a specific PlayerType instead of their default co-op icon. Set the anm2 file it needs to play and its respective animation or provide the Sprite object directly.
---@param playerType PlayerType
---@param anm2 string
---@param animation string
---@overload fun(playerType: PlayerType, sprite: Sprite)
function UniqueProgressBarIcon.SetIcon(playerType, anm2, animation)
	if not UniqueIsaacPlayerTypeCheck(playerType, "SetIcon") then return end
	if not anm2
		or (
			type(anm2) ~= "string"
			and type(anm2) ~= "userdata"
		)
		or (
			type(anm2) == "userdata"
			and getmetatable(anm2).__type ~= "Sprite"
		)
	then
		UniqueProgressBarError("2", anm2, "SetIcon", "string or Sprite")
		return
	elseif type(anm2) == "string"
	and (not animation
		or type(animation) ~= "string")
	then
		UniqueProgressBarError("3", animation, "SetIcon", "string")
		return
	end

	local sprite, wasLoaded = Sprite(anm2, true)
	if type(anm2) ~= "string" then
		---@cast anm2 Sprite
		sprite = anm2
		wasLoaded = true
	end
	if not wasLoaded then
		UniqueProgressBarError("2", anm2, "SetIcon", "string", "(Anm2 failed to load).")
	end

	sprite:Stop()
	
	if type(anm2) == "string" then
		sprite:Play(animation)
		if not sprite:IsPlaying(animation) then
			UniqueProgressBarError("3", animation, "string", "(Animation name is invalid).")
		end
		sprite:SetFrame(animation, 0)
	end
	local animTable = type(anm2) == "userdata" and {Sprite = sprite} or { Anm2 = anm2, Animation = animation }
	customAnims[playerType] = animTable
end

---Reset the icon set by UniqueProgressBarIcon.SetIcon()
---@param playerType PlayerType
function UniqueProgressBarIcon.ResetIcon(playerType)
	if not UniqueIsaacPlayerTypeCheck(playerType, "ResetIcon") then return end
	customAnims[playerType] = nil
end

---If you want to do your own thing. Sets whether the icon will be rendered or not.
---@param playerType PlayerType
---@param bool boolean True to stop rendering, false to render as normal again.
function UniqueProgressBarIcon.StopPlayerTypeRender(playerType, bool)
	if not UniqueIsaacPlayerTypeCheck(playerType, "StopPlayerTypeRender") then return end
	customBlacklist[playerType] = bool
end

--#endregion

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

---@param player EntityPlayer
---@overload fun(playerType: PlayerType, playerName: string)
local function tryCreateModdedCoopIcon(player, playerName)
	local playerType = type(player) == "number" and player or player:GetPlayerType()
	local coopSprite = EntityConfig.GetPlayer(playerType):GetModdedCoopMenuSprite()
	if not coopSprite then return end
	local testSprite, wasLoadSuccessful = Sprite(coopSprite:GetFilename(), true)
	if not wasLoadSuccessful then return end
	coopSprite = testSprite
	local name = playerName or player:GetName()
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
---@return IsaacIcon
---@overload fun(playerType: PlayerType, playerName: string)
function UniqueProgressBarIcon.CreateIcon(player, playerName)
	local playerType = type(player) == "number" and player or player:GetPlayerType()
	local iconData = { PlayerType = playerType, Icon = nil, Offset = Vector.Zero, RenderLayer = 0, StopRender = false }
	local anm2ToLoad = "gfx/ui/coop menu.anm2"
	local animToPlay = "Main"
	local frameToSet = 0
	local loadedModdedSprite = false
	if customAnims[playerType] then
		local customAnimation = customAnims[playerType]
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
		local newSprite, renderLayer = tryCreateModdedCoopIcon(player, playerName)
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
	if customYOffsets[playerType] then
		iconData.Offset = Vector(iconData.Offset.X, customYOffsets[playerType])
	end
	if registeredTwins[playerType] then
		iconData.PrimaryTwin = registeredTwins[playerType]
	end
	iconData.StopRender = customBlacklist[playerType] == true
	return iconData
end

local function loadIsaacIcons()
	---@type IsaacIcon[]
	local iconList = {}
	for _, player in ipairs(PlayerManager.GetPlayers()) do
		local playerType = player:GetPlayerType()
		--Stop strawman-like or other-twin players if they aren't a registered twin
		if (player.Parent or GetPtrHash(player:GetMainTwin()) ~= GetPtrHash(player)) and not registeredTwins[playerType] then goto continue end
		local iconData = UniqueProgressBarIcon.CreateIcon(player)
		--iconData.Icon.Color = Color(0,0,0,0.5)
		table.insert(iconList, iconData)
		::continue::
	end
	--If all players have been accounted for and its over 4, try and condense twins
	if #iconList > 4 then
		for index = #iconList, 1, -1 do
			local iconData = iconList[index]
			if iconList[index - 1] and iconList[index - 1].PlayerType == iconData.PrimaryTwin then
				iconList[index - 1].TwinData = iconData
				table.remove(iconList, index)
			end
		end
	end
	--Hard cap at 4
	UniqueProgressBarIcon.Icons = {
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
	if customYOffsets[iconData.PlayerType] then
		shadowY = shadowY - (customYOffsets[iconData.PlayerType] * scale)
	end
	shadowLocations:Render(Vector(shadowX, shadowY))
	sprite:RenderLayer(layer, Vector(renderX, renderY))

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

	for playerNum, iconData in ipairs(UniqueProgressBarIcon.Icons) do
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
end

function mod:OnNightmareRender()
	if NightmareScene.IsDogmaNightmare() then return end

	if currentNightmareFrame == 0 then
		NightmareScene.GetProgressBarSprite():GetLayer(1):SetVisible(false)
		loadIsaacIcons()
		shadowLocations:SetFrame(tostring(#UniqueProgressBarIcon.Icons), 0)
	end

	currentNightmareFrame = currentNightmareFrame + 1
	if currentNightmareFrame >= TRANSITION_FRAME_START and currentNightmareFrame <= TRANSITION_FRAME_END then
		if direction == ICON_DIRECTION.FORWARD then
			movingPos = movingPos + ICON_SPEED
		elseif direction == ICON_DIRECTION.BACKWARD then
			movingPos = movingPos - ICON_SPEED
		end
	end
	mod:RenderIsaacIcons(Vector((Isaac.GetScreenWidth() / 2) - firstIconPos + iconMapOffset + movingPos, 20))
end

mod:AddCallback(ModCallbacks.MC_POST_NIGHTMARE_SCENE_RENDER, mod.OnNightmareRender)

if currentNightmareFrame > 0 then
	currentNightmareFrame = 0
end

function mod:TestCoopIcon()
	if currentNightmareFrame == 0 then
		loadIsaacIcons()
		currentNightmareFrame = 1
	end
	if game:IsPaused() then return end
	for i, iconData in ipairs(UniqueProgressBarIcon.Icons) do
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
	if stageAnimData.State == 2 and stageAnimData.Frame > 150 and not loadedIconForStageAPI then
		stageAPIIcon:GetLayer(0):SetVisible(false)
		stageAPIIcon:GetLayer(1):SetVisible(false)
		loadIsaacIcons()
		loadedIconForStageAPI = true
		shadowLocations:SetFrame(tostring(#UniqueProgressBarIcon.Icons), 0)
	end

	mod:RenderIsaacIcons(Vector(renderPos.X, renderPos.Y - 3), true)
end

mod:AddCallback(ModCallbacks.MC_GET_SHADER_PARAMS, mod.RenderForStageAPI)

return mod
