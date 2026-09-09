GLOBAL.setfenv(1, GLOBAL)

local SKIN_AFFINITY_INFO = require("skin_affinity_info")
local ALL_MOD_SKINS = {}
local HEADSKIN_CHARACTERS = {}
local OVERRIDE_RARITY_DATA = {}
local CHARACTER_EXCLUSIVE_SKINS = {}
local OFFICIAL_PREFAB_SKINS = {}

for _, skins in pairs(PREFAB_SKINS) do
	for _, skin in pairs(skins) do
		OFFICIAL_PREFAB_SKINS[skin] = true
	end
end

local function get_player_from_id(id)
	if type(id) == "table" then -- If it's an entity
		return id.prefab and id or nil
	end
	for _, player in ipairs(AllPlayers) do
		if player.userid == id then
			return player
		end
	end
end

local function get_mod_skins()
	return shallowcopy(ALL_MOD_SKINS)
end

local function add_mod_skin(skin, test_fn)
	if OFFICIAL_PREFAB_SKINS[skin] then
		return
	end
	ALL_MOD_SKINS[skin] = test_fn or true
end

local function remove_mod_skin(skin)
	ALL_MOD_SKINS[skin] = nil
end

local function validate_mod_skin(skin, userid)
	local test_fn = ALL_MOD_SKINS[skin]
	if userid then
		local player = get_player_from_id(userid)
		local characters = CHARACTER_EXCLUSIVE_SKINS[skin]
		if player and characters then
			return table.contains(characters, player.prefab)
		end
	end
	return FunctionOrValue(test_fn, skin, userid)
end

local function set_character_exlusive_skin(skin, characters)
	CHARACTER_EXCLUSIVE_SKINS[skin] = type(characters) == "string" and { characters } or characters
end

local function does_character_have_skin(skin, character)
	local characters = CHARACTER_EXCLUSIVE_SKINS[skin]
	if characters then
		character = type(character) == "table" and character.prefab or character
		if character then
			return table.contains(characters, character)
		end
	end
	return true
end

-- Skin index for networking between server and clients
local function index_skin_ids(prefab)
	PREFAB_SKINS_IDS[prefab] = {}
	for index, skin in pairs(PREFAB_SKINS[prefab] or {}) do
		PREFAB_SKINS_IDS[prefab][skin] = index
	end
end

local get_full_inventory = InventoryProxy.GetFullInventory
InventoryProxy.GetFullInventory = function(...)
	local items = get_full_inventory(...)
	for skin_name in pairs(ALL_MOD_SKINS) do
		if validate_mod_skin(skin_name, TheNet:GetUserID()) then
			table.insert(items, {
				item_type = skin_name,
				modified_time = 0,
				item_id = "1",
			})
		end
	end
	return items
end

local check_ownership = InventoryProxy.CheckOwnership
InventoryProxy.CheckOwnership = function(self, skin, ...)
	if validate_mod_skin(skin) then
		return true
	end
	return check_ownership(self, skin, ...)
end

local check_client_ownership = InventoryProxy.CheckClientOwnership
InventoryProxy.CheckClientOwnership = function(self, userid, skin, ...)
	if validate_mod_skin(skin, userid) then
		return true
	end
	return check_client_ownership(self, userid, skin, ...)
end

local check_ownership_get_latest = InventoryProxy.CheckOwnershipGetLatest
InventoryProxy.CheckOwnershipGetLatest = function(self, item_type, ...)
	if validate_mod_skin(item_type, TheNet:GetUserID()) then
		return true, -2333 -- :nope:
	end
	return check_ownership_get_latest(self, item_type, ...)
end

local anim_state_to_entity = {}

local function clean_up_mapping(inst)
	if inst.AnimState then
		anim_state_to_entity[inst.AnimState] = nil
	end
end

local add_anim_state = Entity.AddAnimState
function Entity:AddAnimState(...)
	local anim_state = add_anim_state(self, ...)

	local guid = self:GetGUID()
	local inst = Ents[guid]
	anim_state_to_entity[anim_state] = inst
	inst:ListenForEvent("onremove", clean_up_mapping)

	return anim_state
end

local get_skin_build = AnimState.GetSkinBuild
function AnimState:GetSkinBuild(...)
	local inst = anim_state_to_entity[self]
	local skin_build = get_skin_build(self, ...)
	return (skin_build ~= "" and skin_build) or (inst and inst:GetSkinBuild()) or ""
end

