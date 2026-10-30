-- server/giphy.lua — GIF search for the chat, proxied through the server.
--
-- API keys live ONLY on the server: in config_server.lua (server-only, never
-- sent to players) — or, alternatively, in server.cfg:
--
--   set spz_giphy_keys "key_one,key_two,key_three"
--
-- Both sources are merged. Never put keys in config.lua: it is shared with
-- every client.
--
-- Several keys are allowed so free-tier keys can share the load: requests use
-- the current key until GIPHY answers 429 (rate limit) or 401/403 (key rejected
-- or quota used up). That key then rests for Config.Giphy.KeyCooldownMin and the
-- next one is tried straight away, so a search only fails when every key is
-- resting. Results are cached for a few minutes to save quota.

local G = Config.Giphy or {}

local keys = {}                 -- { key = "...", restUntil = 0 }
local current = 1

local function loadKeys()
    keys = {}
    local seen = {}
    local function add(k)
        if type(k) == 'string' and k ~= '' and not seen[k] then
            seen[k] = true
            keys[#keys + 1] = { key = k, restUntil = 0 }
        end
    end
    for _, k in ipairs((ServerConfig and ServerConfig.GiphyKeys) or {}) do add(k) end
    for k in (GetConvar('spz_giphy_keys', '')):gmatch('[^,%s]+') do add(k) end
    current = 1
    print(('^2[spz-chat] GIPHY: %d API key(s) loaded^7'):format(#keys))
end
loadKeys()

local function anyKey() return #keys > 0 end

--- Next usable key index starting at `from`, or nil when all are resting.
local function usableFrom(from)
    local now = os.time()
    for n = 0, #keys - 1 do
        local i = ((from - 1 + n) % #keys) + 1
        if keys[i].restUntil <= now then return i end
    end
    return nil
end

local cache = {}                -- [query] = { at, results }
local CACHE_S = 300

local function urlencode(s)
    return (s:gsub('[^%w%-_%.~]', function(c) return ('%%%02X'):format(c:byte()) end))
end

--- One HTTP call, synchronous inside a coroutine.
local function get(url)
    local p = promise.new()
    PerformHttpRequest(url, function(status, body) p:resolve({ status = status, body = body }) end, 'GET')
    return Citizen.Await(p)
end

--- Trim GIPHY's response to what the picker needs.
local function shape(data)
    local out = {}
    for _, g in ipairs(data or {}) do
        local im = g.images or {}
        local small = im.fixed_width_small or im.fixed_height_small or im.fixed_width
        if g.id and small and small.url then
            out[#out + 1] = {
                id = g.id,
                preview = small.url,
                w = tonumber(small.width) or 100,
                h = tonumber(small.height) or 100,
                title = g.title,
            }
        end
    end
    return out
end

--- Search (or trending when the query is empty). Rotates keys on limits.
local function search(query)
    if not anyKey() then return nil, 'GIFs are not set up on this server.' end
    query = (query or ''):sub(1, 50)
    local ck = query:lower()
    local hit = cache[ck]
    if hit and os.time() - hit.at < CACHE_S then return hit.results end

    local tried = 0
    local i = usableFrom(current)
    while i and tried < #keys do
        tried = tried + 1
        local base = query == '' and 'https://api.giphy.com/v1/gifs/trending?' or
            ('https://api.giphy.com/v1/gifs/search?q=%s&'):format(urlencode(query))
        local url = ('%sapi_key=%s&limit=%d&rating=%s&bundle=messaging_non_clips'):format(
            base, keys[i].key, G.Results or 24, G.Rating or 'pg-13')
        local res = get(url)

        if res.status == 200 then
            current = i
            local ok, decoded = pcall(json.decode, res.body or '')
            local results = ok and decoded and shape(decoded.data) or {}
            cache[ck] = { at = os.time(), results = results }
            return results
        end

        if res.status == 429 or res.status == 401 or res.status == 403 then
            -- Rate limit or key refused: rest it, move on to the next one now.
            keys[i].restUntil = os.time() + (G.KeyCooldownMin or 60) * 60
            print(('^3[spz-chat] GIPHY key #%d returned %d, resting it; trying the next^7'):format(i, res.status))
            i = usableFrom(i % #keys + 1)
        else
            -- Network or GIPHY-side error: don't burn the key, just give up.
            return nil, 'GIF search is unavailable right now.'
        end
    end
    return nil, 'GIF search limit reached — try again later.'
end

local lastSearch = {}           -- [source] = GetGameTimer()

lib.callback.register('spz-chat:gifSearch', function(source, query)
    if not (G.Enabled ~= false) then return { ok = false, error = 'GIFs are turned off.' } end
    local now = GetGameTimer()
    if lastSearch[source] and now - lastSearch[source] < (G.SearchCooldownMs or 600) then
        return { ok = false, error = 'Slow down.' }
    end
    lastSearch[source] = now
    local results, err = search(type(query) == 'string' and query or '')
    if not results then return { ok = false, error = err } end
    return { ok = true, results = results }
end)

AddEventHandler('playerDropped', function() lastSearch[source] = nil end)

--- GIF ids are GIPHY's own (letters and digits). The URL is built here, never
--- taken from the client, so chat can only ever show GIPHY media.
function GiphyUrl(id)
    if type(id) ~= 'string' or not id:match('^[%w]+$') or #id > 40 then return nil end
    return ('https://media.giphy.com/media/%s/200.gif'):format(id)
end

GiphyEnabled = function() return G.Enabled ~= false and anyKey() end

-- Reload keys after editing server.cfg:  /spzgiphyreload  (console / ACE command.spzgiphyreload)
RegisterCommand('spzgiphyreload', function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'command.spzgiphyreload') then return end
    loadKeys()
end, true)
