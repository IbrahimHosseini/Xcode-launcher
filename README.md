# Xcode Launcher

Run an older Xcode on a newer macOS, without patching anything.

macOS refuses to launch Xcode versions that Apple has not qualified for the
current OS release. You get a slashed icon in Finder and this dialog:

> This version of Xcode isn't supported in this version of macOS.

This repository contains a single script that works around it by creating a
thin launcher app. Nothing on your system is modified.

---

## Is this safe?

The short answer is yes, and the rest of this section explains exactly why so
you do not have to take my word for it.

**What this script does NOT do:**

- It does not disable System Integrity Protection (SIP)
- It does not modify, patch, or replace any file inside `/System`
- It does not touch the Signed System Volume or its seal
- It does not modify the Xcode app bundle you already have
- It does not require `sudo`
- It does not download anything

**What it does:** it creates one small `.app` bundle in `~/Applications`
containing a five-line shell stub. That is the entire footprint. Removing it
is a single `rm -rf`, and the script provides an `--uninstall` flag that does
exactly that.

---

## Why the block exists in the first place

This is worth understanding, because it explains why the workaround is so
small.

The block is a **policy decision, not a technical incompatibility**. Two pieces
of evidence:

**1. The binary declares a much lower minimum than Apple advertises.**

```
$ vtool -show-build /Applications/Xcode.app/Contents/MacOS/Xcode
 platform MACOS
    minos 14.0
      sdk 27.0
```

The Mach-O `LC_BUILD_VERSION` load command says the binary runs on macOS 14 and
later. Meanwhile `Info.plist` declares `LSMinimumSystemVersion = 26.6`. The
kernel and dyld have no objection to loading this binary. The restriction lives
entirely above them.

**2. The decision is stored in a data file, not in Xcode.**

macOS keeps a compatibility exception database at:

```
/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Exceptions.plist
```

It maps bundle identifiers to version ranges and flags. The entry for Xcode
looks like this:

```
"com.apple.dt.Xcode" => [
  0 => { "HardDisabled" => true, "LowVersion" => "2",           "HighVersion" => "9999.99.98" }
  1 => { "HardDisabled" => true, "LowVersion" => "9999.99.100", "HighVersion" => "24999" }
]
```

The ranges are matched against `CFBundleVersion` (the build number), not the
version you see in the UI:

| Xcode | `CFBundleVersion` | In range | Result |
|---|---|---|---|
| 26.6 | `24959` | yes, record 1 | blocked |
| 27.0 | `25183.107.5` | no | allowed |

Note the one-value gap between the two records: `9999.99.99`. That is the
sentinel build number used by internal builds, which is why Apple split what
could have been a single range into two.

When LaunchServices matches a bundle against a `HardDisabled` record, it
refuses the launch before `exec()` is ever reached, and marks the app with the
slashed icon. You can confirm your own machine agrees:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
  | grep -A2 "bundle flags"
```

The blocked Xcode carries a `version-too-low` flag. The current one does not.

---

## How the workaround works

Because the check happens in **LaunchServices** and keys on
`CFBundleIdentifier`, there are two ways past it:

1. Execute the binary directly, which never goes through LaunchServices:
   ```bash
   /Applications/Xcode-26.6.app/Contents/MacOS/Xcode
   ```
2. Launch it from a bundle with a different identifier.

This script does the second, so you get a normal icon in Spotlight, Finder, and
the Dock. The launcher bundle contains:

```sh
#!/bin/zsh
exec "/Applications/Xcode-26.6.app/Contents/MacOS/Xcode" "$@"
```

`exec` replaces the launcher process image entirely, so there is no duplicate
Dock icon and no orphan parent process. The bundle declares
`LSMinimumSystemVersion = 14.0`, matching the binary's real `minos` rather than
Apple's advertised policy value, and is signed ad-hoc so Gatekeeper stays quiet.

---

## Requirements

- macOS with zsh (the default shell since Catalina)
- An older Xcode already installed, for example `/Applications/Xcode-26.6.app`

If you keep multiple Xcode versions, rename them so they do not collide, for
example `Xcode-26.6.app` and `Xcode.app`.

---

## Usage

```bash
chmod +x create-xcode-launcher.sh

