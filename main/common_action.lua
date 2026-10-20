local AddAction = AddAction
local AddComponentAction = AddComponentAction
local AddStategraphActionHandler = AddStategraphActionHandler
GLOBAL.setfenv(1, GLOBAL)

local HIGH_ACTION_PRIORITY = 10
local COMMON_ACTION = Action({ priority = HIGH_ACTION_PRIORITY })
COMMON_ACTION.id = "COMMON_ACTION"
COMMON_ACTION.str = "COMMON_ACTION"
AddAction(COMMON_ACTION)

local actionhandler = ActionHandler(COMMON_ACTION, function(_, bufferedaction)
	if bufferedaction.invobject and bufferedaction.invobject.components.commonaction then
		return bufferedaction.invobject.components.commonaction:GetActionState(bufferedaction)
	elseif bufferedaction.target and bufferedaction.target.components.commonaction then
		return bufferedaction.target.components.commonaction:GetActionState(bufferedaction)
	end
	return "dolongaction"
end)
AddStategraphActionHandler("wilson", actionhandler)
AddStategraphActionHandler("wilson_client", actionhandler)

AddComponentAction("SCENE", "commonaction", function(inst, doer, actions, right)
	if inst.components.commonaction then
		inst.components.commonaction:CollectActions("SCENE", actions, inst, doer, nil, nil, right)
	end
end)

AddComponentAction("USEITEM", "commonaction", function(inst, doer, target, actions, right)
	if inst.components.commonaction then
		inst.components.commonaction:CollectActions("USEITEM", actions, inst, doer, target, nil, right)
	end
end)

AddComponentAction("POINT", "commonaction", function(inst, doer, pos, actions, right, target)
	if inst.components.commonaction then
		inst.components.commonaction:CollectActions("POINT", actions, inst, doer, target, pos, right)
	end
end)

AddComponentAction("EQUIPPED", "commonaction", function(inst, doer, target, actions, right)
	if inst.components.commonaction then
		inst.components.commonaction:CollectActions("EQUIPPED", actions, inst, doer, target, nil, right)
	end
end)

AddComponentAction("INVENTORY", "commonaction", function(inst, doer, actions, right)
	if inst.components.commonaction then
		inst.components.commonaction:CollectActions("INVENTORY", actions, inst, doer, nil, nil, right)
	end
end)

local _PreviewAction = StateGraphInstance.PreviewAction

-- Actions from other mods share the code counter, so match mod_name too. Only actions
-- registered by this mod get the common action handler injected.
local function ensure_common_action_handler(sg, action)
	if sg.actionhandlers and not sg.actionhandlers[action] and action.code == ACTIONS.COMMON_ACTION.code and action.mod_name == ACTIONS.COMMON_ACTION.mod_name then
		sg.actionhandlers[action] = sg.actionhandlers[ACTIONS.COMMON_ACTION]
	end
end

---@diagnostic disable-next-line duplicate-set-filed
function StateGraphInstance:PreviewAction(bufferedaction, ...)
	ensure_common_action_handler(self.sg, bufferedaction.action)
	return _PreviewAction(self, bufferedaction, ...)
end

local _StartAction = StateGraphInstance.StartAction
---@diagnostic disable-next-line duplicate-set-filed
function StateGraphInstance:StartAction(bufferedaction, ...)
	ensure_common_action_handler(self.sg, bufferedaction.action)
	return _StartAction(self, bufferedaction, ...)
end
