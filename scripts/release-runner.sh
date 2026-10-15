#!/bin/bash
# Prepares a GitHub-hosted runner for .github/workflows/release.yml and its rehearsal, and cleans up after them.
# It replaces the user's keychain search list, so it runs on such a runner and nowhere else.
# Usage: release-runner.sh tools | identity PATTERN | keys | cleanup
set -euo pipefail

xcode=27.0
xcodegen=2.46.0
xcodegen_sha256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
keychain=$RUNNER_TEMP/release.keychain-db
die() { echo "error: $*" >&2; exit 1; }

case ${1:-} in
tools)
    developer=/Applications/Xcode_$xcode.app/Contents/Developer
    [ -d "$developer" ] || die "this runner has no Xcode $xcode: $(echo /Applications/Xcode*.app)"
    echo "DEVELOPER_DIR=$developer" >>"$GITHUB_ENV"
    DEVELOPER_DIR=$developer xcodebuild -version
    curl -fsSL --retry 3 -o "$RUNNER_TEMP/xcodegen.zip" \
        "https://github.com/yonaskolb/XcodeGen/releases/download/$xcodegen/xcodegen.zip"
    echo "$xcodegen_sha256  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -
    ditto -x -k "$RUNNER_TEMP/xcodegen.zip" "$RUNNER_TEMP"
    echo "$RUNNER_TEMP/xcodegen/bin" >>"$GITHUB_PATH"
    "$RUNNER_TEMP/xcodegen/bin/xcodegen" --version
    ;;
identity)
    pattern=${2:?usage: release-runner.sh identity PATTERN}
    [ -n "${P12:-}" ] || die "no certificate: the release environment has no DEVELOPER_ID_P12 secret"
    password=$(openssl rand -hex 24)
    security create-keychain -p "$password" "$keychain"
    # Locks only after six hours, the longest a job runs.
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$password" "$keychain"
    (umask 077 && printf '%s' "$P12" | base64 --decode >"$RUNNER_TEMP/release.p12")
    security import "$RUNNER_TEMP/release.p12" -k "$keychain" -f pkcs12 -P "${P12_PASSWORD:-}" \
        -T /usr/bin/codesign >/dev/null
    rm -f "$RUNNER_TEMP/release.p12"
    # Lets codesign use the key without the prompt a runner could never answer.
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
    security list-keychains -d user -s "$keychain"
    found=$(security find-identity -v -p codesigning "$keychain")
    [ "$(grep -cE "\"$pattern\"" <<<"$found")" = 1 ] ||
        die "no one valid identity matches '$pattern', so the build would not sign (is Apple's intermediate" \
            "missing?): $(security find-identity -p codesigning "$keychain")"
    grep -E "\"$pattern\"" <<<"$found"
    ;;
keys)
    [ -n "${SPARKLE_PRIVATE_KEY:-}" ] || die "the release environment has no SPARKLE_PRIVATE_KEY secret"
    (umask 077 && printf '%s\n' "$SPARKLE_PRIVATE_KEY" >"$RUNNER_TEMP/sparkle-key")
    echo "SPARKLE_KEY_FILE=$RUNNER_TEMP/sparkle-key" >>"$GITHUB_ENV"
    if [ -n "${NOTARY_API_KEY:-}" ]; then
        (umask 077 && printf '%s\n' "$NOTARY_API_KEY" >"$RUNNER_TEMP/notary.p8")
        echo "NOTARY_KEY=$RUNNER_TEMP/notary.p8" >>"$GITHUB_ENV"
    fi
    ;;
cleanup)
    [ ! -e "$keychain" ] || security delete-keychain "$keychain"
    rm -f "$RUNNER_TEMP/release.p12" "$RUNNER_TEMP/sparkle-key" "$RUNNER_TEMP/notary.p8"
    ;;
*) die "usage: release-runner.sh tools | identity PATTERN | keys | cleanup" ;;
esac
