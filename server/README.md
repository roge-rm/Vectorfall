# Dedicated server

From the project root, copy `server/.env.example` to `.env`. Set the server name, arena, round length and team size there. Set `ADMIN_PASSWORD` to enable the Match Setup form on the dashboard. With the password blank the dashboard shows the score, clock and roster.

Run `docker compose up --build -d`, then open [the dashboard](http://localhost:27303). Use `docker compose logs -f game` for the game logs and `docker compose down` to stop the server.

Set `TEAM_SIZE=16` for a 16v16 match with up to 32 players and bots combined. The server defaults to 8v8. Phones and tablets can join a 16v16 server from the Online menu. Local matches on those devices go up to 8v8.

Use the same Vectorfall build on the server and clients so their arena layouts match. In Vectorfall, choose **Online → Find LAN games** or enter the server address and UDP port. The server fills both teams with bots. A player takes over a slot on the team with fewer players, and a bot takes it back when they leave. The server starts a new round on the same arena after the results. The dashboard can start a round on another arena at once.

## Ports

| Default | Use |
|---|---|
| 27300 UDP | Android and Linux game connections |
| 27301 UDP | LAN discovery |
| 27302 TCP | WebSocket game connections |
| 27303 TCP | Browser dashboard, bound to loopback by default |

The default Compose file runs on x86-64 and uses Linux host networking so LAN broadcasts reach the server. For Docker Desktop or explicit port mappings, run `docker compose -f compose.yml -f compose.bridge.yml up --build -d`. In that setup, players enter the address and port directly.

## Play in a browser

Install the Godot 4.7.2 Web export template and run `tools/build-web.sh` from the repo. It exports to `build/web`, which the web container serves at `/play/`. The dashboard shows **Play in browser** when the export is there. The Web preset runs without WebAssembly threads, so it does not need cross-origin isolation headers.

For HTTPS, put a TLS reverse proxy in front of the dashboard and proxy `/match` to the game's WebSocket port with WebSocket upgrades enabled. Set `PUBLIC_WS` in `.env` if the public WebSocket address differs. Keep the dashboard behind HTTPS if you administer it over a network.

Run `tools/check-online.sh` to check LAN discovery, native and WebSocket joins, movement, round changes and bot takeovers against a local test server.
