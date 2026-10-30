-- client/main.lua — Chat box: always-visible log, T opens the input.
-- Slash-command autocomplete is resolved locally from GetRegisteredCommands();
-- DM target autocomplete comes from the server's online-player list. The
-- server owns channel routing (global/crew/dm) — this side just captures
-- input and renders what it's sent.

local open = false

-- Mirrors the exact prefix rules server/main.lua uses to route a message —
-- must match precisely (including the required trailing space) so a bare
-- "/crew" still opens the crew dashboard command instead of being read as
-- an empty "/crew <msg>" chat line.
local function isChatPrefixed(text)
    local lower = text:lower()
    if lower == '/c' or lower:sub(1, 3) == '/c ' then return true end
    if lower:sub(1, 6) == '/crew ' then return true end
    if lower:sub(1, 3) == '/w ' or lower:sub(1, 4) == '/dm ' or lower:sub(1, 6) == '/tell ' then return true end
    if lower:sub(1, 3) == '/g ' then return true end
    return false
end

-- Descriptions and argument hints, from the standard chat:addSuggestion
-- events any resource can fire (same API as the default cfx chat):
--   TriggerEvent('chat:addSuggestion', '/carcode', 'Copy the car spawn code', {
--       { name = 'id', help = 'player id' } })
-- Plus the chat's own routing shortcuts, which are not registered commands.
local Suggestions = {
    c    = { help = 'Message your crew',            params = { { name = 'message' } } },
    g    = { help = 'Message everyone (global)',    params = { { name = 'message' } } },
    w    = { help = 'Private message a player',     params = { { name = 'player' }, { name = 'message' } } },
    dm   = { help = 'Private message a player',     params = { { name = 'player' }, { name = 'message' } } },
    tell = { help = 'Private message a player',     params = { { name = 'player' }, { name = 'message' } } },
}

local function suggestionKey(name)
    return tostring(name or ''):gsub('^/', ''):lower()
end

local function addSuggestion(name, help, params)
    local key = suggestionKey(name)
    if key == '' then return end
    local clean = {}
    for _, p in ipairs(type(params) == 'table' and params or {}) do
        if type(p) == 'table' and p.name then
            clean[#clean + 1] = { name = tostring(p.name), help = p.help and tostring(p.help) or nil }
        end
    end
    Suggestions[key] = { help = help and tostring(help) or nil, params = clean }
end

local pushQueued = false
local pushCommands

-- Suggestions tend to arrive in bursts at resource start; send one update.
local function queuePush()
    if pushQueued then return end
    pushQueued = true
    SetTimeout(500, function() pushQueued = false; pushCommands() end)
end

RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    addSuggestion(name, help, params); queuePush()
end)
RegisterNetEvent('chat:addSuggestions', function(list)
    for _, s in ipairs(list or {}) do addSuggestion(s.name, s.help, s.params) end
    queuePush()
end)
RegisterNetEvent('chat:removeSuggestion', function(name)
    Suggestions[suggestionKey(name)] = nil; queuePush()
end)

