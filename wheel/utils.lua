local M = {}

M.COOLDOWN_REFRESH_INTERVAL = .5

M.DYNAMIC_FIELDS =
{
	"get_spell_state",
	"get_cooldown_percent",
	"get_active_duration_percent",
	"checkcooldown",
	"checkenabled",
	"cooldownscale",
	"cooldowncolor",
	"spell_toggle",
}

function M.GetSpellItemKey(item)
	return item ~= nil and (item.spell_id or item.label) or nil
end

function M.ResolveValue(value, owner, fallback)
	local result = value
	for _ = 1, 2 do
		if type(result) == "function" then
			result = result(owner)
		else
			break
		end
	end
	-- Must accept explicit false/0; `x ~= nil and x or fallback` turns false into fallback.
	if result == nil then
		return fallback
	end
	return result
end

function M.ResolveColor(value, owner, fallback)
	local color = M.ResolveValue(value, owner, fallback)
	if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil or color[4] == nil then
		return fallback
	end
	return color
end

function M.AreColorsEqual(a, b)
	return a ~= nil
		and b ~= nil
		and a[1] == b[1]
		and a[2] == b[2]
		and a[3] == b[3]
		and a[4] == b[4]
end

return M
