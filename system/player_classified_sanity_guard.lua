-- Client guard: vanilla player_classified OnSanityDirty assumes parent.replica.sanity
-- exists when sanitydirty fires. Timing / mod combo can leave replica unset → LUA ERROR.

-- =============================================================================
-- Private helpers
-- =============================================================================

-- C/lightuserdata listeners cannot store fields on the function value.
local ORIGINAL_TO_WRAPPED = setmetatable({}, { __mode = "k" })
local IS_WRAPPED = setmetatable({}, { __mode = "k" })

local function GetClassifiedParent(classified)
    local parent = classified._parent
    if parent == nil and classified.entity ~= nil then
        parent = classified.entity:GetParent()
        if parent ~= nil then
            classified._parent = parent
        end
    end
    return parent
end

local function HasParentSanityReplica(parent)
    local sanity = parent ~= nil and parent.replica ~= nil and parent.replica.sanity or nil
    return sanity ~= nil
        and sanity.GetSanityMode ~= nil
        and sanity.Max ~= nil
        and sanity.GetPenaltyPercent ~= nil
end

local function ResetSanityDirtyLocals(classified)
    if classified.maxsanity ~= nil and classified.currentsanity ~= nil then
        local maxsanity = classified.maxsanity:value()
        classified._oldsanitypercent = maxsanity > 0
            and classified.currentsanity:value() / maxsanity
            or 1
    else
        classified._oldsanitypercent = 1
    end
    classified.issanitypulseup:set_local(false)
    classified.issanitypulsedown:set_local(false)
end

local function GuardBeforeSanityDirty(classified)
    GetClassifiedParent(classified)
end

local function WrapSanityDirtyHandler(fn)
    if fn == nil then
        return fn
    end
    if IS_WRAPPED[fn] then
        return fn
    end

    local existing = ORIGINAL_TO_WRAPPED[fn]
    if existing ~= nil then
        return existing
    end

    local wrapped = function(classified, data)
        GuardBeforeSanityDirty(classified)
        local parent = GetClassifiedParent(classified)
        if not HasParentSanityReplica(parent) then
            ResetSanityDirtyLocals(classified)
            return
        end
        return fn(classified, data)
    end

    ORIGINAL_TO_WRAPPED[fn] = wrapped
    IS_WRAPPED[wrapped] = true
    return wrapped
end

local function WrapAllSanityDirtyListeners(classified)
    if classified == nil or classified._sanity_guard_wrapped_all then
        return false
    end

    local listeners = classified.event_listeners
    if listeners == nil then
        return false
    end

    local sanity_listeners = listeners.sanitydirty
    if sanity_listeners == nil then
        return false
    end

    local fns = sanity_listeners[classified]
    if fns == nil or #fns == 0 then
        return false
    end

    for i, fn in ipairs(fns) do
        if type(fn) == "function" then
            fns[i] = WrapSanityDirtyHandler(fn)
        end
    end

    classified._sanity_guard_wrapped_all = true
    return true
end

local function InstallSanityDirtyGuards(classified, attempt)
    if classified == nil or not classified:IsValid() then
        return
    end

    if WrapAllSanityDirtyListeners(classified) then
        return
    end

    attempt = attempt or 1
    if attempt < 5 then
        classified:DoStaticTaskInTime(0, function()
            InstallSanityDirtyGuards(classified, attempt + 1)
        end)
    end
end

-- =============================================================================
-- Public API
-- =============================================================================

local function InstallClientGuard()
    AddPrefabPostInit("player_classified", function(inst)
        if TheNet:IsDedicated() then
            return
        end
        if TheWorld ~= nil and TheWorld.ismastersim then
            return
        end

        -- Register before vanilla DoStaticTaskInTime(0, RegisterNetListeners).
        inst:ListenForEvent("sanitydirty", GuardBeforeSanityDirty)

        -- Wrap vanilla + other mod handlers after they register.
        inst:DoStaticTaskInTime(0, function()
            InstallSanityDirtyGuards(inst, 1)
        end)
    end)
end

InstallClientGuard()
