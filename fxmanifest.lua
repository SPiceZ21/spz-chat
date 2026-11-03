fx_version 'cerulean'
game 'gta5'

name 'spz-chat'
description 'SPiceZ Chat — global / crew / DM chat box with slash-command autocomplete'
version '1.11.0'
author 'SPiceZ-Core'
lua54 'yes'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
}

client_scripts {
    '@spz-hud/shim.lua',   -- NUI goes through spz-hud
  'client/boot.lua',
  'client/main.lua',
}

server_scripts {
  'config_server.lua',   -- server only: API keys (never shared with players)
  'server/giphy.lua',
  'server/main.lua',
}

-- ui_page 'ui/index.html'  -- drawn by spz-hud now (web/public/apps/spz-chat); uncomment + drop the shim to roll back

files {
  'ui/index.html',
  'ui/style.css',
  'ui/app.js',
  'ui/fonts/*.ttf',
}

dependencies {
    'spz-hud',
  'ox_lib',
  'spz-core',
  'spz-identity',
}
