#!/bin/sh
# Publishes a release that copies of Notch Island find and install themselves.
#
#   ./release.sh --setup              once: makes your update signing key (kept in your login keychain) and the
#                                     certificate every release is signed with
#   ./release.sh 0.2.0 [NOTES.md]     builds, signs and zips the app, tags the commit, and creates the GitHub
#                                     release (notes from the file, or generated from the commits)
set -e
cd "$(dirname "$0")"
KEYNAME="Notch Island update key"
CERT="Notch Island Release"

if [ "$1" = --setup ]; then
    if security find-generic-password -s "$KEYNAME" >/dev/null 2>&1; then
        echo "You already have an update key."
    else
        swift build -c release
        KEYS=$("$(swift build -c release --show-bin-path)/NotchIsland" --new-update-key)
        SECRET=$(echo "$KEYS" | sed -n 1p)
        PUBLIC=$(echo "$KEYS" | sed -n 2p)
        security add-generic-password -s "$KEYNAME" -a "$USER" -w "$SECRET"
        /usr/libexec/PlistBuddy -c "Set :NIUpdateKey $PUBLIC" Resources/Info.plist 2>/dev/null ||
            /usr/libexec/PlistBuddy -c "Add :NIUpdateKey string $PUBLIC" Resources/Info.plist
        echo "Made your update key. The secret half is in your login keychain as \"$KEYNAME\"."
        echo "Back it up somewhere safe; without it, existing copies won't accept your updates:"
        echo "    security find-generic-password -s \"$KEYNAME\" -w"
        echo "The public half is now in Resources/Info.plist. Commit it."
    fi
    if security find-identity -v -p codesigning | grep -q "\"$CERT\""; then
        echo "You already have the \"$CERT\" certificate."
    else
        T=$(mktemp -d)
        trap 'rm -rf "$T"' EXIT
        cat > "$T/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
        # The system's openssl, so `security import` can read the bundle
        /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/cert.cnf" -keyout "$T/key.pem" -out "$T/cert.pem" 2>/dev/null
        /usr/bin/openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -out "$T/id.p12" -passout pass:notch
        security import "$T/id.p12" -k ~/Library/Keychains/login.keychain-db -P notch -T /usr/bin/codesign
        echo "macOS will ask for your password to trust it for signing code:"
        security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "$T/cert.pem"
        echo "Made the \"$CERT\" certificate."
    fi
    exit 0
fi

V="$1"
NOTES="$2"
case "$V" in
    "" | *[!0-9.]*) echo "Usage: ./release.sh --setup  or  ./release.sh VERSION [NOTES.md], with VERSION like 0.2.0"; exit 1 ;;
esac
git diff --quiet && git diff --cached --quiet || { echo "Commit your changes first."; exit 1; }
git rev-parse -q --verify "refs/tags/v$V" >/dev/null && { echo "v$V is already released."; exit 1; }
SECRET=$(security find-generic-password -s "$KEYNAME" -w 2>/dev/null) || { echo "No update key yet. Run ./release.sh --setup first."; exit 1; }
/usr/libexec/PlistBuddy -c "Print :NIUpdateKey" Resources/Info.plist >/dev/null 2>&1 || { echo "Info.plist has no NIUpdateKey. Run ./release.sh --setup."; exit 1; }
command -v gh >/dev/null || { echo "Needs the GitHub CLI: brew install gh"; exit 1; }

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" -c "Set :CFBundleVersion $V" Resources/Info.plist
./build.sh
ZIP="build/NotchIsland-$V.zip"
rm -f "$ZIP" "$ZIP.sig"
ditto -c -k --keepParent build/NotchIsland.app "$ZIP"
printf '%s\n' "$SECRET" | build/NotchIsland.app/Contents/MacOS/NotchIsland --sign-update "$ZIP" > "$ZIP.sig"

git commit -qam "Release $V"
git tag "v$V"
git push -q origin HEAD "v$V"
if [ -n "$NOTES" ]; then set -- --notes-file "$NOTES"; else set -- --generate-notes; fi
gh release create "v$V" "$ZIP" "$ZIP.sig" --title "Notch Island $V" "$@"
echo "Released $V. Copies of Notch Island will offer it within a day, or now from Check for Updates."
