# Sync an opentalks room status with a telegram group via bot

_clone git_
`git clone`

_copy env_
`cp .env.example .env`

Edit the `env` to contain your opentalk user

_get all avaialble rooms_
`go run client --info`

_run cli to opoen websocket connection_
`go run client --socket <room-id>`
