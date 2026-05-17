fx_version 'cerulean'
game 'gta5'

author 'Beetle Studios'
description 'Simple cross-framework billing system'
version '1.1.0'

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/banking.lua',
    'server/bills.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

files {
    'locales/*.json'
}

dependencies {
    'ox_lib',
    'oxmysql'
}

lua54 'yes'
