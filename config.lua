-- config.lua

Config = {}

Config.Keybind        = 't'    -- opens chat input (registry: Docs/keybinds.md)
Config.MaxLength      = 200    -- max characters per message
Config.MinIntervalMs  = 350    -- flood guard between messages
Config.HistorySize    = 100    -- messages kept in the NUI log
Config.FadeAfterMs    = 6000   -- log fades to low opacity this long after last activity while closed

Config.Channels = {
  global = { label = 'Global', prefix = '',       color = '#e4e4e7' },
  crew   = { label = 'Crew',   prefix = '/c ',     color = '#ff9142' },
  dm     = { label = 'DM',     prefix = '/w ',     color = '#ff6ec7' },
  system = { label = 'System', prefix = nil,       color = '#f59e0b' },
}
