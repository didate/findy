# Releasing

## 1. Build the disk image

```bash
scripts/release.sh
```

It builds a universal app (Apple Silicon and Intel), packages it in `build/release/Findy-<version>.dmg` and prints the SHA-256 of the image.

The version comes from `MARKETING_VERSION` in `project.yml`. Bump it, and `CURRENT_PROJECT_VERSION`, before building a new release.

## 2. Sign

macOS remembers the permissions it granted to an app (Desktop, Documents, Downloads, external and network volumes) by the app's signing identity.

- **Ad hoc** (no identity, the default): the identity is the hash of the binary. Every new build is a stranger, and people are asked for the same permissions again after each update.
- **Self-signed certificate**: the identity is the certificate, so it stays the same from one version to the next. This is how releases are signed. macOS still blocks the first launch of a downloaded copy.
- **Developer ID and notarization** (needs an Apple Developer account): the same, and the first launch is no longer blocked.

### Self-signed certificate

The releases are signed with a certificate named `Findy Self-Signed`, whose private key lives in the maintainer's login keychain. Its SHA-1 fingerprint is `478DAB4F0B549A901C5548151ECC0356AE08E821`; it shows in the identity that `scripts/release.sh` prints.

```bash
FINDY_SIGN_IDENTITY="Findy Self-Signed" scripts/release.sh
```

**Back up the key** (Keychain Access > My Certificates > Findy Self-Signed > Export). A release signed with another certificate is a different app for macOS: every user is asked for the permissions once more. The certificate expires on 22 November 2036.

To create such a certificate on another Mac: Keychain Access > Certificate Assistant > Create a Certificate, with Identity Type "Self-Signed Root" and Certificate Type "Code Signing".

### Developer ID

With a Developer ID certificate in the keychain:

```bash
xcrun notarytool store-credentials findy   # once
FINDY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
FINDY_NOTARY_PROFILE=findy \
scripts/release.sh
```

Moving from the self-signed certificate to a Developer ID changes the identity one last time.

## 3. Publish

```bash
git tag v<version>
git push origin v<version>
gh release create v<version> build/release/Findy-<version>.dmg --title "Findy <version>" --notes-file <notes>
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
