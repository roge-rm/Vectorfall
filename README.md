# Vectorfall

Vectorfall is a team capture the flag shooter for Android with jetpacks and a cel shaded look. Two teams of 8 fight over each other's flags, on foot or in the air. It's early: for now there's a test map with a valley to ski down, two weapons and a stand-in enemy to shoot at.

## Controls

| | Keyboard and mouse | Gamepad | Touch |
|---|---|---|---|
| Move | W A S D | Left stick | Left thumb, the stick appears where you touch |
| Look | Mouse | Right stick | Drag on the right half |
| Fire | Left click | Right trigger | FIRE |
| Jetpack (hold) | Right click or Shift | Left trigger or left shoulder | JET |
| Jump | Space | A | JUMP |
| Ski (hold) | Space | A | SKI, tap to turn on and off |
| Disc launcher, chaingun | 1, 2 | | |
| Next weapon | Q or mouse wheel | Right shoulder | SWAP |
| Use | E | X | |
| Deploy | G | Y | |
| Let go of the mouse | Esc | | |

Click in the window to capture the mouse. The touch controls show when you touch the screen and hide when you use a keyboard or gamepad.

Skiing makes you slide with next to no friction, so you speed up going downhill and slow down going up. Hold Space to hop and then ski when you land, and jet to get up the next hill without losing your speed. The SKI light on the screen is bright while you're skiing on the ground.

The disc launcher fires slow discs that blow up with a big blast and push. Lead your shots, and aim at the ground by someone's feet. Fire one at your own feet while you jet for a disc jump; your own blasts hurt you a little. The chaingun takes a moment to spin up, then fires fast, spreading shots that do little damage each. Both carry some of your own speed, the disc most of it. When you die you're back on your base's deck after 4 seconds.

The jetpack drains energy while you hold it, and the energy starts to refill a moment after you let go. You keep your speed in the air and when you land on a downhill.

## Building

Vectorfall uses Godot 4.7.2, the Compatibility renderer and Jolt physics. The scripts expect these local tools, which aren't in the repo:

- `tools/godot/Godot_v4.7.2-stable_linux.x86_64`, with an empty `._sc_` file beside it to keep settings in `tools/godot/editor_data`
- Godot 4.7.2 export templates in `tools/godot/editor_data/export_templates/4.7.2.stable`
- Android SDK and Java 21, set under Export › Android in the editor settings

```sh
tools/run.sh                       # run from the source in a window, extra arguments go to Godot
tools/build-linux.sh               # Linux debug build, build/desktop/vectorfall.x86_64
tools/build-linux.sh --release     # release build, build/desktop/release/vectorfall.x86_64
tools/build-linux.sh --run         # build, then start it in a window
tools/package-deb.sh               # release build packed as build/desktop/vectorfall_<version>_amd64.deb
tools/build-android.sh             # phone APK, arm64
tools/build-android.sh --emulator  # emulator APK, x86_64
```

The Linux build is for Debian trixie on amd64 and needs the Godot Linux export templates too. The .deb puts the game in `/usr/lib/vectorfall` with a `vectorfall` launcher and a menu entry. The APKs are signed with the Android debug key and go in `build/`. The code is in `scripts`, shaders in `shaders` and the main scene in `scenes`. Everything in the world is made in code.

To take pictures of the test map and of a soldier close up (they need a screen):

```sh
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/map_shot.tscn
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/combat_shot.tscn
```

## Testing

Run the headless tests on the computer:

```sh
tools/run-tests.sh
```

They check the jetpack, skiing, movement in the air, that soldiers move only from their commands, the touch controls, weapon damage, splash and disc jumps, that shots can't pass through walls, respawning, the test map's ski speed and saving and loading match state.

## Licence

Vectorfall is free software under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE).