function pushCommands()
    local seen, list = {}, {}
    local function add(name)
        local key = suggestionKey(name)
        -- "+foo" / "-foo" are key-mapping halves and "_x" internals: not typed.
        if key == '' or seen[key] or key:find('^[%+%-_]') then return end
        seen[key] = true
        local s = Suggestions[key] or {}
        list[#list + 1] = { name = key, help = s.help, params = s.params }
    end
    for _, c in ipairs(GetRegisteredCommands() or {}) do add(c.name) end
    for key in pairs(Suggestions) do add(key) end
    table.sort(list, function(a, b) return a.name < b.name end)
    SendNUIMessage({ action = 'commands', list = list })
end

local function pushOnline()
    local list = lib.callback.await('spz-chat:online', false) or {}
    SendNUIMessage({ action = 'online', list = list })
end

-- ── Base theme (server.cfg spz_theme_* convars via spz-core) ────────────────
local function pushTheme(theme)
    if theme and next(theme) then
        SendNUIMessage({ action = 'theme', theme = theme })
    end
end

CreateThread(function()
    local ok, theme = pcall(function() return exports['spz-core']:GetTheme() end)
    if ok then pushTheme(theme) end
end)

AddEventHandler('SPZ:themeUpdated', function(theme) pushTheme(theme) end)

-- ── Minimap anchor ──────────────────────────────────────────────────────────
-- The chat docks beside the GTA minimap (same rect maths as spz-speedcam).
-- Safezone / resolution can change at runtime, so re-check periodically.
local function getMinimapRect()
    local safeZone    = GetSafeZoneSize()
    local aspectRatio = GetAspectRatio(false)
    local resX, resY  = GetActiveScreenResolution()

    local width   = (resX / (4 * aspectRatio)) / resX
    local height  = (resY / 5.674) / resY
    local leftX   = (resX * (0.05 * (math.abs(safeZone - 1.0) * 10))) / resX
    local bottomY = 1.0 - (resY * (0.05 * (math.abs(safeZone - 1.0) * 10))) / resY

    return { left = leftX, width = width, top = bottomY - height, bottom = bottomY }
end

CreateThread(function()
    local last
    while true do
        local m = getMinimapRect()
        local key = ('%f|%f|%f|%f'):format(m.left, m.width, m.top, m.bottom)
        if key ~= last then
            last = key
            SendNUIMessage({ action = 'minimap', rect = m })
        end
        Wait(2000)
    end
end)

-- ── Visibility gate ──────────────────────────────────────────────────────
--
-- The log is always-on, but "always" starts when the player is actually in the
-- world — not at resource start. The loading screen comes down onto the spawn
-- menu, and the chat box was drawn over both. spz-spawn publishes where the
-- player is in that flow as client-local statebags; nil means that resource is
-- not running, which reads as "in the world" so chat is never lost without it.
local function inWorld()
    local st = LocalPlayer.state
    if st.spawnMenuOpen then return false end
    if st.spawned == false then return false end
    return true
end

local openChat, closeChat

local visible = nil
local function pushVisibility()
    local v = inWorld()
    if v == visible then return end
    visible = v
    -- Input open when the menu takes over (`/spawn`, a route back to the menu):
    -- drop focus with it, or the player is typing into a box they cannot see.
    if not v then closeChat() end
    SendNUIMessage({ action = 'visible', visible = v })
end

function openChat()
    if open then return end
    -- T during the spawn menu is not a chat key: the menu owns NUI focus, and
    -- taking it here is how the menu became unclickable.
    if not inWorld() then return end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'show' })
    pushCommands()
    pushOnline()
end

function closeChat()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
end

-- spz-tutorial closes whatever it opened when the tour moves on.
AddEventHandler("spz-tutorial:closeUI", function() closeChat() end)


-- Polled rather than driven by a state-bag handler: the bag name needs a server
-- id, which is not assigned yet this early, and pushVisibility only sends a NUI
-- message when the answer actually changes. Half a second of chat arriving late
-- after the menu closes is not worth a handler that can miss its own bag.
CreateThread(function()
    while true do
        pushVisibility()
        Wait(500)
    end
end)

-- Chat open while something moves the player (teleport into a minigame or a
-- race, the race intro cover, a spawn fade) kept NUI focus through it: the
-- typing box held the keyboard and mouse while the new mode tried to take
-- them, and controls ended up split between the two. Any of those moments
-- closes the box first.
local function spectating()
    if GetResourceState('spz-spectate') ~= 'started' then return false end
    local ok, on = pcall(function() return exports['spz-spectate']:IsSpectating() end)
    return ok and on == true
end

-- Everything that means "the player's situation just changed": race / queue /
-- minigame / time trial / spectate state, the race phase, and which car they
-- are in (a race or minigame warps them into one).
local function modeKey()
    local st = LocalPlayer.state
    return table.concat({
        tostring(st.inRace), tostring(st.inQueue), tostring(st.pendingRace),
        tostring(st.inMinigame), tostring(st.mgRoom), tostring(st.inTimeTrial),
        tostring(_G.SPZ_InTimeTrial), tostring(GlobalState.raceState),
        tostring(spectating()), tostring(GetVehiclePedIsIn(PlayerPedId(), false)),
    }, '|')
end

