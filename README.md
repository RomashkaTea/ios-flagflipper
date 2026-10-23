# FlagFlipper

FlagFlipper gives you a searchable view of Apple's on-device feature flags. You
can inspect the flags defined by iOS, see which ones have an override, and force
an individual flag on or off without disturbing the rest of its domain.

> [!IMPORTANT]
> FlagFlipper follows DarkSword's supported range: **iOS/iPadOS 17.0–18.7.1**
> and **26.0–26.0.1** on arm64e iPhones and iPads. A19/A19 Pro and M5 devices
> are not supported. The app refuses to prepare access or write an override
> outside that range.

This is research software for a device you own and are authorized to test.
Feature flags are private, undocumented, and sometimes unfinished.

> [!WARNING]
> An override can crash an app or system service, and a bad flag
> can leave the device in a boot loop. Make a current backup and **enable Find My
> before changing flags**.
>
> If a looping device can still connect to Wi-Fi or cellular service, a pending
> [remote erase through Find My](https://support.apple.com/guide/iphone/erase-a-device-iph21a030ae3/ios)
> may be received and clear the bad override. This is only a last-chance option,
> not a guaranteed recovery method. It permanently erases all content and
> settings, requires the Apple Account password to reactivate the device, and
> may never reach a device that cannot get online. If it succeeds, it may avoid
> a computer firmware restore—which installs the latest available OS—and give
> you a chance to keep the currently installed iOS/iPadOS version.

## What it does

- Searches flags by name or domain.
- Shows each flag's declared default and development phase, when available.
- Distinguishes inherited values from explicit on/off overrides.
- Lets you **Force On**, **Force Off**, or **Use Default** for one flag at a
  time.
- Preserves unrelated flags and metadata in the same plist.

## How it works

iOS keeps the definitions and overrides in different places:

|                    | Path                                                   |
| ------------------ | ------------------------------------------------------ |
| System definitions | `/System/Library/FeatureFlags/Domain/*.plist`          |
| Overrides          | `/private/var/preferences/FeatureFlags/Domain/*.plist` |

FlagFlipper reads the live system definitions and, after access has been
prepared, merges in the override directory by domain and flag name. An
override that no longer appears in a system definition still shows up in the
app, so it can be removed safely. No build-specific flag catalog is bundled;
the list always comes from the installed OS.

Tapping **Prepare Access** runs the vendored Lara access path, loads the offsets
needed for this build, and escapes the app sandbox. If the offsets are not
already available, FlagFlipper reads the running kernel cache and resolves them
locally. The app must not be attached to a debugger during this step.

### Writing an override

FlagFlipper changes only the selected flag's `Enabled` field. **Use Default**
removes that field instead of writing a guessed value. Any other fields in the
flag—and every other entry in the domain—are left intact.

Writes are guarded against stale data and partial updates. Before replacing a
domain plist, the app checks that it still matches the last refresh, validates
its contents, writes a complete replacement beside it, preserves its mode and
owner, and atomically renames the new file into place. It then syncs the
directory and reads the file back for verification.

The preferences directories only change ownership for the duration of a write.
FlagFlipper saves the original UID and GID in an on-device receipt first. If the
app is interrupted before ownership is restored, it blocks further changes and
offers **Repair Directory Ownership**.

## Build and install

You will need:

- an arm64e iPhone or iPad on iOS/iPadOS 17.0–18.7.1 or 26.0–26.0.1 (excluding
  A19/A19 Pro and M5 devices);
- a Mac with an Xcode version that supports iOS 18; and
- an Apple development team, or another appropriate way to sign and install
  the app.

The Xcode project is checked in. Open it directly:

```sh
git clone <repository-url>
cd FlagFlipper
open FlagFlipper.xcodeproj
```

Select the **FlagFlipper** target, choose your team under **Signing &
Capabilities**, and set a bundle identifier available to that team. Keep the
architecture set to `arm64e`, select the physical device, then build and
install.

Once the app is installed, stop the Xcode debugging session and launch it from
the device. **Prepare Access** deliberately refuses to run while a debugger is
attached.

The project is generated from `project.yml`. If you change that file, install
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and regenerate the project:

```sh
xcodegen generate
```

Signing is disabled in the project definition, so you will need to reapply your
local signing settings after regeneration.

## Using the app

1. Open FlagFlipper and tap **Prepare Access**.
2. Wait for **Access ready**.
3. Find a flag by browsing or searching for its name or domain.
4. Open its menu and choose **Force On**, **Force Off**, or **Use Default**.
5. Restart the affected app or service. Some flags do not take effect until the
   device is restarted.

The value shown as **Definition** comes from the system plist. It is not a live
reading of the feature's effective state. **Unspecified** simply means that the
definition has no boolean `Enabled` key. Some Apple components also define
flags entirely in code; those cannot be discovered from the domain plists and
will not appear here.

## Compatibility notes

The compatibility gate mirrors the range published by the
[pinned Lara release](https://github.com/rooootdev/lara/blob/879e3fae0822776d1f75f91d9f2d1aee505f339e/README.md).
Lara describes iOS 16.x as experimental: DarkSword may affect those versions,
but the required offsets are not generally supported. For that reason
FlagFlipper does not enable iOS 16.x. Lara also notes that results can vary on
M-series iPads.

## Repository layout

```text
App/                    SwiftUI app and guarded storage layer
Vendor/Lara/            Pinned access sources, headers, and libraries
project.yml             XcodeGen project definition
FlagFlipper.xcodeproj/  Generated Xcode project
```

## License

FlagFlipper is available under the [GNU Affero General Public License
v3.0](LICENSE).

The access components in `Vendor/Lara` come from
[rooootdev/lara](https://github.com/rooootdev/lara), pinned to commit
`879e3fae0822776d1f75f91d9f2d1aee505f339e`. They are also distributed under
the AGPL-3.0. See [`Vendor/Lara/README.md`](Vendor/Lara/README.md) for the local
changes and checksums of the bundled libraries.
