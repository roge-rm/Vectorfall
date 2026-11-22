# Vectorfall

Vectorfall is a capture-the-flag shooter for Android and Linux. Ski down a hill, jet over the next ridge and bring the other team's flag home. Fly a gunship to cover your runner, or go in on foot and knock out the enemy generator.

Two play on ten arenas, with up to eight soldiers a side locally or sixteen a side on a dedicated server. Bots can fill both teams, drive and fly vehicles, repair the base and take orders from you.

Let me know what works and what doesn't in the #vectorfall channel [on my discord](https://discord.gg/9Wun47jGC6), or open an issue here.

Enjoy,<br>
Dan

---

## Gameplay

![Skiing for the flag, flying a Needlewing over Ochre Fold and fighting on Greenfall Terraces](docs/images/gameplay.gif)

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/images/ski-run.png" width="400" alt="Approaching the jet gate in Ski Practice with the timer and speed readout" /><br>Ski Practice</td>
    <td align="center"><img src="docs/images/bomber-and-ferry.png" width="400" alt="A Blue Cinder Kite and Morrow Ferry flying above Ochre Fold" /><br>Bomber and ferry</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/caldera-relay.png" width="400" alt="The two rim routes overlooking the crater floor on Caldera Relay" /><br>Caldera Relay</td>
    <td align="center"><img src="docs/images/beacon-wreck.png" width="400" alt="Cargo bays of the wreck between the outer dunes on Beacon Wreck" /><br>Beacon Wreck</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/greenfall-terraces.png" width="400" alt="Green hills and parallel switchbacks on Greenfall Terraces" /><br>Greenfall Terraces</td>
    <td align="center"><img src="docs/images/copper-steps.png" width="400" alt="Red rock shelves and ramps below a flag deck on Copper Steps" /><br>Copper Steps</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/armour-classes.png" width="400" alt="Lime and Blue soldiers in light, medium and heavy armour" /><br>Armour classes</td>
    <td align="center"><img src="docs/images/ground-vehicles.png" width="400" alt="The Basalt Crawler and Tern Sled outside the Lime base" /><br>Tank and grav bike</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/match-setup.png" width="400" alt="Match Setup with arena, team, bot skill and match limits" /><br>Match setup</td>
    <td align="center"><img src="docs/images/loadout.png" width="400" alt="The loadout screen with armour, weapons and equipment choices" /><br>Loadout</td>
  </tr>
</table>

---

## Install