local function mustClose()
    local ped = PlayerPedId()
    return IsScreenFadingOut() or IsScreenFadedOut()   -- teleport / spawn / intro cover
        or IsPauseMenuActive()                          -- GTA map / settings took over
        or IsEntityDead(ped)                            -- died mid-sentence
        or IsPlayerSwitchInProgress()                   -- sky-cam transitions
end

CreateThread(function()
    local lastMode = modeKey()
    while true do
        local mode = modeKey()
        if open and (mode ~= lastMode or mustClose()) then closeChat() end
        lastMode = mode
        Wait(open and 100 or 500)
    end
end)

-- Moments that move the player or put a screen up, closed on the event itself
-- so the box is gone before the move rather than up to 100ms after it.
for _, ev in ipairs({
    'SPZ:tpToGrid', 'SPZ:tpToGridPoint', 'SPZ:tpToSafeZone', 'SPZ:gridFormed',
    'SPZ:spawnCheckpoints', 'SPZ:pollOpen', 'SPZ:tt:Begin', 'SPZ:tt:End',
    'spz:minigameChanged', 'spz:leaveMinigame',
}) do
    -- RegisterNetEvent: most of these come from the server, and a plain
    -- AddEventHandler in this resource would never see them.
    RegisterNetEvent(ev, function() closeChat() end)
end

-- Any resource about to take NUI focus can close chat first:
--   TriggerEvent('spz-chat:close')   or   exports['spz-chat']:Close()
AddEventHandler('spz-chat:close', function() closeChat() end)
exports('Close', function() closeChat() end)
exports('IsOpen', function() return open end)

RegisterCommand('spz_chat_open', function() openChat() end, false)
RegisterKeyMapping('spz_chat_open', 'Open chat', 'keyboard', Config.Keybind)

RegisterNetEvent('spz-chat:receive', function(payload)
    SendNUIMessage({ action = 'message', payload = payload })
end)

-- Compat: several resources (spz-physics, spz-core permissions, spz-fpscap)
-- still post feedback via the default FiveM chat resource's event, either
-- server-triggered or fired locally with plain TriggerEvent. Catch it here
-- too so those messages keep showing once the default `chat` resource is
-- no longer running.
RegisterNetEvent('chat:addMessage', function(data)
    data = data or {}
    local text = data.args and table.concat(data.args, ' ') or (data.template or '')
    text = text:gsub('%^%d', '') -- strip default-chat ^N colour codes
    if text == '' then return end
    -- No `ts` here: the `os` library does not exist in FiveM's client Lua
    -- sandbox, and the UI never reads the field anyway (server-sent payloads
    -- carry it, where os.time() is valid).
    SendNUIMessage({ action = 'message', payload = { channel = 'system', text = text } })
end)

-- ── NUI callbacks ─────────────────────────────────────────────────────────────

RegisterNUICallback('close', function(_, cb)
    closeChat()
    cb(1)
end)

-- GIF picker: the server searches GIPHY (it holds the API keys).
RegisterNUICallback('gifSearch', function(d, cb)
    local res = lib.callback.await('spz-chat:gifSearch', false, d and d.q or '')
    cb(res or { ok = false, error = 'No answer from the server.' })
end)

RegisterNUICallback('send', function(d, cb)
    closeChat()
    local text = d and d.text
    if not text or text == '' then cb(1) return end

    -- A leading "/" that isn't one of our own chat-channel prefixes is a
    -- real command (e.g. /savecustom, bare /crew) — run it locally instead
    -- of posting it as a chat message.
    if text:sub(1, 1) == '/' and not isChatPrefixed(text) then
        ExecuteCommand(text:sub(2))
        cb(1)
        return
    end

    local res = lib.callback.await('spz-chat:send', false, { text = text })
    if not (res and res.ok) and res and res.error then
        SendNUIMessage({ action = 'message', payload = { channel = 'error', text = res.error } })
    end
    cb(1)
end)

-- ESC closes without sending.
CreateThread(function()
    while true do
        if open then
            if IsControlJustPressed(0, 322) then closeChat() end -- INPUT_FRONTEND_PAUSE_ALTERNATE (Esc)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)

TriggerEvent('chat:addSuggestion', '/help', 'Show every server feature and its key')

