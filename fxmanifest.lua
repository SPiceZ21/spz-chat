fx_version 'cerulean'
game 'gta5'

name 'spz-chat'
description 'SPiceZ Chat — global / crew / DM chat box with slash-command autocomplete'
version '1.0.0'
author 'SPiceZ-Core'
lua54 'yes'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
}

client_scripts {
  'client/main.lua',
}

server_scripts {
  'server/main.lua',
}

ui_page 'ui/index.html'

files {
  'ui/index.html',
  'ui/style.css',
  'ui/app.js',
  'ui/fonts/*.ttf',
}

dependencies {
  'ox_lib',
  'spz-core',
  'spz-identity',
}
