#!/bin/zsh
# Builds Findy for release and packages it in a disk image.
#
#   scripts/release.sh
#
# Without a signing identity the app is signed ad hoc: it runs, but macOS identifies it by the
# hash of its binary, so every new version asks again for access to Desktop, Documents and the
# like. Set:
#
#   FINDY_SIGN_IDENTITY     the name of a code signing certificate in the keychain: a self-signed
#                           one (see docs/RELEASING.md) or "Developer ID Application: Name (TEAMID)"
#   FINDY_NOTARY_PROFILE    a keychain profile created with `xcrun notarytool store-credentials`
#                           (Developer ID only)
#
# Output: build/release/Findy-<version>.dmg and its SHA-256, which the Homebrew cask needs.

set -euo pipefail
cd "$(dirname "$0")/.."

out="build/release"
derived="$out/DerivedData"
stage="$out/dmg"
identity="${FINDY_SIGN_IDENTITY:--}"

command -v xcodegen >/dev/null || { echo "error: XcodeGen is missing (brew install xcodegen)" >&2; exit 1 }

echo "==> Generating the project"
xcodegen generate --quiet

echo "==> Building (Release, Apple Silicon and Intel)"
xcodebuild -scheme Findy -configuration Release -derivedDataPath "$derived" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    build | grep -E "error:|warning: |BUILD" | grep -v appintents || true

app="$derived/Build/Products/Release/Findy.app"
[[ -d "$app" ]] || { echo "error: the build produced no app" >&2; exit 1 }
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
dmg="$out/Findy-$version.dmg"

# Xcode builds ad hoc, whatever the identity: it refuses a self-signed certificate, which the
# system does not trust. `codesign` accepts it, and trust plays no part in how macOS remembers
# the permissions granted to the app.
if [[ "$identity" != "-" ]]; then
    echo "==> Signing with $identity"
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --deep --strict "$app"

echo "==> Packaging $dmg"
# Only ever removes this script's own staging folder, by its fixed path.
rm -rf "build/release/dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/Findy.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Findy $version" -srcfolder "$stage" -ov -format UDZO "$dmg"

if [[ "$identity" != "-" ]]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
fi

if [[ -n "${FINDY_NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarizing (this takes a few minutes)"
    xcrun notarytool submit "$dmg" --keychain-profile "$FINDY_NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
else
    echo "==> Not notarized: no FINDY_NOTARY_PROFILE"
fi

echo
echo "Version:       $version"
echo "Architectures: $(lipo -archs "$app/Contents/MacOS/Findy")"
echo "Identity:      $(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')"
echo "Disk image:    $dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '))"
echo "SHA-256:       $(shasum -a 256 "$dmg" | cut -d' ' -f1)"
