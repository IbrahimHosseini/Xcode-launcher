#!/bin/zsh
#
# create-xcode-launcher.sh
#
# Builds a thin launcher .app that starts an older Xcode on a newer macOS.
#
# Why this works:
#   macOS blocks old Xcode via LaunchServices, which matches on
#   CFBundleIdentifier "com.apple.dt.Xcode" plus CFBundleVersion against
#   ranges in CoreTypes.bundle/Contents/Resources/Exceptions.plist.
#   The launcher carries a DIFFERENT bundle identifier, so it never matches,
#   and it exec()s straight into the Xcode binary, bypassing LaunchServices.
#   Nothing in the system is modified. No SIP changes. No patched plists.
#
# Usage:
#   ./create-xcode-launcher.sh                          # auto-detect
#   ./create-xcode-launcher.sh /Applications/Xcode-26.6.app
#   ./create-xcode-launcher.sh --uninstall
#

set -euo pipefail

# zsh aborts the whole command when a glob matches nothing (NOMATCH is on by
# default, unlike bash). null_glob makes an unmatched pattern expand to
# nothing instead, so scanning a directory that does not exist is harmless.
setopt null_glob

# The Xcode this script targets when no path is passed on the command line.
DEFAULT_XCODE="/Applications/Xcode-26.6.app"

BUNDLE_PREFIX="app.thepixelforge.xcode-launcher"
INSTALL_DIR="$HOME/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# ----------------------------------------------------------------------------
# output helpers
# ----------------------------------------------------------------------------

info()  { print -r -- "  $*"; }
ok()    { print -r -- "  [ok] $*"; }
warn()  { print -r -- "  [!]  $*"; }
die()   { print -r -- "  [x]  $*" >&2; exit 1; }
rule()  { print -r -- "--------------------------------------------------------"; }

# ----------------------------------------------------------------------------
# uninstall mode
# ----------------------------------------------------------------------------

if [[ "${1:-}" == "--uninstall" ]]; then
    rule
    print -r -- "  Removing Xcode launchers"
    rule
    found=0
    for app in "$INSTALL_DIR"/Xcode*.app; do
        [[ -e "$app" ]] || continue
        bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
              "$app/Contents/Info.plist" 2>/dev/null || true)
        if [[ "$bid" == "$BUNDLE_PREFIX"* ]]; then
            rm -rf "$app"
            ok "removed $app"
            found=1
        fi
    done
    (( found )) || info "nothing to remove"
    exit 0
fi

# ----------------------------------------------------------------------------
# locate the old Xcode
# ----------------------------------------------------------------------------

rule
print -r -- "  Xcode launcher builder"
rule

read_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$1/Contents/Info.plist" 2>/dev/null || true
}

XCODE_APP="${1:-}"

if [[ -n "$XCODE_APP" ]]; then
    XCODE_APP="${XCODE_APP%/}"
    [[ -d "$XCODE_APP" ]] || die "not found: $XCODE_APP"

elif [[ -x "$DEFAULT_XCODE/Contents/MacOS/Xcode" ]]; then
    XCODE_APP="$DEFAULT_XCODE"
    info "using default path: $XCODE_APP"

