# Vectorfall

Vectorfall is a team capture the flag shooter for Android with jetpacks and a cel shaded look. Two teams of 8 fight over each other's flags, on foot or in the air. It's early: for now there's one full size map, Ochre Fold, 1.5 km of ridges, a canyon and a high spine between two bases, a small test map, two weapons, and a full capture the flag match with bots on both teams that ski, jet, fight and play as a team around you. Each team has a commander that gives its bots roles as the match goes, and it works out what you're doing without being told: head for the enemy flag and bots escort you, stay at home and one fewer bot defends.

## Controls

| | Keyboard and mouse | Gamepad | Touch |
|---|---|---|---|
| Move | W A S D | Left stick | Left thumb, the stick appears where you touch |
| Look | Mouse | Right stick | Drag on the right half |
| Fire | Left click | Right trigger | FIRE, or the small FIRE on the left; dragging from FIRE also looks, and sliding from JET onto FIRE fires and jets |
| Jetpack (hold) | Right click or Shift | Left trigger or left shoulder | JET, next to FIRE and JUMP |
| Jump | Space | A | JUMP |
| Ski (hold) | Space | A | Hold JUMP, and slide onto JET to ski and jet |
| Disc launcher, chaingun | 1, 2 | | |
| Next weapon | Q or mouse wheel | Right shoulder | SWAP |
| Use | E | X | |
| Deploy | G | Y | |
| Let go of the mouse | Esc | | |
| Bot overlay | F3 | | |

Click in the window to capture the mouse. The touch controls show when you touch the screen and hide when you use a keyboard or gamepad.

Skiing makes you slide with next to no friction, so you speed up going downhill and slow down going up. Hold Space (or JUMP on touch) to hop and then ski when you land, and jet to get up the next hill without losing your speed. The SKI light on the screen is bright while you're skiing on the ground.

The disc launcher fires slow discs that blow up with a big blast and push. Lead your shots, and aim at the ground by someone's feet. Fire one at your own feet while you jet for a disc jump; your own blasts hurt you a little. The chaingun takes a moment to spin up, then fires fast, spreading shots that do little damage each. Both carry some of your own speed, the disc most of it. When you die you're back at your team's spawn, about 40 m beside your flag, after 4 seconds.

The jetpack drains energy while you hold it, and the energy starts to refill a moment after you let go. You keep your speed in the air and when you land on a downhill.

## Capture the flag

Touch the enemy flag on its stand to pick it up, then run, ski or jet it to your own stand and touch that to score. Your own flag has to be home for a capture to count. You can still shoot and jet while you carry it. If you die it drops where you were and tumbles on with your speed. Touching your own dropped flag sends it home, and a dropped flag goes home by itself after 30 seconds. First to 5 captures wins, or whoever has most after 20 minutes, and the same score is a draw. The end screen has a restart button, or press R. The capture limit and time limit are in `scripts/sim/match_settings.gd`.

The screen shows the score and time at the top, a compass strip below it, a message for each flag event, and a marker with the distance on each flag, with an arrow at the edge of the screen when it's out of view. A tall beam of light stands over each flag, wider when it's away from its stand.

## Building

Vectorfall uses Godot 4.7.2, the Compatibility renderer and Jolt physics. The scripts expect these local tools, which aren't in the repo:

- `tools/godot/Godot_v4.7.2-stable_linux.x86_64`, with an empty `._sc_` file beside it to keep settings in `tools/godot/editor_data`
- Godot 4.7.2 export templates in `tools/godot/editor_data/export_templates/4.7.2.stable`
- Android SDK and Java 21, set under Export › Android in the editor settings

```sh
tools/run.sh                       # run from the source in a window, extra arguments go to Godot
tools/run.sh -- --map test         # the same on the test map
tools/build-linux.sh               # Linux debug build, build/desktop/vectorfall.x86_64
tools/build-linux.sh --release     # release build, build/desktop/release/vectorfall.x86_64
tools/build-linux.sh --run         # build, then start it in a window
tools/package-deb.sh               # release build packed as build/desktop/vectorfall_<version>_amd64.deb
tools/build-android.sh             # phone APK, arm64
tools/build-android.sh --emulator  # emulator APK, x86_64
```