# Uses the default path defined at the top of the script
./create-xcode-launcher.sh

# Or point it at a specific Xcode
./create-xcode-launcher.sh "/Applications/Xcode-26.6.app"

# Remove any launchers this script created
./create-xcode-launcher.sh --uninstall
```

The launcher is created in `~/Applications` and named after the Xcode version,
for example `Xcode 26.6.app`. Launch it from Spotlight like any other app.

To target a different Xcode by default, edit one line near the top of the
script:

```sh
DEFAULT_XCODE="/Applications/Xcode-26.6.app"
```

---

## What works

Verified on macOS 27 with Xcode 26.6 launched this way, alongside Xcode 27
installed as the active version:

| | Status |
|---|---|
| Editor, indexing, code completion | verified working |
| Build, compile, link | verified working |
| iOS Simulator | verified working |
| Running a real project on a simulator | verified working |
| Command line (`xcodebuild`, `simctl`) | verified working, no launcher needed |
| Archive and export | not tested |
| Debugging on a physical device | not tested |
| SwiftUI Previews | not tested |

If you test any of the untested rows, an issue or PR updating this table is
welcome.

### A note on the simulator

Part of the simulator stack lives outside the Xcode bundle and is shared across
every installed version:

```
/Library/Developer/PrivateFrameworks/CoreSimulator.framework
/Library/Developer/CoreSimulator/
```

Whichever Xcode ran its first launch most recently owns those paths. In
practice this is fine, because `CoreSimulator` is backward compatible: the
version installed by Xcode 27 drives Xcode 26.6 without complaint.

What actually matters is **runtime availability**, not the framework. Simulator
runtimes are installed separately and each Xcode expects certain ones. Check
what you have:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.6.app/Contents/Developer" xcrun simctl list runtimes
```

If the runtime your project targets is still present, the simulator works. If a
runtime shows up under `Unavailable`, it is no longer usable and needs to be
reinstalled from Xcode's settings. Prefer selecting a runtime that shipped with
the older Xcode rather than one added later by the newer Xcode.

---

## Warning: do not run `-runFirstLaunch`

```bash
# Do NOT do this with the older Xcode
sudo /Applications/Xcode-26.6.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch
```

This overwrites the shared components listed above with older versions and will
break your current Xcode and your simulators. If the older Xcode prompts to
install additional components on launch, cancel.

---

## Command line toolchain

The block only affects app launches, so `xcodebuild` is unaffected. Use
`DEVELOPER_DIR` per command instead of changing `xcode-select` globally, so
your current Xcode stays the default:

```bash
DEVELOPER_DIR="/Applications/Xcode-26.6.app/Contents/Developer" xcodebuild -version
DEVELOPER_DIR="/Applications/Xcode-26.6.app/Contents/Developer" xcodebuild -showsdks
```

---

## Uninstall

```bash
./create-xcode-launcher.sh --uninstall
```

This finds launchers by their bundle identifier prefix rather than by name, so
it will never delete a real Xcode installation, even if you renamed the
launcher.

---

## A note on when to use this

This configuration is not supported by Apple. Their own position, stated by DTS
on the developer forums, is that these combinations are blocked because they
are not qualified, not because they are known to fail.

That distinction matters for how you use it. For local development, debugging,
and keeping a project building while you migrate, the risk is low and the
tradeoff is reasonable. For producing release artifacts you upload to App Store
Connect, it is not: if something goes wrong you will not be able to tell
whether the cause is your code or an unqualified toolchain.

The better long-term fix is ordering your upgrades correctly. Test the new
Xcode on your current macOS first, then upgrade macOS. That direction is always
supported. The reverse never is.

---

## License

Released under the [MIT License](https://github.com/IbrahimHosseini/Xcode-launcher?tab=MIT-1-ov-file#).

Copyright (c) 2026 Ibrahim Hosseini.