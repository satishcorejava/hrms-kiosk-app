# HRMS Kiosk

An Android app for a shared store tablet or phone. Staff punch in and out by **face** or by **employee code and PIN**. The punch time is always the server's clock; nobody can choose it.

## How it works

- **Pairing:** HR adds the device under **Time Clock → Devices** in the HRMS portal and gets an 8-character pairing code. The app trades the code for a device key, which can only identify staff and punch. Revoking the device stops it at once.
- **Face:** the face check runs in the app with the same engine as the web portal (face-api.js, bundled in `assets/face`, so no CDN is needed). A face set up in the portal is recognised here.
  - Live-person check: look straight, turn the head to one side, look straight again.
  - The server compares the face and keeps a photo with each punch.
- **PIN:** the employee code and the tablet PIN set under **Time Clock → Staff settings**. Staff whose punches need a face check also look at the camera.
- **Layout:** a phone in portrait shows one column. A tablet in landscape shows the clock on the left and the punch screen on the right.
- **Manager menu:** long-press the clock, then enter the device's exit PIN (set by HR under Devices). From there you can:
  - lock or unlock the app on screen
  - refresh the device's settings
  - unpair the device

## Build

```sh
flutter pub get
flutter build apk --release                  # build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --split-per-abi  # smaller APKs, one per CPU type
```

The release build is signed with the debug key for now. Add a release keystore in `android/app/build.gradle.kts` before publishing it on Play.

## Setting up a device

1. Install the APK and open **HRMS Kiosk**.
2. In the portal, go to **Time Clock → Devices → Add device**: choose a name, a location, how staff punch (face, PIN or both) and an exit PIN.
3. Type the pairing code into the app. The server address defaults to production; change it on the pairing screen if needed.
4. Allow the camera when asked.

### Kiosk lock

Choose one of these:

- **Screen pinning (quick):** in the manager menu, turn on **Lock the app on screen**. Android asks once to pin the app. On some phones it can be undone by holding Back and Overview.
- **Full kiosk (recommended for store tablets):** make the app the device owner on a freshly reset device, before any Google account is added:
  ```sh
  adb shell dpm set-device-owner com.cckart.hrms_kiosk/.KioskAdminReceiver
  ```
  Then **Lock the app on screen** locks it completely, with no prompt. The status bar, Home and Recents are disabled, and only the exit PIN gets out.
- **Home screen:** the app can also be chosen as the device's home app (Settings → Apps → Default apps → Home), so it opens on start-up.
