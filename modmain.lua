--[[
	Follow extra rules if you want to contain any codes of Glassic API in your DST mod:
	1. You must not publish your mod to WeGame.
	2. You must make your mods compatible with Glassic API.
--]]
Assets = {}
PrefabFiles = {}
PreloadAssets = {}

local ENV = env
GLOBAL.setfenv(1, GLOBAL)

GlassicAPI = {}

------------------------------------------------------------------------------------------------------------
-- Import Utils
------------------------------------------------------------------------------------------------------------
local utils = {
	"skinhandler",
	"slaxml",
	"upvalueutil",
}
for i = 1, #utils do
	ENV.modimport("utils/" .. utils[i])
end

------------------------------------------------------------------------------------------------------------

-- RegisterItemAtlas helps you register inventory item atlas, so you don't need to specify each mod prefab's inventory image and atlas
-- It's suitable for a atlas that contains mulitiple images.
-- The root folder is "MODROOT/images"
-- e.g. GlassicAPI.RegisterItemAtlas("inventoryimages", Assets) will import "MODROOT/images/inventoryimges.xml" and register every element inside.
-- must set 'assets_table' to Assets.
---@param atlas_path string
---@param assets_table table
GlassicAPI.RegisterItemAtlas = function(atlas_path, assets_table)
	atlas_path = resolvefilepath("images/" .. (atlas_path:find(".xml") and atlas_path or atlas_path .. ".xml"))

	local images = {}
	local file = io.open(atlas_path, "r")
	local parser = ENV.SLAXML:parser({
		attribute = function(name, value)
			if name == "name" then
				table.insert(images, value)
			end
		end,
	})
	if file then
		parser:parse(file:read("*a"))
		file:close()
	end

	if assets_table then
		table.insert(assets_table, Asset("ATLAS", atlas_path))
		table.insert(assets_table, Asset("ATLAS_BUILD", atlas_path, 256))
	end

	for _, image in ipairs(images) do
		RegisterInventoryItemAtlas(atlas_path, image)
		RegisterInventoryItemAtlas(atlas_path, hash(image))
	end
end

------------------------------------------------------------------------------------------------------------

