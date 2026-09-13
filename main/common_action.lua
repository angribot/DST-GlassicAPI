local AddAction = AddAction
local AddComponentAction = AddComponentAction
local AddStategraphActionHandler = AddStategraphActionHandler
GLOBAL.setfenv(1, GLOBAL)

local HIGH_ACTION_PRIORITY = 10
local COMMON_ACTION = Action({priority = HIGH_ACTION_PRIORITY})
COMMON_ACTION.id = "COMMON_ACTION"
COMMON_ACTION.str = "COMMON_ACTION"
AddAction(COMMON_ACTION)

local actionhandler = ActionHandler(COMMON_ACTION, function(_, bufferedaction)
	if bufferedaction.invobject and bufferedaction.invobject.components.commonaction then
		return bufferedaction.invobject.components.commonaction:GetActionState()
	elseif bufferedaction.target and bufferedaction.target.components.commonaction then
		return bufferedaction.target.components.commonaction:GetActionState()
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
---@diagnostic disable-next-line duplicate-set-filed
function StateGraphInstance:PreviewAction(bufferedaction, ...)
	if self.sg.actionhandlers
		and not self.sg.actionhandlers[bufferedaction.action]
		and bufferedaction.action.code == ACTIONS.COMMON_ACTION.code
	then
		self.sg.actionhandlers[bufferedaction.action] = self.sg.actionhandlers[ACTIONS.COMMON_ACTION]
	end
	return _PreviewAction(self, bufferedaction, ...)
end

local _StartAction = StateGraphInstance.StartAction
---@diagnostic disable-next-line duplicate-set-filed
function StateGraphInstance:StartAction(bufferedaction, ...)
	if self.sg.actionhandlers
		and not self.sg.actionhandlers[bufferedaction.action]
		and bufferedaction.action.code == ACTIONS.COMMON_ACTION.code
	then
		self.sg.actionhandlers[bufferedaction.action] = self.sg.actionhandlers[ACTIONS.COMMON_ACTION]
	end
	return _StartAction(self, bufferedaction, ...)
end