else
    warn "default path not found: $DEFAULT_XCODE"
    info "scanning for Xcode installations..."
    typeset -a candidates
    candidates=()

    for app in /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app; do
        [[ -x "$app/Contents/MacOS/Xcode" ]] || continue
        bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
              "$app/Contents/Info.plist" 2>/dev/null || true)
        [[ "$bid" == "com.apple.dt.Xcode" ]] || continue
        candidates+=("$app")
    done

    (( ${#candidates[@]} )) || die "no Xcode installations found"

    # current default, so we can skip it
    current=$(xcode-select -p 2>/dev/null | sed 's#/Contents/Developer$##' || true)

    typeset -a older
    older=()
    for app in "${candidates[@]}"; do
        v=$(read_version "$app")
        info "found  $app  (version ${v:-unknown})"
        [[ "$app" == "$current" ]] && continue
        older+=("$app")
    done

    if (( ${#older[@]} == 0 )); then
        die "only the active Xcode was found, nothing to build a launcher for"
    elif (( ${#older[@]} > 1 )); then
        print -r -- ""
        warn "more than one candidate. Pass the path explicitly:"
        for app in "${older[@]}"; do info "$0 \"$app\""; done
        exit 1
    fi

    XCODE_APP="${older[1]}"
fi

XCODE_BIN="$XCODE_APP/Contents/MacOS/Xcode"
[[ -x "$XCODE_BIN" ]] || die "no executable at $XCODE_BIN"

VERSION=$(read_version "$XCODE_APP")
[[ -n "$VERSION" ]] || die "could not read version from $XCODE_APP"

BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
        "$XCODE_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")

print -r -- ""
info "source      : $XCODE_APP"
info "version     : $VERSION  (build $BUILD)"

MAJOR="${VERSION%%.*}"
CURRENT_OS=$(sw_vers -productVersion)
OS_MAJOR="${CURRENT_OS%%.*}"
info "running on  : macOS $CURRENT_OS"

if (( MAJOR >= OS_MAJOR )); then
    print -r -- ""
    warn "Xcode $VERSION is not blocked on macOS $CURRENT_OS."
    warn "You do not need a launcher for this one. Continuing anyway."
fi

# ----------------------------------------------------------------------------
# build the launcher bundle
# ----------------------------------------------------------------------------

APP_NAME="Xcode $VERSION"
APP="$INSTALL_DIR/$APP_NAME.app"
BUNDLE_ID="$BUNDLE_PREFIX.${VERSION//./-}"

print -r -- ""
info "launcher    : $APP"
info "bundle id   : $BUNDLE_ID"
print -r -- ""

mkdir -p "$INSTALL_DIR"
[[ -e "$APP" ]] && { rm -rf "$APP"; ok "replaced existing launcher"; }

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- Info.plist -------------------------------------------------------------
# LSMinimumSystemVersion is set to 14.0 to match the binary's real Mach-O
# minos, not the 26.6 that Apple declares in Xcode's own Info.plist.
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>Xcode</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
ok "wrote Info.plist"

# --- launcher stub ----------------------------------------------------------
# exec replaces this process image entirely, so no duplicate Dock icon and no
# orphan parent process is left behind.
cat > "$APP/Contents/MacOS/launcher" <<EOF
#!/bin/zsh
exec "$XCODE_BIN" "\$@"
EOF

chmod +x "$APP/Contents/MacOS/launcher"
ok "wrote launcher stub"

# --- icon -------------------------------------------------------------------
if [[ -f "$XCODE_APP/Contents/Resources/Xcode.icns" ]]; then
    cp "$XCODE_APP/Contents/Resources/Xcode.icns" "$APP/Contents/Resources/Xcode.icns"
    ok "copied icon"
else
    warn "no Xcode.icns found, launcher will use the generic app icon"
fi

# --- ad-hoc signature -------------------------------------------------------
# The bundle was created locally so it carries no quarantine attribute.
# An ad-hoc signature keeps Gatekeeper and TCC quiet.
if codesign --force --deep --sign - "$APP" 2>/dev/null; then
    ok "signed ad-hoc"
else
    warn "ad-hoc signing failed, the launcher will still run"
fi

# --- register with LaunchServices so Spotlight finds it ---------------------
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP" 2>/dev/null || true
    ok "registered with LaunchServices"
fi

# ----------------------------------------------------------------------------
# done
# ----------------------------------------------------------------------------

print -r -- ""
rule
print -r -- "  Done"
rule
info "Launch it from Spotlight or Finder as \"$APP_NAME\"."
print -r -- ""
info "Command line toolchain for this version (LaunchServices is not"
info "involved, so no launcher is needed there):"
print -r -- ""
info "  DEVELOPER_DIR=\"$XCODE_APP/Contents/Developer\" xcodebuild -version"
print -r -- ""
warn "Do NOT run 'xcodebuild -runFirstLaunch' from Xcode $VERSION."
warn "It overwrites the shared CoreSimulator framework in /Library/Developer"
warn "and will break your current Xcode. If Xcode $VERSION prompts to install"
warn "additional components on launch, cancel."
print -r -- ""
info "To remove the launcher later:  $0 --uninstall"
print -r -- ""