local function generate_skin_id(name)
	if type(name) == "string" then
		local res = 0x1505
		local sid = TheWorld.meta.session_identifier
		local str = name .. sid
		for i = 1, #str do
			res = ((res * 0x21) % 0x80000000) + string.byte(str:sub(i, i))
		end
		return res
	end
end

local function init_mod_skin(ent, skin)
	ent.skinname = skin
	ent.skin_id = generate_skin_id(skin)

	local init_fn = Prefabs[skin].init_fn
	if init_fn then
		init_fn(ent)
	end
end

local spawn_prefab = SpawnPrefab
SpawnPrefab = function(name, skin, skin_id, creator, ...)
	local ent = spawn_prefab(name, skin, skin_id, creator, ...)
	if validate_mod_skin(skin, creator) then
		init_mod_skin(ent, skin)
	end
	return ent
end

local reskin_entity = Sim.ReskinEntity
Sim.ReskinEntity = function(self, guid, targetskinname, reskinname, skin_id, userid, ...)
	local ent = Ents[guid]
	-- Reskin Entity
	local ret = { reskin_entity(self, guid, targetskinname, reskinname, skin_id, userid, ...) }
	-- Execute mod skin init_fn
	if validate_mod_skin(reskinname, userid) then
		init_mod_skin(ent, reskinname)
	end
	return unpack(ret)
end

local function apply_temp_character(base_fn, ...)
	if IsTableEmpty(HEADSKIN_CHARACTERS) then
		return base_fn(...)
	end
	local added_characters = {}
	for character in pairs(HEADSKIN_CHARACTERS) do
		if not table.contains(DST_CHARACTERLIST, character) then
			table.insert(DST_CHARACTERLIST, character)
			added_characters[character] = true
		end
	end
	local ret = { base_fn(...) }
	for i = #DST_CHARACTERLIST, 1, -1 do
		if added_characters[DST_CHARACTERLIST[i]] then
			table.remove(DST_CHARACTERLIST, i)
		end
	end
	return unpack(ret)
end

local function apply_temp_inv_item_list(base_fn, char, ...)
	if not char then
		return base_fn(...)
	end

	local inv_item_list = (
		TUNING.GAMEMODE_STARTING_ITEMS[TheNet:GetServerGameMode()] or TUNING.GAMEMODE_STARTING_ITEMS.DEFAULT
	)[string.upper(char)]
	local copy = shallowcopy(inv_item_list)

	if inv_item_list and #inv_item_list > 0 then
		for i, item in ipairs(inv_item_list) do
			if PREFAB_SKINS[item] then
				local prefab_skins = {}
				for _, skin in ipairs(PREFAB_SKINS[item]) do
					if does_character_have_skin(skin, char) then
						table.insert(prefab_skins, skin)
					end
				end
				if #prefab_skins == 0 then
					table.remove(inv_item_list, i)
				end
			end
		end
	end

	local ret = { base_fn(...) }
	inv_item_list = copy
	return unpack(ret)
end

local validate_spawn_prefab_request = ValidateSpawnPrefabRequest
ValidateSpawnPrefabRequest = function(...)
	return apply_temp_character(validate_spawn_prefab_request, ...)
end

local LoadoutSelect = require("widgets/redux/loadoutselect")
local LoadoutSelect_ctor = LoadoutSelect._ctor
LoadoutSelect._ctor = function(...)
	return apply_temp_character(LoadoutSelect_ctor, ...)
end

local LoadoutSelect_ShouldShowStartingItemSkinsButton = LoadoutSelect._ShouldShowStartingItemSkinsButton
---@diagnostic disable-next-line: duplicate-set-field
function LoadoutSelect:_ShouldShowStartingItemSkinsButton(...) -- :angri:
	return apply_temp_inv_item_list(LoadoutSelect_ShouldShowStartingItemSkinsButton, self.currentcharacter, self, ...)
end

local apply_skin_presets = LoadoutSelect.ApplySkinPresets
---@diagnostic disable-next-line: duplicate-set-field
LoadoutSelect.ApplySkinPresets = function(...)
	return apply_temp_character(apply_skin_presets, ...)
end

local SkinPresetsPopup = require("screens/redux/skinpresetspopup")
local SkinPresetsPopup_ctor = SkinPresetsPopup._ctor
SkinPresetsPopup._ctor = function(self, ...)
	local ret = { apply_temp_character(SkinPresetsPopup_ctor, self, ...) }

	local scroll_widget_apply = self.scroll_list.update_fn
	self.scroll_list.update_fn = function(...)
		return apply_temp_character(scroll_widget_apply, ...)
	end

	return unpack(ret)
