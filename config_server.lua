-- config_server.lua — SERVER ONLY. Never add this file to shared_scripts or
-- files{}: it holds API keys, and anything shared is downloaded by every player.

ServerConfig = {}

-- GIPHY API keys for the chat GIF picker (https://developers.giphy.com → Create an App → API).
-- Add as many as you like: when one hits its free-tier limit (or is refused),
-- it rests for Config.Giphy.KeyCooldownMin and the next one is used
-- automatically. Leave the list empty to turn GIFs off.
ServerConfig.GiphyKeys = {
    -- "your_first_key_here",
    -- "your_second_key_here",
}
