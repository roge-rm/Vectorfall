# Dedicated server

From the project root, copy `server/.env.example` to `.env`. Set the server name, arena, round length and team size there. Set `ADMIN_PASSWORD` to enable the Match Setup form on the dashboard. With the password blank the dashboard shows the score, clock and roster.

When upgrading from Vectorfall, run `docker compose down` from the old checkout before starting Skifrei so it can bind the game and dashboard ports. You can keep using the same `.env` file.

Run `docker compose up --build -d`, then open [the dashboard](http://localhost:27303). Use `docker compose logs -f game` for the game logs and `docker compose down` to stop the server.

Set `TEAM_SIZE=16` for a 16v16 match with up to 32 players and bots combined. The server defaults to 8v8. Phones and tablets can join a 16v16 server from the Online menu. Local matches on those devices go up to 8v8.

Upgrade the server and clients together. Skifrei 0.16.0 uses protocol 2 and updated arena layouts. Open **Online → Browse servers** or enter the server address and UDP port. The server fills both teams with bots. A player takes over a bot slot, and the bot takes it back when they leave.

After the results, the server moves to the next arena. By default it starts on `MAP` and runs through the regular arenas in the configured mode. Set `ROTATION=copper_steps:ctf,nightline_foundry:hold,white_signal:ctf` to choose an order and mix modes. Omit a mode to use `MODE`. Set `ROTATION=off` for one arena. The dashboard can start a round on another arena at once.

Set `MODE=hold` for Capture and Hold. All maps support this mode. The round runs for `MINUTES`, and the team with the most points wins. Set `MIDFIELD_RESUPPLY=1` to add the ammo pad on Nightline Foundry and Gannet Reach. In Capture and Hold on Nightline Foundry, the team holding B can use the pad when the point is clear of enemies.

## Ports

| Default | Use |
|---|---|
| 27300 UDP | Android and Linux game connections |
| 27301 UDP | LAN discovery |
| 27302 TCP | WebSocket game connections |
| 27303 TCP | Browser dashboard, bound to loopback by default |

The default Compose file runs on x86-64 and uses Linux host networking so LAN broadcasts reach the server. For Docker Desktop or explicit port mappings, run `docker compose -f compose.yml -f compose.bridge.yml up --build -d`. In that setup, players enter the address and port directly.

## Public server list

LAN discovery and direct connect work without a directory. To host a public list, run `SKIFREI_DIRECTORY_TOKEN=<token> python3 server/directory.py` and use a TLS reverse proxy to publish its `/servers` endpoint. The Python service listens on `127.0.0.1:27304` by default. Keep it running with your service manager.

Game servers list themselves when their `.env` has `DIRECTORY_URL=https://your-directory.example/servers`, the shared `DIRECTORY_TOKEN` and a reachable `PUBLIC_HOST` or `PUBLIC_WS`. Use a `wss://` address for browsers. Share the token only with server operators you want listed. They can see and update the public server list without signing players in. The service removes entries after 100 seconds without a heartbeat.

Players can paste the directory URL under **Online → Browse servers** and refresh. The list shows the map, mode, humans and slots, and measures the round trip to each responding server. A client build can ship with a default by setting `skifrei/directory/url` in Project Settings.

## Play in a browser

Install the Godot 4.7.2 Web export template and run `tools/build-web.sh` from the repo. It exports to `build/web`, which the web container serves at `/play/`. The dashboard shows **Play in browser** when the export is there. The Web preset runs without WebAssembly threads, so it does not need cross-origin isolation headers.

A standalone export opens the main menu. A dashboard link with `?server=...` opens Online with the server address filled in.

Browsers require HTTPS for play over the network. Localhost works over HTTP. Put a TLS reverse proxy in front of the dashboard and proxy `/match` to the game's WebSocket port with WebSocket upgrades enabled. Set `PUBLIC_WS` in `.env` if the public WebSocket address differs.

Run `tools/check-online.sh` to check LAN discovery, native and WebSocket joins, movement, round changes and bot takeovers against a local test server.
