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

local function pushCommands()
    local cmds = GetRegisteredCommands() or {}
    local names = {}
    for _, c in ipairs(cmds) do
        names[#names + 1] = c.name
    end
    table.sort(names)
    SendNUIMessage({ action = 'commands', list = names })
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

local function openChat()
    if open then return end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'show' })
    pushCommands()
    pushOnline()
end

local function closeChat()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
end

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
