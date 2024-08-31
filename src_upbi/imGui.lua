local imguiSupport = {}

local menu = "uniqueProgressBarIcon"

local settingsData = {
	{ Name = "Display Co-op Players", DefaultValue = true,  Helpmarker = "Displays co-op players." },
	{ Name = "Display Strawmen",     DefaultValue = false, Helpmarker = "Strawman-like players will be displayed." },
	{ Name = "Display Twins", DefaultValue = true, Helpmarker = "Displays twin players so long as they've been manually registered. Will group twins together if total player count goes over 4."},
	{ Name = "Display Dark Esau", DefaultValue = true, Helpmarker = "While playing as Tainted Jacob, will display Dark Esau under the floor you were previously on."
		.. " Will also display Shadow Esau if they have Birthright."
	},
	{ Name = "LazarusB Birthright", DefaultValue = true, Helpmarker = "While playing as Tainted Lazarus, if they have Birthright and \"Display Twins\" is enabled, "
		.. "will display the hologram player with a custom holographic-like icon." },
	{ Name = "Display Co-op Babies", DefaultValue = false, Helpmarker = "Displays co-op babies. This includes Found Soul. Co-op player ghosts are not affected by this, still treated as players."
		.. " Babies without an icon are displayed as the \"Random\" baby icon, which is unfortunately most of them."},
	{ Name = "Dead Players as Co-op Ghosts", DefaultValue = true, Helpmarker = "When a co-op player is dead as a co-op ghost, they'll display as such instead of their normal character icon."}
}

function imguiSupport:CreateMenu()
	if not ImGui.ElementExists(menu) then
		ImGui.CreateMenu(menu, "\u{f5b3} UPB Icon")
		ImGui.AddElement(menu, "UPBI_settingsMenuButton", ImGuiElement.MenuItem, "Mod Settings")
		ImGui.CreateWindow("UPBI_settingsWindow", "Unique Progress Bar Icon Settings")
		ImGui.LinkWindowToElement("UPBI_settingsWindow", "UPBI_settingsMenuButton")
	end
end

imguiSupport:CreateMenu()

local function getSettingsVarName(setting, element)
	local varName = string.gsub(setting.Name, " ", "")
	if element then
		varName = "UPBI_" .. varName
	end
	return varName
end

for _, setting in ipairs(settingsData) do
	local varName = string.gsub(setting.Name, " ", "")
	UniqueProgressBarIcon.SaveManager.DEFAULT_SAVE.file.settings[varName] = setting.DefaultValue
end

function imguiSupport:CreateImguiWindows()
	local settingsSave = UniqueProgressBarIcon.SaveManager.GetSettingsSave()
	if not settingsSave then return end
	for _, setting in ipairs(settingsData) do
		local varName = getSettingsVarName(setting)
		local elementName = getSettingsVarName(setting, true)
		ImGui.AddCheckbox("UPBI_settingsWindow", elementName, setting.Name,
			function(bool)
				local settingsSave = UniqueProgressBarIcon.SaveManager.GetSettingsSave()
				if not settingsSave then return end
				settingsSave[varName] = bool
				UniqueProgressBarIcon.SaveManager.Save()
			end,
			settingsSave[varName])
		ImGui.SetHelpmarker(elementName, setting.Helpmarker)
	end
end

function imguiSupport:UpdateImGui()
	local settingsSave = UniqueProgressBarIcon.SaveManager.GetSettingsSave()
	if not settingsSave then return end
	if settingsSave["DisplayCoopPlayers"] then
		settingsSave["DisplayCo-opPlayers"] = settingsSave["DisplayCoopPlayers"]
		settingsSave["DisplayCoopPlayers"] = nil
	end
	if ImGui.ElementExists(getSettingsVarName(settingsData[1], true)) then
		for _, setting in ipairs(settingsData) do
			local varName = getSettingsVarName(setting)
			local elementName = getSettingsVarName(setting, true)
			ImGui.UpdateData(elementName, ImGuiData.Value, settingsSave[varName])
		end
	end
end

UniqueProgressBarIcon.SaveManager.AddCallback(UniqueProgressBarIcon.SaveManager.Utility.CustomCallback.POST_DATA_LOAD,
	imguiSupport.UpdateImGui)

---@param saveSlot integer
---@param isSlotSelected boolean
---@param rawSlot integer
function imguiSupport:OnSaveSlotLoad(saveSlot, isSlotSelected, rawSlot)
	if not isSlotSelected then
		if rawSlot == 0 and not ImGui.ElementExists("UPBI_saveSlotNotice") then
			ImGui.AddText("UPBI_settingsWindow",
				"NOTICE: No options are accessible until a slot is selected. Please select a save file!", true,
				"UPBI_saveSlotNotice")
			ImGui.SetTextColor("UPBI_saveSlotNotice", 1, 0.9, 0)
		end
		return
	end
	if ImGui.ElementExists("UPBI_saveSlotNotice") then
		ImGui.RemoveElement("UPBI_saveSlotNotice")
		imguiSupport:CreateImguiWindows()
		return
	end
end

UniqueProgressBarIcon:AddCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, imguiSupport.OnSaveSlotLoad)

return imguiSupport
