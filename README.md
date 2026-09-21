# Xcode launcher

Builds a thin `.app` that starts an older Xcode on a newer macOS.

macOS blocks outdated Xcode through LaunchServices: it matches `CFBundleIdentifier` `com.apple.dt.Xcode` plus `CFBundleVersion` against ranges in `CoreTypes.bundle`. This launcher uses a different bundle identifier, then `exec()`s the real Xcode binary, so LaunchServices never sees the blocked identity.

Nothing on the system is modified. No SIP changes. No patched plists.

## Usage

```sh
chmod +x create-xcode-launcher.sh

./create-xcode-launcher.sh                          # auto-detect
./create-xcode-launcher.sh /Applications/Xcode-26.6.app
./create-xcode-launcher.sh --uninstall
```

The launcher is installed to `~/Applications` (for example `Xcode 26.6.app`) and registered with LaunchServices so Spotlight and Finder can find it.

If no path is given, the script uses `/Applications/Xcode-26.6.app` when that exists. Otherwise it scans `/Applications` and `~/Applications` for real Xcode apps, skips the active `xcode-select` install, and builds a launcher for the remaining one. Pass the path explicitly if more than one candidate is found.

## Command-line tools

`xcodebuild` does not go through LaunchServices, so no launcher is needed:

```sh
DEVELOPER_DIR="/Applications/Xcode-26.6.app/Contents/Developer" xcodebuild -version
```

Do **not** run `xcodebuild -runFirstLaunch` from the older Xcode. It overwrites the shared CoreSimulator framework in `/Library/Developer` and will break the current Xcode. If the older Xcode prompts to install additional components on launch, cancel.
