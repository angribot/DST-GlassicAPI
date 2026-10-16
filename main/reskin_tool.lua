local AddPrefabPostInit = AddPrefabPostInit
GLOBAL.setfenv(1, GLOBAL)

-- Official can_cast_fn only restricts beard reskinning to the owner for DST_CHARACTERLIST.
-- Temporarily add the mod character so the official checks (target redirect, _playerlink,
-- reskin_tool_cannot_target_this, GetNextSkin, PREFAB_SKINS_SHOULD_NOT_SELECT) all apply.
local function call_as_dst_character(fn, prefab, ...)
	if not table.contains(MODCHARACTERLIST, prefab) or table.contains(DST_CHARACTERLIST, prefab) then
		return fn(...)
	end
	table.insert(DST_CHARACTERLIST, prefab)
	local ret = { fn(...) }
	for i = #DST_CHARACTERLIST, 1, -1 do
		if DST_CHARACTERLIST[i] == prefab then
			table.remove(DST_CHARACTERLIST, i)
			break
		end
	end
	return unpack(ret)
end

AddPrefabPostInit("reskin_tool", function(inst)
	if not TheWorld.ismastersim then
		return
	end
	local spellcaster = inst.components.spellcaster
	local can_cast_fn = spellcaster and spellcaster.can_cast_fn
	if not can_cast_fn then
		return
	end
	spellcaster:SetCanCastFn(function(doer, target, ...)
		-- Mirror the official redirect to find the prefab that will actually be checked.
		local real_target = target
		if target.reskin_tool_target_redirect and target.reskin_tool_target_redirect:IsValid() then
			real_target = target.reskin_tool_target_redirect
		end
		return call_as_dst_character(can_cast_fn, real_target.prefab, doer, target, ...)
	end)
end)
