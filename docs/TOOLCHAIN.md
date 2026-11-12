# Toolchain pin

Swipeinn builds against a pinned Flutter SDK so that a demo build is
reproducible and cannot be changed by an accidental upgrade.

## Pinned version

| Item | Value |
| --- | --- |
| Flutter | `3.47.9`, channel `stable` |
| Dart | `3.13.7` |
| DevTools | `2.60.0` |
| Framework revision | `c197ca5199e` |
| Engine revision | `89c39edfdfa` (`9e025265bef30b838c0c1b68cad19decf97048f2`) |
| SDK path | `C:\Users\Lenovo\flutter` |
| Recovery tag | `pin-3.47.9` |

## Why 3.47.9 and not the latest stable

Upstream `stable` moved to **3.50.0** on 2026-11-09, three days before this pin
was made. That is a quarterly feature release with no hotfixes behind it, and
quarterly releases are where engine regressions and Gradle/AGP template bumps
land. Neither is something to absorb on the way to a demo.

The pin keeps the fixes that actually matter for this project:

- **3.47.8** carries a security advisory ([GHSA-frr6-h895-5pxp](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp)):
  it updates BoringSSL in the Dart runtime and moves `dart:io` on Android 14+
  to the updatable Conscrypt APEX root store. The advisory explicitly asks
  Android, Windows, and Linux shippers to rebuild on this version.
- **3.47.9** fixes a `flutter_tools` crash on Windows paths over `MAX_PATH`
  (`OS Error 206`) and a `StateError` in native-assets compilation.

## Restoring the pin

If the SDK has drifted, return to the pinned commit:

```powershell
git -C C:\Users\Lenovo\flutter checkout pin-3.47.9
flutter --version   # expect 3.47.9 / Dart 3.13.7
```

## Upgrading later, deliberately

Do this after a demo, not before one, and never in the same change as a feature.

```powershell
git -C C:\Users\Lenovo\flutter checkout stable
git -C C:\Users\Lenovo\flutter pull --ff-only
flutter --version
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug --target-platform android-x64
```

If any step fails, reset the pin tag to the new verified commit only after the
whole checklist is green.

## Verification checklist

Run these before any presentation build:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug --target-platform android-x64
```

Expected: `flutter analyze` reports no issues, all tests pass, and both build
commands exit 0.

## Known environment constraints

- The machine has 6 GB RAM, so `android/gradle.properties` caps Gradle at a
  1.5 GB heap and two workers. Do not raise those limits here.
- Android emulator images for API 37 expect 16 GB RAM. Use a physical device
  for runtime testing; build the APK with the default multi-ABI target for a
  real phone.
