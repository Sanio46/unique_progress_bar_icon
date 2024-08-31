local api = {
	---@type table<PlayerType, boolean>
	StopRender = {},
	---@type table<PlayerType, boolean>
	CustomBlacklist = {},
	---@type table<PlayerType, integer>
	CustomYOffsets = {},
	---@type table<PlayerType, {Anm2: string | nil, Animation: string | nil, Sprite: Sprite | nil}>
	CustomAnims = {
		[PlayerType.PLAYER_LAZARUS2] = { Anm2 = "gfx/ui/unique_coop_icons.anm2", Animation = "LazarusRisen" },
		[PlayerType.PLAYER_LAZARUS2_B] = { Anm2 = "gfx/ui/unique_coop_icons.anm2", Animation = "LazarusRisenB" },
		[PlayerType.PLAYER_ESAU] = { Anm2 = "gfx/ui/unique_coop_icons.anm2", Animation = "Esau" },
		[PlayerType.PLAYER_THESOUL_B] = { Anm2 = "gfx/ui/unique_coop_icons.anm2", Animation = "The Soul" }
	},
	---@type table<PlayerType, PlayerType>
	RegisteredTwins = {
		[PlayerType.PLAYER_ESAU] = PlayerType.PLAYER_JACOB,
		[PlayerType.PLAYER_LAZARUS2_B] = PlayerType.PLAYER_LAZARUS_B,
		[PlayerType.PLAYER_THESOUL_B] = PlayerType.PLAYER_THEFORGOTTEN_B
	},
	---@type table<BabySubType, {Anm2: string, Frame: integer}>
	CustomCoopBabies = {
		[BabySubType.BABY_FOUND_SOUL] = { Anm2 = "gfx/ui/unique_coop_baby_icons.anm2", Frame = 0 },
		[BabySubType.BABY_WISP] = { Anm2 = "gfx/ui/unique_coop_baby_icons.anm2", Frame = 1 },
		[BabySubType.BABY_DOUBLE] = { Anm2 = "gfx/ui/unique_coop_baby_icons.anm2", Frame = 2 },
		[BabySubType.BABY_GLOWING] = { Anm2 = "gfx/ui/unique_coop_baby_icons.anm2", Frame = 3 },
		[BabySubType.BABY_ILLUSION] = { Anm2 = "gfx/ui/unique_coop_baby_icons.anm2", Frame = 4 },
		[BabySubType.BABY_HOPE] = { Anm2 = "gfx/ui/unique_coop_baby_icons.anm2", Frame = 5 },
		[BabySubType.BABY_SOLOMON_A] = { Anm2 = "gfx/ui/unique_coop_baby_icons.anm2", Frame = 6  }
	}
}

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
	error(messageStart .. messageAppend, 3)
end

---@param playerType PlayerType
local function UniqueIsaacPlayerTypeCheck(playerType, funcName)
	if not playerType
		or type(playerType) ~= "number"
	then
		UniqueProgressBarError("1", playerType, funcName, "PlayerType")
		return false
	elseif not EntityConfig.GetPlayer(playerType) then
		UniqueProgressBarError("1", playerType, funcName, "PlayerType", "(PlayerType is not in valid range between 0 and " .. EntityConfig:GetMaxPlayerType() .. ").")
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
		return
	end
	api.CustomYOffsets[playerType] = offset
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
		---@diagnostic disable-next-line: cast-type-mismatch
		---@cast anm2 Sprite
		sprite = anm2
		wasLoaded = true
	end
	if not wasLoaded then
		UniqueProgressBarError("2", anm2, "SetIcon", "string", "(Anm2 failed to load).")
		return
	end

	sprite:Stop()

	if type(anm2) == "string" then
		sprite:Play(animation)
		if not sprite:IsPlaying(animation) then
			UniqueProgressBarError("3", animation, "SetIcon", "string", "(Animation name is invalid).")
			return
		end
	end
	local animTable = type(anm2) == "userdata" and { Sprite = sprite } or { Anm2 = anm2, Animation = animation }
	api.CustomAnims[playerType] = animTable
end

---Reset the icon set by UniqueProgressBarIcon.SetIcon()
---@param playerType PlayerType
function UniqueProgressBarIcon.ResetIcon(playerType)
	if not UniqueIsaacPlayerTypeCheck(playerType, "ResetIcon") then return end
	api.CustomAnims[playerType] = nil
