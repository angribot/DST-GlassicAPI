-- Tool designed by Rezecib.
-- Personal Changed by Tony.
-- Changed by Civi again.
local modname = modname
GLOBAL.setfenv(1, GLOBAL)

local function GetUpvalueHelper(entry_fn, entry_name)
	local i = 1
	while true do
		local name, value = debug.getupvalue(entry_fn, i)
		if name == entry_name then
			return value, i
		elseif name == nil then
			return
		end
		i = i + 1
	end
end

local function GetUpvalue(fn, path)
	local prv, i = nil, nil
	for var in path:gmatch("[^%.]+") do
		prv = fn
		fn, i = GetUpvalueHelper(fn, var)
		if not fn then
			break
		end
	end
	return fn, i, prv
end

local function SetUpvalue(start_fn, path, new_fn)
	local _, fn_i, scope_fn = GetUpvalue(start_fn, path)
	if not fn_i then
		print("Didn't find " .. path .. " from", start_fn)
		return
	end
	debug.setupvalue(scope_fn, fn_i, new_fn)
end

GlassicAPI.UpvalueUtil = {
	parant = modname,
	GetUpvalue = GetUpvalue,
	SetUpvalue = SetUpvalue,
}
