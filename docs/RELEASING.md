# Releasing

## 1. Build the disk image

```bash
scripts/release.sh
```

It builds a universal app (Apple Silicon and Intel), packages it in `build/release/Findy-<version>.dmg` and prints the SHA-256 of the image.

The version comes from `MARKETING_VERSION` in `project.yml`. Bump it, and `CURRENT_PROJECT_VERSION`, before building a new release.

## 2. Sign and notarize (needs an Apple Developer account)

Without a Developer ID the app is signed ad hoc. It runs, but macOS blocks it the first time for people who downloaded it: they have to allow it in System Settings > Privacy & Security.

With a Developer ID certificate in the keychain:

```bash
xcrun notarytool store-credentials findy   # once
FINDY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
FINDY_NOTARY_PROFILE=findy \
scripts/release.sh
```

## 3. Publish

```bash
git tag v0.1.0
git push origin v0.1.0
gh release create v0.1.0 build/release/Findy-0.1.0.dmg --title "Findy 0.1.0" --notes-file <notes>
```

Upload the exact image whose SHA-256 goes in the cask: two builds of the same sources do not produce the same bytes.

## 4. Update the Homebrew cask

Copy `packaging/homebrew/findy.rb` to `Casks/findy.rb` in the tap repository (`didate/homebrew-tap`) with the new `version` and `sha256`. People then install with:

```bash
brew tap didate/tap
brew trust didate/tap
brew install --cask findy
```

`brew trust` exists in recent versions of Homebrew, which refuse casks from a third-party tap until it is trusted. If your Homebrew does not know the command, skip that line.

The official `homebrew/cask` repository only accepts notarized apps, hence the tap.
