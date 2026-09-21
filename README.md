# Xcode launcher

Builds a small `.app` that starts an older Xcode on a newer macOS, next to the Xcode you already use.

Example: you are on **macOS 27** with **Xcode 27** installed, and you still need **Xcode 26.6** for a project. macOS refuses to open Xcode 26.6 and says the app is not supported on this version of macOS. This script builds `~/Applications/Xcode 26.6.app`. That app opens the real Xcode 26.6.

Nothing on the system is modified. It needs no SIP changes, no `sudo`, and it does not patch any Apple plist.

---

## Contents

- [How it works](#how-it-works)
- [Compatibility](#compatibility)
- [Requirements](#requirements)
- [What to download and where to get it](#what-to-download-and-where-to-get-it)
- [Step by step](#step-by-step)
- [Using the older Xcode](#using-the-older-xcode)
- [Command-line tools](#command-line-tools)
- [Things you must not do](#things-you-must-not-do)
- [Updating, moving and removing](#updating-moving-and-removing)
- [Troubleshooting](#troubleshooting)

---

## How it works

macOS does not block old Xcode because the binary can't run. It blocks it with a lookup in LaunchServices, the part of macOS that opens apps from Finder, the Dock and Spotlight.

1. LaunchServices reads the app's `Info.plist` and checks `CFBundleIdentifier` and `CFBundleVersion`.
2. It compares them against a block list in
   `/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Exceptions.plist`.
3. On macOS 27, that list has an entry for `com.apple.dt.Xcode` marked `HardDisabled`. It covers every build below `24999`. Xcode 26.6 is build `24959`, so it is refused.

The launcher gets around this lookup:

- It is a separate `.app` with its own bundle identifier (`app.thepixelforge.xcode-launcher.26-6`), so it never matches the block list.
- Its executable is a two-line shell script that `exec()`s the real binary at `Xcode-26.6.app/Contents/MacOS/Xcode`.
- `exec()` replaces the launcher process with Xcode itself. LaunchServices is not asked again, you get one Dock icon, and no stray parent process is left behind.

The Xcode bundle is never touched, so its Apple code signature stays valid.

---

## Compatibility

| | Tested | Should work | Not needed |
|---|---|---|---|
| **macOS** | 27.0 (Apple silicon) | Any macOS whose `Exceptions.plist` blocks the older Xcode | |
| **Older Xcode (the one you launch)** | 26.6 (build 24959) | Other releases whose binary still runs on your macOS | Xcode with the same or newer major version as macOS (the script warns you) |
| **Current Xcode (your main one)** | 27.0 | Any | |

Keep in mind:

- The launcher only removes the **LaunchServices block**. It can't make Xcode run if the binary itself doesn't support your OS. Xcode 26.x declares a minimum of macOS 14.0 in its Mach-O header (`vtool -show-build .../Contents/MacOS/Xcode` shows `minos 14.0`), so it runs fine on macOS 27. Much older Xcode releases may crash on launch because of missing or changed system frameworks, and a launcher can't fix that.
- Apple does not support running an Xcode that the OS has disabled. Use it to build, test and archive older projects. Use your current Xcode for everything else.
- The script uses `zsh`, which has been the default shell on macOS since 10.15. It works on Apple silicon and on Intel.

You can check whether your macOS blocks a given Xcode:

```sh
plutil -p /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Exceptions.plist \
  | grep -A14 '"com.apple.dt.Xcode"'

/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/Xcode-26.6.app/Contents/Info.plist
```

If the `CFBundleVersion` falls inside one of the `LowVersion`/`HighVersion` ranges, macOS blocks it and you need the launcher.

---

## Requirements

- **A Mac on the newer macOS**, for example macOS 27.
- **Your current Xcode** in `/Applications/Xcode.app`, selected with `xcode-select`. It stays your default.
- **The older Xcode**, unpacked from Apple's `.xip` (see below).
- **An Apple Account** (free) to download old Xcode releases from Apple.
- **Free disk space.** An unpacked Xcode takes tens of GB, and expanding the `.xip` briefly needs room for both the archive and the result.
- **This repository**, from `git clone` or as a downloaded ZIP.
- **Admin rights only to move Xcode into `/Applications`.** The script itself runs as your user and writes only to `~/Applications`.

The script needs nothing else. `PlistBuddy`, `codesign`, `lsregister`, `sw_vers` and `xcode-select` all ship with macOS.

---

## What to download and where to get it

### 1. The older Xcode

Pick **one** of these:

**Apple Developer website (official)**

1. Open <https://developer.apple.com/download/all/?q=xcode> and sign in with your Apple Account. A free account is enough.
2. Find the release you need, for example **Xcode 26.6**, and download the `.xip`.

**Xcodes (third party, open source)**

- App: <https://github.com/XcodesOrg/XcodesApp>
- CLI: <https://github.com/XcodesOrg/xcodes> (`brew install xcodesorg/made/xcodes`)

Xcodes downloads from Apple's servers with your Apple Account, expands the archive for you, and can install several versions side by side.

> Do **not** use the Mac App Store. It always installs the latest Xcode and replaces `/Applications/Xcode.app`.

### 2. This script

```sh
git clone <this-repo-url> xcode-launcher
cd xcode-launcher
```

Or download the ZIP from the repository page and unzip it.

---

## Step by step

### Step 1: Unpack the older Xcode

If you used the Xcodes app, skip to Step 2.

Double-click the `.xip` in Finder, or run:

```sh
cd ~/Downloads
xip --expand Xcode_26.6.xip
```

This takes several minutes and produces `Xcode.app`.

### Step 2: Rename it and move it into `/Applications`

Your current Xcode already lives at `/Applications/Xcode.app`. **Do not overwrite it.** Give the old one a versioned name:

```sh
mv ~/Downloads/Xcode.app /Applications/Xcode-26.6.app
```

`Xcode-26.6.app` is the name the script looks for by default. If you choose another name or location, pass the path in Step 4.

Check the version:

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Xcode-26.6.app/Contents/Info.plist
```

If you double-click `Xcode-26.6.app` now, macOS will refuse to open it. That is expected.

### Step 3: Make sure your current Xcode is still the default

```sh
xcode-select -p
# /Applications/Xcode.app/Contents/Developer
```

If it points at the old Xcode, switch it back with `sudo xcode-select -s /Applications/Xcode.app`. Auto-detection in the next step skips whichever Xcode `xcode-select` points to, so this also keeps the script from picking the wrong one.

### Step 4: Run the script

```sh
chmod +x create-xcode-launcher.sh
./create-xcode-launcher.sh
```

How the script finds the older Xcode:

1. **A path is given** (`./create-xcode-launcher.sh /path/to/Xcode-26.6.app`): it uses that path.
2. **No path, but `/Applications/Xcode-26.6.app` exists**: it uses that.
3. **Otherwise it scans** `/Applications/Xcode*.app` and `~/Applications/Xcode*.app` for real Xcode bundles (`com.apple.dt.Xcode`) and skips the one `xcode-select` points to.
   - One left: it uses that one.
   - More than one left: it stops and prints the command to run for each candidate. Rerun with the path you want.
   - None left: it stops with an error.

What it then does:

1. Reads the version and build from the older Xcode's `Info.plist`.
2. Compares the Xcode major version with the macOS major version. If Xcode isn't older, it warns that you don't need a launcher, then continues anyway.
3. Creates `~/Applications/Xcode <version>.app`, replacing any existing launcher with the same name, containing:
   - `Contents/Info.plist` with bundle id `app.thepixelforge.xcode-launcher.<version>` and `LSMinimumSystemVersion` 14.0
   - `Contents/MacOS/launcher`, the `exec` stub
   - `Contents/Resources/Xcode.icns`, copied from the older Xcode so it has the right icon
4. Signs the launcher ad-hoc (`codesign --sign -`) so Gatekeeper and privacy (TCC) prompts leave it alone.
5. Registers it with LaunchServices so Spotlight and Finder can find it.

Example output:

```
--------------------------------------------------------
  Xcode launcher builder
--------------------------------------------------------
  using default path: /Applications/Xcode-26.6.app

  source      : /Applications/Xcode-26.6.app
  version     : 26.6  (build 24959)
  running on  : macOS 27.0

  launcher    : /Users/you/Applications/Xcode 26.6.app
  bundle id   : app.thepixelforge.xcode-launcher.26-6

  [ok] wrote Info.plist
  [ok] wrote launcher stub
  [ok] copied icon
  [ok] signed ad-hoc
  [ok] registered with LaunchServices
--------------------------------------------------------
  Done
--------------------------------------------------------
```

### Step 5: Launch it

Open **Spotlight** (`⌘ Space`) and type `Xcode 26.6`, or open `~/Applications` in Finder and double-click **Xcode 26.6**.

Once Xcode is running, right-click its Dock icon and choose **Options > Keep in Dock**. The pinned icon starts the launcher.

### Step 6: Answer the first-launch prompts

- If the older Xcode asks to **install additional components**, click **Cancel**. See [Things you must not do](#things-you-must-not-do).
- Check **Xcode > About Xcode** and make sure it shows the old version.

---

## Using the older Xcode

- **Open projects from inside Xcode** with **File > Open** or the welcome window. Double-clicking a `.xcodeproj` in Finder opens it in your default Xcode, which is the current one.
- **Simulators** are shared between both Xcodes through `/Library/Developer/CoreSimulator`. Manage simulator runtimes from your current Xcode.
- **Signing and accounts** are shared too. Accounts you add in one Xcode appear in the other.
- **DerivedData** is shared (`~/Library/Developer/Xcode/DerivedData`). If you switch the same project between versions, clean the build folder first (`⇧⌘K`).

---

## Command-line tools

`xcodebuild`, `xcrun`, `swift` and the rest don't go through LaunchServices, so they need no launcher. Point `DEVELOPER_DIR` at the older Xcode for a single command:

```sh
DEVELOPER_DIR="/Applications/Xcode-26.6.app/Contents/Developer" xcodebuild -version
DEVELOPER_DIR="/Applications/Xcode-26.6.app/Contents/Developer" xcodebuild -scheme MyApp -destination 'generic/platform=iOS' build
```

Prefer this to `sudo xcode-select -s`. `DEVELOPER_DIR` affects only that one command, while `xcode-select` changes the default for the whole system.

---

## Things you must not do

- **Do not run `xcodebuild -runFirstLaunch` from the older Xcode.** It installs its own CoreSimulator framework into `/Library/Developer`, overwriting the newer one, and that breaks your current Xcode.
- **Do not accept "Install additional components"** when the older Xcode offers it. It does the same thing as `-runFirstLaunch`.
- **Do not replace `/Applications/Xcode.app`** with the older Xcode. Always give the old one a versioned name.
- **Do not edit the older Xcode's `Info.plist`** to get around the block. That breaks its code signature. The launcher exists so you don't have to.

If you already broke your current Xcode this way, reopen it (`/Applications/Xcode.app`) and let it install its components again, or run:

```sh
xcodebuild -runFirstLaunch
```

with your **current** Xcode selected.

---

## Updating, moving and removing

- **The Xcode path is written into the launcher.** If you move or rename the older Xcode, run the script again with the new path.
- **Running it again replaces the launcher** for that version, so you can rerun it safely.
- **Several old versions** each get their own launcher (`Xcode 26.4.app`, `Xcode 26.6.app`, ...). Pass each path explicitly.
- **Change the default path** by editing `DEFAULT_XCODE` near the top of `create-xcode-launcher.sh`.
- **To remove all launchers:**

  ```sh
  ./create-xcode-launcher.sh --uninstall
  ```

  This deletes only apps in `~/Applications` whose bundle id starts with `app.thepixelforge.xcode-launcher`. The Xcode apps themselves are not touched. Delete `/Applications/Xcode-26.6.app` yourself if you no longer need it.

---

## Troubleshooting

**macOS still says Xcode is not supported.**
You opened `/Applications/Xcode-26.6.app` instead of the launcher. Open `~/Applications/Xcode 26.6.app`. Check a Dock item by right-clicking it and choosing **Options > Show in Finder**.

**The script stops with "more than one candidate".**
Several Xcodes were found. Run it again with the path of the one you want, as the script shows.

**The script stops with "only the active Xcode was found".**
`xcode-select` points at the Xcode you wanted a launcher for, or the old one isn't in `/Applications` or `~/Applications`. Pass the path explicitly, or fix `xcode-select` (Step 3).

**The launcher doesn't show up in Spotlight.**
Spotlight can take a minute to index it. You can also register it by hand:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"Xcode 26.6.app"
```

**The launcher opens and then nothing happens.**
Run the stub directly to see Xcode's error output:

```sh
~/Applications/"Xcode 26.6.app"/Contents/MacOS/launcher
```

If Xcode crashes here, the binary itself doesn't run on this macOS, and a launcher can't fix that (see [Compatibility](#compatibility)).

**Simulators or the current Xcode stopped working after using the old one.**
Components were probably installed from the older Xcode. See the recovery steps in [Things you must not do](#things-you-must-not-do).