end

---Like SetIcon, but for co-op babies
---@param babySubType BabySubType
---@param anm2 string
---@param frame integer
function UniqueProgressBarIcon.SetBabyIcon(babySubType, anm2, frame)
	if not babySubType
		or type(babySubType) ~= "number"
	then
		UniqueProgressBarError("1", babySubType, "SetBabyIcon", "BabySubType")
		return false
	elseif not EntityConfig.GetBaby(babySubType) then
		UniqueProgressBarError("1", babySubType, "SetBabyIcon", "BabySubType", "(BabySubType is not in valid range between 0 and " .. EntityConfig:GetMaxBabyID() .. ").")
		return false
	end
	if not anm2
		or type(anm2) ~= "string"
	then
		UniqueProgressBarError("2", anm2, "SetBabyIcon", "string")
		return
	elseif not frame
		or type(frame) ~= "number"
	then
		UniqueProgressBarError("3", frame, "SetBabyIcon", "	")
		return
	end

	local sprite, wasLoaded = Sprite(anm2, true)
	if not wasLoaded then
		UniqueProgressBarError("2", anm2, "SetBabyIcon", "string", "(Anm2 failed to load).")
		return
	end

	if not sprite:GetAnimationData(sprite:GetDefaultAnimation()):GetLayer(0):GetFrame(frame) then
		UniqueProgressBarError("3", frame, "SetBabyIcon", "string", "(Animation name is invalid).")
		return
	end
	local animTable = { Anm2 = anm2, Frame = frame }
	api.CustomCoopBabies[babySubType] = animTable
end

---Reset the icon set by UniqueProgressBarIcon.SetBabyIcon()
---@param babySubType BabySubType
function UniqueProgressBarIcon.ResetBabyIcon(babySubType)
	if not babySubType
		or type(babySubType) ~= "number"
	then
		UniqueProgressBarError("1", babySubType, "SetBabyIcon", "BabySubType")
		return false
	elseif not EntityConfig.GetBaby(babySubType) then
		UniqueProgressBarError("1", babySubType, "SetBabyIcon", "BabySubType", "(BabySubType is not in valid range between 0 and " .. EntityConfig:GetMaxBabyID() .. ").")
		return false
	end
	api.CustomCoopBabies[babySubType] = nil
end

---If you want to do your own thing. Sets whether the icon will be rendered or not.
---@param playerType PlayerType
---@param bool boolean True to stop rendering, false to render as normal again.
function UniqueProgressBarIcon.StopPlayerTypeRender(playerType, bool)
	if not UniqueIsaacPlayerTypeCheck(playerType, "StopPlayerTypeRender") then return end
	api.StopRender[playerType] = bool
end

---Prevents the icon for the PlayerType from being generated.
---@param playerType PlayerType
---@param bool boolean True to set blacklist, false to lift it.
function UniqueProgressBarIcon.BlacklistPlayerType(playerType, bool)
	if not UniqueIsaacPlayerTypeCheck(playerType, "StopPlayerTypeRender") then return end
	api.CustomBlacklist[playerType] = bool
end

---Register a twin player that's meant be paired with another player. The twin player will be treated slightly differently. For example, twinPlayerType should be Esau, and mainPlayerType should be Jacob.
---@param mainPlayerType PlayerType
---@param twinPlayerType PlayerType
function UniqueProgressBarIcon.RegisterTwin(twinPlayerType, mainPlayerType)
	if not UniqueIsaacPlayerTypeCheck(mainPlayerType, "RegisterTwin") then
		return
	elseif not UniqueIsaacPlayerTypeCheck(twinPlayerType, "RegisterTwin") then
		return
	elseif mainPlayerType == twinPlayerType then
		UniqueProgressBarError("2", twinPlayerType, "RegisterTwin", "PlayerType",
			"(mainPlayerType and twinPlayerType cannot be equal).")
		return
	elseif mainPlayerType == api.RegisteredTwins[twinPlayerType] then
		UniqueProgressBarError("2", twinPlayerType, "RegisterTwin", "PlayerType",
			"(Cannot assign twinPlayerType as they already have an assigned twin).")
	end
	api.RegisteredTwins[mainPlayerType] = twinPlayerType
end

