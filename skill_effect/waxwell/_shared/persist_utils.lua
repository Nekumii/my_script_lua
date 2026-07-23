local M = {}

function M.HasFlagOrTag(inst, flagname, tag)
    return inst ~= nil
        and ((flagname ~= nil and inst[flagname])
            or (tag ~= nil and inst:HasTag(tag)))
end

function M.MarkFlagAndTag(inst, flagname, tag, onmark)
    if inst == nil then
        return
    end

    if flagname ~= nil then
        inst[flagname] = true
    end
    if onmark ~= nil then
        onmark(inst)
    end
    if tag ~= nil and not inst:HasTag(tag) then
        inst:AddTag(tag)
    end
end

function M.SaveFlag(data, key, enabled)
    if data ~= nil and enabled then
        data[key] = true
    end
end

function M.SaveValue(data, key, value)
    if data ~= nil and value ~= nil then
        data[key] = value
    end
end

function M.SaveRemainingTime(data, key, endtime)
    if data == nil or key == nil or endtime == nil then
        return
    end

    data[key] = math.max(0, endtime - GetTime())
end

function M.GetSavedRemainingTime(data, key)
    local value = data ~= nil and data[key] or nil
    return type(value) == "number" and value or 0
end

function M.SaveMarkedFlags(data, inst, specs)
    if data == nil or inst == nil or specs == nil then
        return
    end

    for _, spec in ipairs(specs) do
        if spec ~= nil and spec.key ~= nil and spec.has ~= nil and spec.has(inst) then
            data[spec.key] = true
        end
    end
end

function M.RestoreMarkedFlags(data, inst, specs)
    if data == nil or inst == nil or specs == nil then
        return
    end

    for _, spec in ipairs(specs) do
        if spec ~= nil and spec.key ~= nil and spec.mark ~= nil and data[spec.key] then
            spec.mark(inst)
        end
    end
end

return M