-- InitCharacterAssets helps you init assets that a mod character needs.
-- e.g. GlassicAPI.InitCharacterAssets("civi", "DUCK", Assets)
-- must set 'assets_table' to Assets.
-- crafting menu avatar is required since GA 4.2
---@param char_name string
---@param char_gender string
---@param assets_table table
GlassicAPI.InitCharacterAssets = function(char_name, char_gender, assets_table)
	table.insert(assets_table, Asset("ATLAS", "bigportraits/" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "bigportraits/" .. char_name .. "_none.xml"))
	table.insert(assets_table, Asset("ATLAS", "images/names_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/avatars/avatar_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/avatars/avatar_ghost_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/avatars/self_inspect_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/saveslot_portraits/" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/crafting_menu_avatars/avatar_" .. char_name .. ".xml"))

	ENV.AddModCharacter(char_name, char_gender)
end

---@param path_to_file string
---@param assets_table table
GlassicAPI.InitMinimapAtlas = function(path_to_file, assets_table)
	local file = "images/" .. path_to_file .. ".xml"
	if assets_table then
		table.insert(assets_table, Asset("ATLAS", file))
	end
	ENV.AddMinimapAtlas(file)
end

--------------------------------------------------------------------------------

---@param tag string
GlassicAPI.SetExclusiveToTag = function(tag)
	---@diagnostic disable-next-line unused-local
	return function(skin_name, userid)
		local player = GlassicAPI.SkinHandler.GetPlayerFromID(userid) or ThePlayer
		if player then
			return player:HasTag(tag)
		end
		return true
	end
end

--------------------------------------------------------------------------------

-- use in skins' init_fn most.
-- before basic init, you need to specify skins' floating swap_data to make the anim switch looks normal.
---@param swap_data table
GlassicAPI.SetFloatData = function(inst, swap_data)
	if inst.components.floater and swap_data then
		inst.components.floater.swap_data = swap_data
	end
end

GlassicAPI.UpdateFloaterAnim = function(inst)
	local floater = inst.components.floater
	if floater and floater:IsFloating() and not (floater.wateranim or floater.landanim) then -- IA Compatible :angri:
		floater:SwitchToDefaultAnim(true)
		floater:SwitchToFloatAnim()
	end
end

------------------------------------------------------------------------------------------------------------

---@param symbol string
---@param symbol_override string
local function set_onquip_skin_item(symbol, symbol_override, frame)
	return function(inst)
		if not TheWorld.ismastersim then
			return
		end

		local onequipfn = inst.components.equippable.onequipfn
		if onequipfn then
			inst.components.equippable:SetOnEquip(function(_inst, _owner)
				onequipfn(_inst, _owner)
				local skin_build = _inst:GetSkinBuild()
				if skin_build then
					_owner:PushEvent("equipskinneditem", _inst:GetSkinName())
					_owner.AnimState:OverrideItemSkinSymbol(symbol, skin_build, symbol_override, _inst.GUID, frame)
				end
			end)
		end
	end
end

-- Set OverrideItemSkinSymbol for official items that has no skin.
-- This is an altanative way to hack into official items without skins.
-- For modded prefabs, you don't need to use this.
---@param name string prefab_name
---@param data table {symbol, symbol_override, frame}
--[[e.g.
	if not rawget(_G, "moonglassaxe_clear_fn") then
		moonglassaxe_clear_fn = function(inst)
			inst.AnimState:SetBank("glassaxe")
			GlassicAPI.SetFloatData(inst, { sym_build = "swap_glassaxe" })
			basic_clear_fn(inst, "glassaxe")
		end
		GlassicAPI.SetOnequipSkinItem("moonglassaxe", {"swap_object", "swap_glassaxe", "swap_glassaxe"})
	end
--]]
GlassicAPI.SetOnequipSkinItem = function(name, data)
	ENV.AddPrefabPostInit(name, set_onquip_skin_item(unpack(data)))
end

-- The common init fn for skinned prefabs.
--[[usage:
	CreatePrefabskin("skin_name", {
		...,
		init_fn = GlassicAPI.BasicInitFn,
		...,
	})
--]]
GlassicAPI.BasicInitFn = function(inst)
	if inst.components.placer == nil and not TheWorld.ismastersim then
		return
	end

	inst.AnimState:SetSkin(inst:GetSkinBuild())
	if inst.components.inventoryitem then
		inst.components.inventoryitem:ChangeImageName(inst:GetSkinName())
	end

	GlassicAPI.UpdateFloaterAnim(inst)
end

-- all actions require component. to avoid compatibility issues, it's better that we use a new component to set actions.
-- GlassicAPI.ShellComponent helps you create such a component.
-- e.g. "scripts/components/glasssocket.lua"
-- usage:
--	   return GlassicAPI.ShellComponent
GlassicAPI.ShellComponent = Class(function(self, inst)
	self.inst = inst
end)

------------------------------------------------------------------------------------------------------------

local TechTree = require("techtree")
---@param name string
local function rebuild_techtree(name)
	TECH.NONE = TechTree.Create()

	for _, v in pairs(AllRecipes) do
		v.level = TechTree.Create(v.level)
	end

	for k, v in pairs(TUNING.PROTOTYPER_TREES) do
		v = TechTree.Create(v)
		TUNING.PROTOTYPER_TREES[k] = TUNING.PROTOTYPER_TREES[k] or {}
		TUNING.PROTOTYPER_TREES[k][name] = TUNING.PROTOTYPER_TREES[k][name] or 0
	end
end

-- custom tech allows you to build custom prototyper or allows muliti prototypers to bonus a tech simultaneously.
-- e.g. GlassicAPI.AddTech("FRIENDSHIPRING")
---@param name string
---@param bonus_available? boolean
GlassicAPI.AddTech = function(name, bonus_available)
	table.insert(TechTree.AVAILABLE_TECH, name)
	if bonus_available then
		table.insert(TechTree.BONUS_TECH, name)
	end
	rebuild_techtree(name)
end

-- custom prototyper trees.
-- e.g. GlassicAPI.AddPrototyperTrees("DUMMYSCIENCE", {DUMMYTECH = 2})
---@param name string
---@param t table
GlassicAPI.AddPrototyperTrees = function(name, t)
	TUNING.PROTOTYPER_TREES[name] = TechTree.Create(t)
end

-- e.g.
-- GlassicAPI.MergeTechBonus("MOONORB_UPGRADED", "FRIENDSHIPRING", 2)
-- GlassicAPI.MergeTechBonus("MOON_ALTAR_FULL", "FRIENDSHIPRING", 2)
-- GlassicAPI.MergeTechBonus("OBSIDIAN_BENCH", "FRIENDSHIPRING", 2)
-- allows muliti prototypers to bonus a tech simultaneously.
---@param target string
---@param name string
---@param level number
GlassicAPI.MergeTechBonus = function(target, name, level)
	scheduler:ExecuteInTime(0, function()
		if TUNING.PROTOTYPER_TREES[target] then
			TUNING.PROTOTYPER_TREES[target][name] = level
		end
	end)
end

------------------------------------------------------------------------------------------------------------

-- set a recipe not listed in search filter or "EVERYTHING".
local HIDDEN_RECIPES = {}
local CraftingMenuWidget = require("widgets/redux/craftingmenu_widget")
local is_recipe_valid_for_search = CraftingMenuWidget.IsRecipeValidForSearch
---@param name string
---@diagnostic disable-next-line duplicate-set-filed
function CraftingMenuWidget:IsRecipeValidForSearch(name)
	local ret = { is_recipe_valid_for_search(self, name) }
	if HIDDEN_RECIPES[name] then
		return
	end
	return unpack(ret)
end

local function init_recipe_print(...)
	if KnownModIndex:IsModInitPrintEnabled() then
		print("Glassic API", ...)
	end
end

local add_recipe_to_filter = function(recipe_name, filter_name)
	init_recipe_print("AddRecipeToFilter", recipe_name)
	local filter = CRAFTING_FILTERS[filter_name]
	if filter ~= nil and filter.default_sort_values[recipe_name] == nil then
		table.insert(filter.recipes, recipe_name)
		filter.default_sort_values[recipe_name] = #filter.recipes
	end
end
-- a smarter way to add a mod recipe, and you don't need to think about filters too much.
-- also, with confog.hidden, you can set your recipe no searching or in "EVERYTHING" filter.
-- same format as AddRecipe2
---@param name string
---@param ingredients table
---@param tech table
---@param config? table
---@param filters? table
GlassicAPI.AddRecipe = function(name, ingredients, tech, config, filters)
	init_recipe_print("AddRecipe", name)
	require("recipe")
	---@diagnostic disable-next-line lowercase-global
	mod_protect_Recipe = false
	local rec = Recipe2(name, ingredients, tech, config)

	if not rec.is_deconstruction_recipe then
		if config and config.nounlock then
			add_recipe_to_filter(name, CRAFTING_FILTERS.CRAFTING_STATION.name)
		end

		if config and config.builder_tag and config.nochar == nil then
			add_recipe_to_filter(name, CRAFTING_FILTERS.CHARACTER.name)
		end

		if config and config.nomods == nil then
			add_recipe_to_filter(name, CRAFTING_FILTERS.MODS.name)
		end

		if config and config.hidden then
			HIDDEN_RECIPES[name] = true
		elseif HIDDEN_RECIPES[name] then
			HIDDEN_RECIPES[name] = nil
		end

		if filters then
			for _, filter_name in ipairs(filters) do
				add_recipe_to_filter(name, filter_name)
			end
		end
	end

	---@diagnostic disable-next-line lowercase-global
	mod_protect_Recipe = true
	rec:SetModRPCID()
	return rec
end

------------------------------------------------------------------------------------------------------------

local function get_index(t, v)
	for index, value in pairs(t) do
		if value == v then
			return index
		end
	end
end

local function do_sorting(a, b, filter_name, offset, force_sort)
	local filter = CRAFTING_FILTERS[filter_name]
	if filter and filter.recipes and type(filter.recipes) == "table" then
		local target_position
		local recipes = filter.recipes
		if get_index(recipes, a) then
			if force_sort or table.contains(recipes, b) then
				table.remove(recipes, get_index(recipes, a))
				target_position = #recipes + 1
			end
		end

		if get_index(recipes, b) then
			target_position = get_index(recipes, b) + offset
		end

		if type(target_position) == "number" then
			table.insert(recipes, target_position, a)
			filter.default_sort_values[a] = filter.default_sort_values[a] or #recipes
		end
	end
end

local function try_sorting(a, b, filter_type, offset)
	if filter_type then
		do_sorting(a, b, filter_type, offset, true)
	elseif b then
		for filter in pairs(CRAFTING_FILTERS) do
			do_sorting(a, b, filter, offset)
		end
	end
end

-- a quick way to sort recipes before or after current recipes.
---@param a string -- the recipe name that you want to sort
---@param b string -- the target recipe name that we base on.
---@param filter_type? string
-- e.g. GlassicAPI.RecipeSortAfter("darkcrystal", "purplegem") will sort "darkcrystal" after "purplegem" in all filters that "purplegem" is in.
-- e.g. GlassicAPI.RecipeSortAfter("darkcrystal", "purplegem", "MAGIC") will only sort "darkcrystal" after "purplegem" in "MAGIC" filter.
-- e.g. GlassicAPI.RecipeSortAfter("darkcrystal", "purplegem", "TOOLS") will only sort "darkcrystal" to the last in "TOOLS" because "purplegem" is not in "TOOLS".
-- e.g. GlassicAPI.RecipeSortAfter("darkcrystal", nil, "TOOLS") will also sort "darkcrystal" to the last in "TOOLS".
-- one of b and filter_type must not be nil.
GlassicAPI.RecipeSortBefore = function(a, b, filter_type)
	try_sorting(a, b, filter_type, 0)
end

---@param a string
---@param b string
---@param filter_type? string
GlassicAPI.RecipeSortAfter = function(a, b, filter_type)
	try_sorting(a, b, filter_type, 1)
end

------------------------------------------------------------------------------------------------------------

local function merge_internal(target, strings, no_override)
	for k, v in pairs(strings) do
		if type(v) == "table" then
			if type(target[k]) == "string" then
				if no_override then
					error("MERGE PROTECTION: Can not merge a table to a string!")
				else
					target[k] = {}
				end
			elseif not target[k] then
				target[k] = {}
			end
			merge_internal(target[k], v, no_override)
		else
			if not (no_override and target[k] ~= nil) then
				target[k] = v
			end
		end
	end
end

---@param strings table
---@param custom_field? table
---@param no_override? boolean
GlassicAPI.MergeStringsToGLOBAL = function(strings, custom_field, no_override)
	merge_internal(custom_field or STRINGS, strings, no_override)
end

local CHS_CODES = {
	zh = "chinese_s", -- Simplified Chinese
	zht = "chinese_t", -- Traditional Chinese
	chs = "chinese_s", -- Chinese Mod (workshop 367546858)
	cht = "chinese_t",
	sc = "chinese_s",
}
---@param base_path string
---@param override_lang? string
GlassicAPI.MergeTranslationFromPO = function(base_path, override_lang)
	local _defaultlang = LanguageTranslator.defaultlang
	local lang = override_lang or _defaultlang
	if not CHS_CODES[lang] then
		return
	end
	local filepath = base_path .. "/" .. CHS_CODES[lang] .. ".po"
	if not resolvefilepath_soft(filepath) then
		print("Could not find a language file matching " .. filepath .. " in any of the search paths.")
		return
	end
	local temp_lang = lang .. "_temp"
	LanguageTranslator:LoadPOFile(filepath, temp_lang)
	merge_internal(LanguageTranslator.languages[lang], LanguageTranslator.languages[temp_lang])
	TranslateStringTable(STRINGS)
	LanguageTranslator.languages[temp_lang] = nil
	LanguageTranslator.defaultlang = _defaultlang
end

-- Basically LanguageTranslator.ConvertEscapeCharactersToString, but replace "\"s first
---@param str string
GlassicAPI.ConvertEscapeCharactersToString = function(str)
	local newstr = string.gsub(str, "\\", "\\\\")
	newstr = string.gsub(newstr, "\n", "\\n")
	newstr = string.gsub(newstr, "\r", "\\r")
	newstr = string.gsub(newstr, '"', '\\"')

	return newstr
end

local function write_speech(file, base_strings, strings, indent)
	indent = indent or 1
	local str = string.rep("\t", indent)
	for _, k, v in sorted_pairs(strings) do
		if type(v) == "table" then
			file:write(str .. k .. " =\n" .. str .. "{\n")
			write_speech(file, base_strings and base_strings[k], v, indent + 1)
			file:write(str .. "}, \n")
		else
			local comment = base_strings and base_strings[k] and "" or "-- "
			v = GlassicAPI.ConvertEscapeCharactersToString(v)
			if tonumber(k) then
				file:write(str .. comment .. '"' .. v .. '", \n')
			else
				file:write(str .. comment .. k .. ' = "' .. v .. '", \n')
			end
		end
	end
end
---@param base_strings table
---@param file file*
---@param source? string
GlassicAPI.MergeSpeechFile = function(base_strings, file, source)
	local speech = require(source or "speech_wilson")
	file:write("return {\n")
	merge_internal(speech, base_strings)
	write_speech(file, base_strings, speech)
	file:write("}")
	file:write("\n")
	file:close()
end

local function write_for_strings(base, data, file)
	for _, k, v in sorted_pairs(data) do
		local path = base .. "." .. k
		if type(v) == "table" then
			write_for_strings(path, v, file)
		else
			file:write("\n")
			file:write("#. " .. path .. "\n")
			file:write('msgctxt "' .. path .. '"\n')
			file:write('msgid "' .. GlassicAPI.ConvertEscapeCharactersToString(v) .. '"\n')
			file:write('msgstr ""\n')
		end
	end
end

---@param file file*
---@param strings table of strings
GlassicAPI.MakePOTFromStrings = function(file, strings)
	file:write('msgid ""\n')
	file:write('msgstr ""\n')
	file:write('"Application: Don\'t Starve Together\\n"')
	file:write("\n")
	file:write('"POT Version: 2.0\\n"')
	file:write("\n")

	write_for_strings("STRINGS", strings, file)

	file:close()
end

local initialize_modmain = ModManager.InitializeModMain
ModManager.InitializeModMain = function(self, _modname, env, mainfile, ...)
	if mainfile == "modmain.lua" then
		env.GlassicAPI = GlassicAPI
	end
	return initialize_modmain(self, _modname, env, mainfile, ...)
end

-- GLOBAL.GlassicAPI = GlassicAPI
ENV.GlassicAPI = GlassicAPI

local main_files = {
	"strings",
	"glassicrarity",
	"common_action",
}

if IsRail() then
	error("Ban WeGame")
end

for i = 1, #main_files do
	ENV.modimport("main/" .. main_files[i])
end

if ENV.is_mim_enabled then
	return
end

ENV.modimport("main/reskin_tool")