The Android presets aren't runnable (no one-click deploy from the editor), since the editor otherwise keeps running adb to look for devices. The Linux build is for Debian trixie on amd64 and needs the Godot Linux export templates too. The .deb puts the game in `/usr/lib/vectorfall` with a `vectorfall` launcher and a menu entry. The APKs are signed with the Android debug key and go in `build/`. The code is in `scripts`, shaders in `shaders` and the main scene in `scenes`. Everything in the world is made in code.

To take pictures of the test map and of a soldier close up (they need a screen). Godot runs adb on our own port 5052 here, as in the tools scripts, so it never starts the shared adb server on 5037:

```sh
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/map_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/combat_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/flag_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/style_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/mockup_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/warm_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/direction_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/team_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/final_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/perf_shot.tscn
ANDROID_ADB_SERVER_PORT=5052 tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/m6_shot.tscn
```

The final shot draws the game's look, the paperback palette: the style scene, the six soldiers close from the front and behind, both guns in your hands and the soldiers at 50 m on sand, turquoise, in shade and against the sky. The style shot has a soldier of each armour for each team, a base and a fight, in the desert and highland palettes, plus a close-up, both guns in your hands for both teams, the six soldiers at 50 m and a picture from the main scene. The mockup shot draws one scene in the four comic ink styles Dan picked from. The warm shot draws the style shot's desert scene in today's look and five warmer ones: golden hour, sepia ink, warm shadows, glow from fire and energy, and sepia with warm shadows. The direction shot draws the same scene in five art directions: warm sun and cool shade, a 1970s sci-fi paperback, a lush painted meadow, a flat travel poster and a neon frontier at dusk (`Palette.sun_and_shade()`, `paperback()`, `meadow()`, `travel_poster()` and `neon_frontier()`); add `-- 2 5` to take only some of them. The team shot draws the paperback scene with three team colour pairs and the six soldiers at 50 m for each. A palette sets its own team colours in `team_colours`, read everywhere through `Palette.team()`. The perf shot prints draw calls, triangles, frame times and terrain chunks drawn in the main scene on Ochre Fold with 17 soldiers spread down the map in view, with outlines on and off; add `-- test` for the test map. The M6 shot draws Ochre Fold from high up, a base, the ski line from a base in game and a long view to the fog. The other shots are of the test map.

The game loads Ochre Fold. Add `--map test` after `--` on the command line for the test map. How far you can see is `view_distance` under `[graphics]` in `user://settings.cfg`, 1200 m by default, with no menu yet; the fog thickens to match it.

## Testing

Run the headless tests on the computer:

```sh
tools/run-tests.sh
```

They check the jetpack, skiing, movement in the air, the chunked terrain (heights, gaps between detail levels, collision under soldiers, shots hitting the ground anywhere), Ochre Fold's spawns and route graph, that soldiers move only from their commands, the touch controls, weapon damage, splash and disc jumps, every capture the flag rule, that shots can't pass through walls, respawning, the test map's ski speed and saving and loading match state. For the bots they check the route graph and planner, what bots see and hear, a bot getting from base to base past 40 m/s, a boxed in bot getting out, leading a moving target, two bots capturing a flag on their own, that the same seed plays a match with fighting and flags the same way, and the team commander: its roles for each score and flag situation, reading a person's role from how they move, learning lanes, and with a scripted stand-in player on Ochre Fold, bots escorting it when it takes the flag, fewer bots defending while it sits at home and bots chasing whoever takes our flag.

The bot match runs bots headless, faster than real time, and writes a report to `build/bot-reports/` with the score, every flag event, how long carriers held the flag, each team's roles every 10 seconds, its commander's decisions and what it learnt about each lane, and each bot's role, distance, speeds, kills, deaths, flags, shots and hits per weapon and where it got stuck:

```sh
tools/bot-match.sh --bots 8 --seed 1 --minutes 5
tools/bot-match.sh --map test     # on the test map
tools/bot-check.sh                # the bots' regression check
```

The bot check plays three seeded 4 minute matches on Ochre Fold and fails if the bots stop grabbing flags, returning them or moving, or if none of the matches has a capture. It takes about 4 minutes.

F3 in the game shows the bots' route graph (run links white, ski blue, jet orange, walls red, points of interest as yellow posts), each bot's route and a label with its role (and who it escorts or chases), goal, what it's doing and who it's fighting, and over each flag what that team's commander wants and its last few decisions. `tools/shots/bots_shot.tscn` takes a picture of it.

## Licence

Vectorfall is free software under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE).