end

local DefaultSkinSelectionPopup = require("screens/redux/defaultskinselection")
local DefaultSkinSelectionPopup_ctor = DefaultSkinSelectionPopup._ctor
function DefaultSkinSelectionPopup:_ctor(...)
	return apply_temp_inv_item_list(DefaultSkinSelectionPopup_ctor, self.character, self, ...)
end
local DefaultSkinSelectionPopup_GetSkinsList = DefaultSkinSelectionPopup.GetSkinsList
---@diagnostic disable-next-line: duplicate-set-field
DefaultSkinSelectionPopup.GetSkinsList = function(self, ...)
	local previous_check_ownership = InventoryProxy.CheckOwnership
	InventoryProxy.CheckOwnership = function(inventory, name, ...)
		if not does_character_have_skin(name, self.character) then
			return false
		end
		return previous_check_ownership(inventory, name, ...)
	end
	local ret = { DefaultSkinSelectionPopup_GetSkinsList(self, ...) }
	InventoryProxy.CheckOwnership = previous_check_ownership
	return unpack(ret)
end

local function is_character(prefab)
	return table.contains(GetActiveCharacterList(), prefab)
end

local function add_mod_skins(data)
	for base_prefab, prefab_skins in pairs(data) do
		if is_character(base_prefab) then
			HEADSKIN_CHARACTERS[base_prefab] = true
		end
		if not PREFAB_SKINS[base_prefab] then
			PREFAB_SKINS[base_prefab] = {}
		end
		for _, skin_data in ipairs(prefab_skins) do
			local skin_name = type(skin_data) == "table" and skin_data.name or skin_data
			if is_character(base_prefab) and skin_name ~= base_prefab .. "_none" then
				if not SKIN_AFFINITY_INFO[base_prefab] then
					SKIN_AFFINITY_INFO[base_prefab] = {}
				end
				if not table.contains(SKIN_AFFINITY_INFO[base_prefab], skin_name) then
					table.insert(SKIN_AFFINITY_INFO[base_prefab], skin_name)
				end
			end
			if not table.contains(PREFAB_SKINS[base_prefab], skin_name) then
				table.insert(PREFAB_SKINS[base_prefab], skin_name)
			end
			add_mod_skin(skin_name, type(skin_data) == "table" and skin_data.test_fn)
			set_character_exlusive_skin(skin_name, type(skin_data) == "table" and skin_data.exclusive_char)
		end
		index_skin_ids(base_prefab)
	end
end

local AccountItemFrame = require("widgets/redux/accountitemframe")
local original_set_rarity = AccountItemFrame._SetRarity
---@diagnostic disable-next-line: duplicate-set-field
AccountItemFrame._SetRarity = function(self, rarity, ...)
	local mod_rarity_data = OVERRIDE_RARITY_DATA[rarity]
	if mod_rarity_data then
		local build = mod_rarity_data.build or "frame_BG"
		local symbol = mod_rarity_data.symbol or mod_rarity_data.build and rarity or GetFrameSymbolForRarity(rarity)
		self:GetAnimState():OverrideSymbol("SWAP_frameBG", build, symbol)
	else
		return original_set_rarity(self, rarity, ...)
	end
end

local function set_rarity(rarity, order, color, override_symbol, override_build)
	RARITY_ORDER[rarity] = order
	SKIN_RARITY_COLORS[rarity] = color
	if override_symbol or override_build then
		OVERRIDE_RARITY_DATA[rarity] = {
			symbol = override_symbol,
			build = override_build,
		}
	else
		OVERRIDE_RARITY_DATA[rarity] = nil
	end
end

GlassicAPI.SkinHandler = {
	GetModSkins = get_mod_skins,
	AddModSkin = add_mod_skin,
	RemoveModSkin = remove_mod_skin,
	IsModSkin = validate_mod_skin, -- Backward compatible
	IsValidModSkin = validate_mod_skin, -- Backward compatible
	ValidateModSkin = validate_mod_skin,

	GetPlayerFromID = get_player_from_id,
	SetCharacterExclusiveSkin = set_character_exlusive_skin,
	DoesCharacterHaveSkin = does_character_have_skin,
	DoesCharacterHasSkin = does_character_have_skin, -- Backward compatible

	AddModSkins = add_mod_skins, -- Import skin data
	SetRarity = set_rarity,
}
