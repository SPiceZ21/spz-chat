-- server/main.lua — Global / crew / DM chat routing.
-- One inbound callback ("spz-chat:send") parses a leading /c, /w, /dm, /tell
-- or /g prefix to pick the channel; everything else is treated as global.
-- Usernames/crew tags come from spz-identity's profile cache.

local LastMsg = {} -- [source] = GetGameTimer() of last accepted message

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Resolve an online player by username (exact match first, then unique prefix).
--- @param name string
--- @return number|nil
local function FindSourceByUsername(name)
    local needle = name:lower()
    local prefixMatch, prefixCount = nil, 0

    for _, pid in ipairs(GetPlayers()) do
        local sid = tonumber(pid)
        local profile = exports['spz-identity']:GetProfile(sid)
        local uname = (profile and profile.username) or GetPlayerName(sid) or ''
        local lname = uname:lower()

        if lname == needle then
            return sid
        elseif lname:sub(1, #needle) == needle then
            prefixMatch, prefixCount = sid, prefixCount + 1
        end
    end

    if prefixCount == 1 then return prefixMatch end
    return nil
end

--- Broadcast a system line (join/leave/etc) to every connected player.
--- @param text string
local function SystemBroadcast(text)
    local payload = { channel = 'system', text = text, ts = os.time() }
    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('spz-chat:receive', tonumber(pid), payload)
    end
end

-- ── Send ─────────────────────────────────────────────────────────────────────

lib.callback.register('spz-chat:send', function(source, data)
    data = data or {}
    local raw = data.text

    if type(raw) ~= 'string' then return { ok = false } end
    raw = trim(raw:gsub('[\r\n]', ' '))
    if raw == '' then return { ok = false } end
    if #raw > Config.MaxLength then raw = raw:sub(1, Config.MaxLength) end

    local now = GetGameTimer()
    if LastMsg[source] and (now - LastMsg[source]) < Config.MinIntervalMs then
        return { ok = false, error = 'Slow down.' }
    end
    LastMsg[source] = now

    local profile  = exports['spz-identity']:GetProfile(source)
    local username = (profile and profile.username) or GetPlayerName(source) or ('Racer' .. source)
    local crewTag  = profile and profile.crew_tag or nil
    local avatar   = profile and profile.avatar_url or nil

    -- ── Parse channel prefix ──────────────────────────────────────────────
    local channel, target, text = 'global', nil, raw
    local lower = raw:lower()

    if lower == '/c' or lower:sub(1, 3) == '/c ' then
        channel = 'crew'
        text = raw:sub(3)
    elseif lower:sub(1, 6) == '/crew ' then
        channel = 'crew'
        text = raw:sub(6)
    elseif lower:sub(1, 3) == '/w ' or lower:sub(1, 4) == '/dm ' or lower:sub(1, 6) == '/tell ' then
        channel = 'dm'
        local rest = raw:sub((lower:sub(1, 6) == '/tell ') and 7 or (lower:sub(1, 4) == '/dm ') and 5 or 4)
        target, text = rest:match('^(%S+)%s*(.*)$')
    elseif lower:sub(1, 3) == '/g ' then
        channel = 'global'
        text = raw:sub(3)
    end

    text = text and trim(text) or ''
    if text == '' then return { ok = false, error = channel == 'dm' and 'Usage: /w <name> <message>' or 'Empty message' } end

    -- ── Crew ────────────────────────────────────────────────────────────
    if channel == 'crew' then
        if not profile or not profile.crew_id then
            return { ok = false, error = 'You are not in a crew.' }
        end

        local payload = { channel = 'crew', from = username, crewTag = crewTag, avatar = avatar, text = text, ts = os.time() }
        local members = exports['spz-identity']:GetOnlineCrewMembers(profile.crew_id)
        for _, sid in ipairs(members) do
            TriggerClientEvent('spz-chat:receive', sid, payload)
        end
        return { ok = true }
    end

    -- ── DM ──────────────────────────────────────────────────────────────
    if channel == 'dm' then
        if not target or target == '' then
            return { ok = false, error = 'Usage: /w <name> <message>' }
        end

        local targetSource = FindSourceByUsername(target)
        if not targetSource then
            return { ok = false, error = ('Player "%s" not found.'):format(target) }
        end
        if targetSource == source then
            return { ok = false, error = 'Cannot DM yourself.' }
        end

        local toProfile = exports['spz-identity']:GetProfile(targetSource)
        local toName   = (toProfile and toProfile.username) or GetPlayerName(targetSource)
        local toAvatar = toProfile and toProfile.avatar_url or nil

        TriggerClientEvent('spz-chat:receive', targetSource, { channel = 'dm', from = username, avatar = avatar, text = text, ts = os.time(), dir = 'in' })
        TriggerClientEvent('spz-chat:receive', source, { channel = 'dm', from = toName, avatar = toAvatar, text = text, ts = os.time(), dir = 'out' })
        return { ok = true }
    end

    -- ── Global ──────────────────────────────────────────────────────────
    local payload = { channel = 'global', from = username, crewTag = crewTag, avatar = avatar, text = text, ts = os.time() }
    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('spz-chat:receive', tonumber(pid), payload)
    end
    return { ok = true }
end)

-- ── Online players (for DM target autocomplete) ───────────────────────────────

lib.callback.register('spz-chat:online', function(source)
    local list = {}
    for _, pid in ipairs(GetPlayers()) do
        local sid = tonumber(pid)
        if sid ~= source then
            local profile = exports['spz-identity']:GetProfile(sid)
            list[#list + 1] = {
                username = (profile and profile.username) or GetPlayerName(sid) or ('Racer' .. sid),
                avatar = profile and profile.avatar_url or nil,
            }
        end
    end
    return list
end)

-- ── Join / leave system lines ──────────────────────────────────────────────────

AddEventHandler('SPZ:playerReady', function(source, profile)
    local name = (profile and profile.username) or GetPlayerName(source) or 'A racer'
    SystemBroadcast(name .. ' connected.')
end)

AddEventHandler('SPZ:playerDisconnected', function(source)
    local profile = exports['spz-identity']:GetProfile(source)
    local name = (profile and profile.username) or GetPlayerName(source) or 'A racer'
    SystemBroadcast(name .. ' disconnected.')
    LastMsg[source] = nil
end)
