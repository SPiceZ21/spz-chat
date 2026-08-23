-- client/main.lua — Chat box: always-visible log, T opens the input.
-- Slash-command autocomplete is resolved locally from GetRegisteredCommands();
-- DM target autocomplete comes from the server's online-player list. The
-- server owns channel routing (global/crew/dm) — this side just captures
-- input and renders what it's sent.

local open = false

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

-- ── NUI callbacks ─────────────────────────────────────────────────────────────

RegisterNUICallback('close', function(_, cb)
    closeChat()
    cb(1)
end)

RegisterNUICallback('send', function(d, cb)
    closeChat()
    local text = d and d.text
    if not text or text == '' then cb(1) return end

    local res = lib.callback.await('spz-chat:send', false, { text = text })
    if not (res and res.ok) and res and res.error then
        SendNUIMessage({ action = 'message', payload = { channel = 'error', text = res.error, ts = os.time() } })
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
