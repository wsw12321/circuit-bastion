# Android build

Circuit Bastion exports an Android ARM64 debug APK from the same Godot scene and deterministic simulation used by the desktop builds.

## Local export

Install Godot 4.3, the Android SDK platform 34, build-tools 34.0.0, command-line tools, CMake 3.10.2.4988404, NDK 23.2.8568313, and an OpenJDK 17 runtime. Configure the Godot Android export templates, then run:

    godot4 --headless --path . --export-debug "Android" dist/godot/circuit-bastion-android-arm64.apk

The Android preset targets arm64-v8a, landscape orientation, and package name com.circuitbastion.game. The generated debug APK is suitable for device smoke testing with adb install -r.

## Touch layout

Android boots MobileBattleView. The battlefield fills the upper area, while the lower action bar provides pause, speed, replay, and shop commands with touch-sized hit targets. Tapping a grid cell selects its module, single-finger drags orbit the 3D camera, and two-finger pinch gestures zoom it. A tap confirms a deployment without mutating simulation state during the drag.

## CI artifact

Pull requests run the Android headless contract probe and export job when Godot or export files change. Version tags build the same APK and attach it to the GitHub Release as circuit-bastion-android-arm64.apk.

The CI artifact uses the standard debug keystore. A store-signed release bundle requires a separate protected keystore and signing configuration before publication to an app store.
