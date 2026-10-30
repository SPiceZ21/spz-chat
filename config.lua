-- config.lua

Config = {}

Config.Keybind        = 't'    -- opens chat input (registry: Docs/keybinds.md)
Config.MaxLength      = 200    -- max characters per message
Config.MinIntervalMs  = 350    -- flood guard between messages

-- ── GIFs (GIPHY) ─────────────────────────────────────────────────────────────
-- The API keys are NOT here (this file is sent to every player): put them in
-- config_server.lua. Several keys rotate automatically when one hits its limit.
Config.Giphy = {
  Enabled          = true,
  Rating           = 'pg-13',  -- g | pg | pg-13 | r
  Results          = 24,       -- GIFs per search
  KeyCooldownMin   = 60,       -- a key that hit its limit rests this long
  SearchCooldownMs = 600,      -- per-player search flood guard
}

-- ── Tips broadcast ───────────────────────────────────────────────────────────
-- One line from this list goes out to everyone every IntervalMin minutes, in
-- order, so new players find out what the server has. Keys are the defaults;
-- players can rebind them in Settings > Key Bindings > FiveM.
Config.Tips = {
  Enabled     = true,
  IntervalMin = 5,
  FirstDelayS = 90,     -- after a resource start
  Lines = {
    "Press E anywhere to join the next race. Press E again to leave the queue.",
    "Press F7 to open the Minigames hub: Bomb Tag, Demolition, Color Rush, Cyclone, Rocket League and Hot Pursuit.",
    "Joining a minigame takes you out of the race queue automatically.",
    "Press F5 for the car spawner. Type /tune to tune and customise your car.",
    "During warmup press Y to tune your race car before the lights go out.",
    "Stuck mid-race? F4 puts you back on the last checkpoint, K flips your car.",
    "Press F6 for race results and the leaderboard.",
    "Not happy with the poll? Vote Reroll for a fresh set of tracks or cars.",
    "Try /timetrail to practise a track alone and chase your personal best.",
    "Challenge someone with /duel <player> <track> <stake>.",
    "Speed camera records: quick menu (Z) > Leaderboard. F3 opens the racing line panel.",
    "Start or join a crew with /crew. /c <message> talks to your crew.",
    "Press Z for the quick menu. Type /help any time to see all features.",
    "New here? Type /tutorial for a guided tour of every screen on the server.",
  },
}

-- ── /help ────────────────────────────────────────────────────────────────────
-- What /help prints to the player who typed it. Also offered once on join.
Config.Help = {
  WelcomeDelayS = 25,   -- after a player connects; 0 = no welcome line
  Lines = {
    "RACING — E join/leave queue (works during warmup too) · vote track, car and traffic · Y tune during warmup · F4 last checkpoint · K flip · B rewind · N standings · F9/F11 race board · F6 results",
    "PRACTICE — /timetrail solo laps · /duel <player> <track> <stake> 1v1 for credits · /spectate watch a race",
    "CARS — F5 car spawner · /tune tuning + customs · /fix repair",
    "MINIGAMES — F7 opens the hub: create a room, invite friends, host starts the match",
    "SOCIAL — /crew crew dashboard · /c crew chat · /w <name> <msg> whisper",
    "DRIVING — arrows indicators · J hazards · L flash · G horn taunt · LSHIFT/LCTRL manual gears · /transmode /tcs /tires",
    "MORE — Z quick menu · speed records in Z > Leaderboard · F3 racing line · F10 nametags · /replays · /appearance · /emote",
    "Type /tutorial to replay the guided tour. Rebind any key in Settings > Key Bindings > FiveM.",
  },
}

