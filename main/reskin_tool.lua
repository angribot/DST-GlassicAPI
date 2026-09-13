local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

local function validate_modchar_beard(doer, target)
	local prefab_to_skin = target.prefab .. "_beard"
	if PREFAB_SKINS[prefab_to_skin] ~= nil then
		for _, item_type in pairs(PREFAB_SKINS[prefab_to_skin]) do
			if TheInventory:CheckClientOwnership(doer.userid, item_type) then
				return true
			end
		end
	end

	local curr_skin = target.components.beard.skinname
	if curr_skin ~= nil then
		return true
	end

	return false
end

AddPrefabPostInit("reskin_tool", function(inst)
	if not TheWorld.ismastersim then
		return
	end
	if inst.components.spellcaster then
		local can_cast_fn = inst.components.spellcaster.can_cast_fn
		inst.components.spellcaster:SetCanCastFn(function(doer, target, ...)
			if table.contains(MODCHARACTERLIST, target.prefab) then
				if
					doer.userid == target.userid
					and target.components.beard
					and target.components.beard.is_skinnable
				then
					return validate_modchar_beard(doer, target)
				end
				return false
			end
			return can_cast_fn(doer, target, ...)
		end)
	end
end)
