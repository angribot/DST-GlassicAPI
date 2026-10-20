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
	atlas_path = resolvefilepath("images/" .. (atlas_path:find(".xml", 1, true) and atlas_path or atlas_path .. ".xml"))

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
---@param mod_env table
---@param char_name string
---@param char_gender string
---@param assets_table table
local function init_character_assets(mod_env, char_name, char_gender, assets_table)
	table.insert(assets_table, Asset("ATLAS", "bigportraits/" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "bigportraits/" .. char_name .. "_none.xml"))
	table.insert(assets_table, Asset("ATLAS", "images/names_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/avatars/avatar_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/avatars/avatar_ghost_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/avatars/self_inspect_" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/saveslot_portraits/" .. char_name .. ".xml"))
	table.insert(assets_table, Asset("ATLAS", "images/crafting_menu_avatars/avatar_" .. char_name .. ".xml"))

	mod_env.AddModCharacter(char_name, char_gender)
end

---@param mod_env table
---@param path_to_file string
---@param assets_table table
local function init_minimap_atlas(mod_env, path_to_file, assets_table)
	local file = "images/" .. path_to_file .. ".xml"
	if assets_table then
		table.insert(assets_table, Asset("ATLAS", file))
	end
	mod_env.AddMinimapAtlas(file)
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
	local floater = inst.components.floater
	if floater and swap_data then
		if floater.SetSwapData then
			floater:SetSwapData(swap_data)
		else
			floater.swap_data = swap_data
		end
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

---@param mod_env table
---@param name string prefab_name
---@param data table {symbol, symbol_override, default_build}
local function add_onquip_skin_item(mod_env, name, data)
	local symbol, symbol_override, default_build = unpack(data)

	mod_env.AddPrefabPostInit(name, function(inst)
		if not TheWorld.ismastersim then
			return
		end

		if not inst.components.equippable then
			return
		end

		-- Listening on the item's own "equipped" event keeps working when another mod
		-- replaces onequipfn later. Only "equipskinneditem" is pushed: prefabs that
		-- already handle their own skin push it too, and a second unequip push would
		-- close a different worn-item record in worldoverseer.
		inst:ListenForEvent("equipped", function(_inst, event_data)
			local owner = event_data and event_data.owner
			local skin_build = _inst:GetSkinBuild()
			if owner and skin_build then
				owner:PushEvent("equipskinneditem", _inst:GetSkinName())
				owner.AnimState:OverrideItemSkinSymbol(symbol, skin_build, symbol_override, _inst.GUID, default_build)
			end
		end)
	end)
end

-- Set OverrideItemSkinSymbol for official items that has no skin.
-- This is an altanative way to hack into official items without skins.
-- For modded prefabs, you don't need to use this.
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
-- The common init fn for skinned prefabs.
--[[usage:
	CreatePrefabskin("skin_name", {
		...,
		init_fn = GlassicAPI.BasicInitFn,
		...,
	})
--]]
-- This generic helper cannot know each prefab's official filter_fn/def_build
-- pair. It uses the current build as the fallback build and leaves special
-- inventory image names to custom init functions.
GlassicAPI.BasicInitFn = function(inst)
	if inst.components.placer == nil and not TheWorld.ismastersim then
		return
	end

	local build_name = inst:GetSkinBuild()
	local def_build = inst.AnimState:GetBuild()
	inst.AnimState:SetSkin(build_name, def_build)
	if inst.components.inventoryitem then
		local skin_name = inst:GetSkinName()
		if inst.components.container and inst.components.container:IsOpen() then
			skin_name = skin_name .. "_open"
		end
		inst.components.inventoryitem:ChangeImageName(skin_name)
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
-- TechTree.Create fills missing AVAILABLE_TECH keys with 0 in place, so it must run
-- after the new tech has been inserted into AVAILABLE_TECH.
local function rebuild_techtree()
	TECH.NONE = TechTree.Create()

	for _, v in pairs(AllRecipes) do
		v.level = TechTree.Create(v.level)
	end

	for _, v in pairs(TUNING.PROTOTYPER_TREES) do
		TechTree.Create(v)
	end
end

-- custom tech allows you to build custom prototyper or allows muliti prototypers to bonus a tech simultaneously.
-- e.g. GlassicAPI.AddTech("FRIENDSHIPRING")
-- NOTE: TechTree builds AVAILABLE_TECH_* caches at load time. Current consumers
-- (builder/player_classified) fall back to string.lower(name).."_..." keys, so
-- updating the public arrays is enough for now; do not write the cache tables here.
---@param name string
---@param bonus_available? boolean
GlassicAPI.AddTech = function(name, bonus_available)
	table.insert(TechTree.AVAILABLE_TECH, name)
	if bonus_available then
		table.insert(TechTree.BONUS_TECH, name)
	end
	rebuild_techtree()
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
	-- OnUpdate still fills searched_recipes for hidden recipes in the background.
	if HIDDEN_RECIPES[name] then
		return
	end
	return is_recipe_valid_for_search(self, name)
end

local function init_recipe_print(...)
	if KnownModIndex:IsModInitPrintEnabled() then
		print("Glassic API", ...)
	end
end

-- Picks the default filter the same way official AddRecipe2/AddCharacterRecipe do:
-- exactly one of CRAFTING_STATION, CHARACTER, MODS. nomods/nochar only suppress
-- the branch they belong to.
---@param config? table
local function get_default_recipe_filter(config)
	config = config or {}
	if config.nounlock then
		return CRAFTING_FILTERS.CRAFTING_STATION.name
	end
	if (config.builder_tag or config.builder_skill) and config.nochar == nil then
		return CRAFTING_FILTERS.CHARACTER.name
	end
	if config.nomods == nil then
		return CRAFTING_FILTERS.MODS.name
	end
end

-- a smarter way to add a mod recipe, and you don't need to think about filters too much.
-- also, with config.hidden, you can set your recipe no searching or in "EVERYTHING" filter.
-- same format as AddRecipe2
---@param mod_env table
---@param name string
---@param ingredients table
---@param tech table
---@param config? table
---@param filters? table
local function add_recipe(mod_env, name, ingredients, tech, config, filters)
	init_recipe_print("AddRecipe", name)
	require("recipe")
	---@diagnostic disable-next-line lowercase-global
	mod_protect_Recipe = false
	local rec = Recipe2(name, ingredients, tech, config)

	if not rec.is_deconstruction_recipe then
		local default_filter = get_default_recipe_filter(config)
		if default_filter then
			mod_env.AddRecipeToFilter(name, default_filter)
		end

		HIDDEN_RECIPES[name] = (config and config.hidden) or nil

		if filters then
			for _, filter_name in ipairs(filters) do
				mod_env.AddRecipeToFilter(name, filter_name)
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

---@param strings table<string, string> keys like "STRINGS.UI.TEXT"
local function apply_translations(strings)
	for path, value in pairs(strings) do
		local rest = path:match("^STRINGS%.(.+)$")
		local node, last = rest and STRINGS, nil
		for part in (rest or ""):gmatch("[^%.]+") do
			if last ~= nil then
				node = type(node[last]) == "table" and node[last] or nil
			end
			last = part
		end
		if node and type(node[last]) == "string" then
			node[last] = value
		end
	end
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
	local merged = LanguageTranslator.languages[temp_lang]
	local target = LanguageTranslator.languages[lang]
	LanguageTranslator.languages[temp_lang] = nil
	LanguageTranslator.defaultlang = _defaultlang
	if not (target and merged) then
		print("Glassic API: no loaded translation for " .. tostring(lang) .. ", skip merging " .. filepath)
		return
	end
	merge_internal(target, merged)
	-- Only the entries this PO contributed are applied: re-running the whole STRINGS
	-- table would overwrite strings other mods already set.
	apply_translations(merged)
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

-- Functions that register post-init data or recipes run once per mod at load time: bound
-- to the calling mod's env so failures are attributed to that mod and its priority
-- decides the run order. Everything else is read straight from GlassicAPI.
local ENV_API = {
	InitCharacterAssets = init_character_assets,
	InitMinimapAtlas = init_minimap_atlas,
	SetOnequipSkinItem = add_onquip_skin_item,
	AddRecipe = add_recipe,
}

local env_apis = setmetatable({}, { __mode = "k" })
local function get_env_api(mod_env)
	if mod_env == ENV then
		return GlassicAPI
	end
	local api = env_apis[mod_env]
	if not api then
		api = {}
		for name, fn in pairs(ENV_API) do
			api[name] = function(...)
				return fn(mod_env, ...)
			end
		end
		setmetatable(api, { __index = GlassicAPI })
		env_apis[mod_env] = api
	end
	return api
end

for name, fn in pairs(ENV_API) do
	GlassicAPI[name] = function(...)
		return fn(ENV, ...)
	end
end

local initialize_modmain = ModManager.InitializeModMain
ModManager.InitializeModMain = function(self, _modname, env, mainfile, ...)
	if mainfile == "modmain.lua" then
		env.GlassicAPI = get_env_api(env)
	end
	return initialize_modmain(self, _modname, env, mainfile, ...)
end

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
