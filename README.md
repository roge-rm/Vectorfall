# Vectorfall

Vectorfall is a team capture the flag shooter for Android with jetpacks and a cel shaded look. Two teams of 8 fight over each other's flags, on foot or in the air. It's early: for now there's a test map to run, jump and jet around.

## Controls

| | Keyboard and mouse | Gamepad | Touch |
|---|---|---|---|
| Move | W A S D | Left stick | Left thumb, the stick appears where you touch |
| Look | Mouse | Right stick | Drag on the right half |
| Fire | Left click | Right trigger | FIRE |
| Jetpack (hold) | Right click or Shift | Left trigger or left shoulder | JET |
| Jump | Space | A | JUMP |
| Use | E | X | |
| Deploy | G | Y | |
| Let go of the mouse | Esc | | |

Click in the window to capture the mouse. The touch controls show when you touch the screen and hide when you use a keyboard or gamepad.

The jetpack drains energy while you hold it, and the energy starts to refill a moment after you let go. You keep your speed in the air and when you land on a downhill.

## Building

Vectorfall uses Godot 4.7.2, the Compatibility renderer and Jolt physics. The scripts expect these local tools, which aren't in the repo:

- `tools/godot/Godot_v4.7.2-stable_linux.x86_64`, with an empty `._sc_` file beside it to keep settings in `tools/godot/editor_data`
- Godot 4.7.2 export templates in `tools/godot/editor_data/export_templates/4.7.2.stable`
- Android SDK and Java 21, set under Export › Android in the editor settings

```sh
tools/build-android.sh             # phone APK, arm64
tools/build-android.sh --emulator  # emulator APK, x86_64
```

The APKs are signed with the Android debug key and go in `build/`. The code is in `scripts`, shaders in `shaders` and the main scene in `scenes`. Everything in the world is made in code.

To take a picture of the test map (it needs a screen):

```sh
tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path . res://tools/shots/map_shot.tscn
```

## Testing

Run the headless tests on the computer:

```sh
tools/run-tests.sh
```

They check the jetpack, movement in the air, that soldiers move only from their commands, the touch controls and saving and loading match state.

## Licence

Vectorfall is free software under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE).
