-- client/boot.lua — keep this page hidden until the loading screen is down.
-- NUI pages render above the loading screen, so without this the page showed
-- through it for the last seconds of loading. The page starts hidden
-- (ui/index.html) and is shown by 'spzBooted'. Sent a few times: the page may
-- not have attached its listener yet when the first one goes out.

local function loadingDone()
    if GetResourceState('spz-loading') ~= 'started' then return true end
    local ok, done = pcall(function() return exports['spz-loading']:IsFinished() end)
    return not ok or done == true
end

local function reveal()
    CreateThread(function()
        for _ = 1, 10 do
            SendNUIMessage({ action = 'spzBooted' })
            Wait(500)
        end
    end)
end

AddEventHandler('spz-loading:finished', reveal)

CreateThread(function()
    -- Covers a resource restart mid-session and the event being missed.
    while not loadingDone() do Wait(500) end
    reveal()
end)