Download the APK or Debian package from [Releases](https://github.com/roge-rm/Vectorfall/releases).

- Android 7.0 and up, on 32-bit or 64-bit ARM. Open `vectorfall-0.13.0.apk`. Follow the install prompt. If you installed a debug APK, remove it first. That clears the debug build's saved settings and loadouts.
- Debian 13 on 64-bit x86. Install `vectorfall_0.13.0_amd64.deb` with `sudo apt install ./vectorfall_0.13.0_amd64.deb` from the download folder. Open Vectorfall from the applications menu. The game needs OpenGL 3.3.

Android supports touch, gyro aim and gamepads. Linux supports a mouse and keyboard or a gamepad.

## Playing

Open `Online`. Pick a game on your LAN or enter a server address. Bots fill the empty slots. A dedicated server can run 16v16. See the [dedicated server guide](server/README.md) for Docker Compose, the dashboard and the browser build.

Open `How to play` and choose `Ski practice`. Hold jump on the way down a hill. Jet over the next rise. Let go of jet to refill your energy. You can reset the run. The game saves your best time.

Open `Play` to set up a local match. Pick one of ten arenas. Pick Lime or Blue. Set the number of bots and their skill for each side. Set the time and capture limits. Local matches go up to 8v8.

Touch the enemy flag to take it. Bring it back to your stand when your own flag is home. Touch your dropped flag to return it. It returns on its own after 30 seconds.

Give bots orders to go for the flag, cover you or help at the base. Turn on `Commander mode` in `Settings` to assign roles. Bots can drive and fly vehicles and repair the base.

### Capture and hold

When running from source, choose Nightline Foundry or Gannet Reach in `Match setup`. Set `Mode` to `Capture and hold`.

Stay inside a control point for three seconds with no enemies inside to take it. Your team gets a point for every five seconds it holds. Enemies in the area stop the points. The team with the most points when time runs out wins.

Turn on `Midfield ammo` to try a resupply pad on either arena. Both teams can use it. Wait 12 seconds after a refill. Step back onto the pad to use it again. Use a base station to change your loadout or replace grenades, mines and deployables.

### Team map and results

When running from source, open the team map with M, the right stick button or `Map` on touch. Pick a teammate and a spot on the map, then press `Send waypoint`.

Open `Match results` after the match. An assist counts if you hurt an enemy in the eight seconds before a teammate kills them. An escort counts if you're within 35 metres of a teammate when they capture the flag. A repair counts when you bring a destroyed piece of equipment back online.

### Loadouts and base equipment

Light armour carries up to two weapons, medium carries three and heavy carries four. Armour determines which weapons you can take and how many grenades and mines you can carry. There are seven weapons, including the disc launcher, chaingun, sniper rifle and mortar. Change your loadout while dead or at a friendly inventory station. You can save loadouts.

Knock out the enemy generator to cut power to their base. The generator powers the turrets, sensors, inventory station and vehicle pads. Use a repair pack to bring it back online. Use a deployable pack to put a field turret, sensor or inventory station on clear ground. Field equipment has its own power.

### Vehicles

| Vehicle | What it does |
|---|---|
| Tern Sled | A fast grav bike for getting across the map. |
| Basalt Crawler | A tank with a cannon. Passengers can fire their own weapons. |
| Needlewing | A gunship with a second seat for the gunner. |
| Cinder Kite | A bomber that drops shells on targets below. |
| Morrow Ferry | A troop transport. Passengers can fire their own weapons. |

Walk up to a stopped or slow-moving friendly vehicle with a free seat. Press `Board`. Use the move controls to drive. Look where you want to turn. In an aircraft, press jet to climb and jump to descend. On touch those buttons read UP and DOWN. Keep your generator running so the pads can replace lost vehicles.

## Arenas

| Arena | Routes and landmarks |
|---|---|
| Ochre Fold | Long ski runs across sand ridges between hilltop bases. |
| Saltwake Flats | An open salt pan with a drainage cut and a wind berm on the sides. |
| Nightline Foundry | Casting bays give infantry cover, with service roads around the yard. |
| Copper Steps | Ramps climb the rock shelves to the flag decks, with ferry pads below. |
| Caldera Relay | Take the crater floor or stay high on either rim. |
| Gannet Reach | Cross by the cliff path, the raised causeway or the tidal flats. |
| White Signal | A tunnel through the snow, with open routes to either side. |
| Glass Ravine | A high bridge, broken crossings and routes along the canyon ledges. |
| Greenfall Terraces | Switchbacks through green terraces, with routes along both banks. |
| Beacon Wreck | Cargo bays through a wreck, with dune routes on either side. |

Choose `Test map` in `Match setup` for a smaller arena.

## Controls

| | Keyboard and mouse | Gamepad | Touch |
|---|---|---|---|
| Move and look | WASD and mouse | Left and right sticks | Left stick and drag on the right |
| Fire | Left click | Right trigger | FIRE, or drag from FIRE to aim while shooting |
| Jump and ski | Space, hold to ski | A, hold to ski | JUMP, hold to ski |
| Jet | Shift or right click | Left trigger or LB | JET |
| Change weapon | 1 to 4, Q or wheel | Y or RB | Tap the weapon name |
| Use pack or place equipment | E, or G to place | X | PACK or PLACE |
| Grenade and mine | F and C | D-pad left and right | GREN and MINE |
| Loadout | I or B | Back | LOADOUT |
| Board or exit | R | B | BOARD or EXIT |
| Orders and pause | V then a number, Esc to pause | D-pad up and Start | ORDERS and the pause button |

Open `Settings` to change look speed for each input, touch button size, gyro aim, aim assist or auto ski. Set the view distance, render scale and outlines there too. There are separate volume controls for effects, voices and music.

## What's new

New in 0.13.0

- Join an online match by address or find servers on your LAN. Bots fill the rest of the team.
- Run up to 16v16 on a dedicated server with Docker Compose. Follow the match from the web dashboard or join from a browser.
- Both teams have wider bases with three ramps and covered inventory bays.

## Building

Use the Godot 4.7.2 Linux editor at `tools/godot/Godot_v4.7.2-stable_linux.x86_64`. Put an empty `._sc_` file beside the editor to keep its settings local. Install the matching export templates to build packages. For Android, set the Android SDK and Java 21 paths in the editor settings. For Debian packaging, install `dpkg-deb` and ImageMagick.

- `tools/run.sh` runs the game from source. Add `-- --map test` to open the test map.
- `tools/build-linux.sh --release` exports a standalone 64-bit Linux executable.
- `tools/package-deb.sh` builds the Debian amd64 package.
- `tools/build-android.sh` builds a debug APK for ARM. Add `--emulator` for x86-64.
- `tools/run-tests.sh` runs the headless tests. Pass names such as `arena_map_test` or `ski_practice_test` to run selected tests.
- `tools/bot-match.sh --map nightline_foundry --bots 8 --seed 1 --minutes 5` runs a bot match and writes the report to `build/bot-reports/`.

## Licence

GPLv3 or later. See [LICENSE](LICENSE). Big Shoulders Display and IBM Plex Serif are under the SIL Open Font License 1.1. Their licence files are in [art/fonts](art/fonts).