UniqueProgressBarIcon.Callbacks = {
	POST_CREATE_ICON = "UNIQUE_PROGRESS_BAR_ICON_POST_CREATE_ICON",
	POST_ICONS_RENDER = "UNIQUE_PROGRESS_BAR_ICON_POST_ICONS_RENDER",
	PRE_ICONS_INIT = "UNIQUE_PROGRESS_BAR_ICON_PRE_ICONS_INIT",
	POST_ICONS_INIT = "UNIQUE_PROGRESS_BAR_ICON_POST_ICONS_INIT"
}

---@param iconData IsaacIcon
---@param player EntityPlayer
UniqueProgressBarIcon:AddCallback(UniqueProgressBarIcon.Callbacks.POST_CREATE_ICON, function(_, iconData, player)
	local settingsSave = UniqueProgressBarIcon.SaveManager:GetSettingsSave()
	if not settingsSave or not settingsSave.LazarusBBirthright then return end
	if iconData.PlayerType == PlayerType.PLAYER_LAZARUS_B
		or iconData.PlayerType == PlayerType.PLAYER_LAZARUS2_B
	then
		if (player:GetOtherTwin() and player:GetOtherTwin():HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
				or player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT))
			and player.EntityCollisionClass == EntityCollisionClass.ENTCOLL_NONE
		then
			if iconData.PlayerType == PlayerType.PLAYER_LAZARUS2_B then
				iconData.Icon:SetFrame(iconData.Icon:GetAnimation() .. "_Birthright", 0)
			else
				iconData.Icon:Load("gfx/ui/unique_coop_icons.anm2", true)
				iconData.Icon:SetFrame("LazarusB_Birthright", 0)
			end
		end
	end
end)

local darkEsau = Sprite("gfx/ui/unique_coop_icons.anm2", true)
darkEsau:SetFrame("Dark Esau", 0)
local renderDarkEsau = false
local jacobHasBirthright = false
local stationaryPos = Vector.Zero

UniqueProgressBarIcon:AddCallback(UniqueProgressBarIcon.Callbacks.POST_ICONS_INIT, function()
	local settingsSave = UniqueProgressBarIcon.SaveManager:GetSettingsSave()
	if not settingsSave or not settingsSave.DisplayDarkEsau then
		renderDarkEsau = false
		return
	end
	renderDarkEsau = PlayerManager.AnyoneIsPlayerType(PlayerType.PLAYER_JACOB_B)
	jacobHasBirthright = PlayerManager.AnyPlayerTypeHasBirthright(PlayerType.PLAYER_JACOB_B)
	stationaryPos = Vector.Zero
end)

UniqueProgressBarIcon:AddCallback(UniqueProgressBarIcon.Callbacks.POST_ICONS_RENDER,
	---@param icons IsaacIcon[]
	---@param shadowSprite Sprite
	---@param renderPos Vector
	function(_, icons, shadowSprite, renderPos)
		if not renderDarkEsau then return end
		if stationaryPos.X == 0 and stationaryPos.Y == 0 then
			stationaryPos = renderPos
		end
		local renderX, renderY = stationaryPos.X, stationaryPos.Y + 32

		if jacobHasBirthright then
			renderX = renderX - 8
			darkEsau:SetFrame("Dark Esau", 0)
		end
		darkEsau.Color = icons[1].Icon.Color
		darkEsau.Offset = icons[1].Icon.Offset
		local scale = icons[1].Icon.Scale
		local shadowScale = shadowSprite.Scale
		if #icons > 2 then
			scale = Vector(scale.X + 0.5, scale.Y + 0.5)
			shadowScale = Vector(shadowScale.X + 0.5, shadowScale.Y + 0.5)
		end
		shadowSprite.Scale = shadowScale
		darkEsau.Scale = scale
		shadowSprite:Render(Vector(renderX, renderY + 3))
		darkEsau:Render(Vector(renderX, renderY))
		if jacobHasBirthright then
			renderX = renderX + 16
			darkEsau:SetFrame("Shadow Esau", 0)
			shadowSprite:Render(Vector(renderX, renderY + 3))
			darkEsau:Render(Vector(renderX, renderY))
		end
	end
)

---Returns the custom sprite for Dark Esau
---@return Sprite
function UniqueProgressBarIcon.GetDarkEsau()
	return darkEsau
end

return api
