local CommonAction = Class(function(self, inst)
	self.inst = inst
	self.state = "dolongaction"
	self.component_actions = {}
end)

---@param action table
function CommonAction:SetAction(action)
	action.code = ACTIONS.COMMON_ACTION.code
	action.id = action.id or action.str or ACTIONS.COMMON_ACTION.id
	self.action = action
end

---@param state string | function
function CommonAction:SetActionState(state)
	self.state = state
	self.action.state = state
end

---@return boolean
function CommonAction:GetActionState(bufferedaction)
	return FunctionOrValue(self.state, self, bufferedaction)
end

---@param type "SCENE" | "USEITEM" | "POINT" | "EQUIPPED" | "INVENTORY"
---@param fn function
function CommonAction:SetActionCollector(type, fn)
	self.component_actions[type] = fn
end

---@param type string
---@param actions table<number, table>
---@param inst table
---@param doer table
---@param target table | nil
---@param pos table | nil
---@param right boolean | nil
function CommonAction:CollectActions(type, actions, inst, doer, target, pos, right)
	if self.action
		and self.component_actions[type] and self.component_actions[type](inst, doer, target, pos, right)
	then
		table.insert(actions, self.action)
	end
end

return CommonAction
