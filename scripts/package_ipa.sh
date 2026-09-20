#!/bin/bash
# Build REScout and pack a TrollStore-friendly IPA (ldid entitlements).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="$ROOT/build"
ARCHIVE_DIR="$DERIVED/Build/Products"
CONFIG="Release"
SDK="iphoneos"
ENTITLEMENTS="$ROOT/REScout/REScout.entitlements"
TUNNEL_ENTITLEMENTS="$ROOT/PacketTunnel/PacketTunnel.entitlements"
LDID_BIN="$(command -v ldid || command -v ldid2 || true)"

echo "[1/5] Generate Xcode project (xcodegen)"
xcodegen generate

echo "[2/5] Clean derived data folder"
rm -rf "$DERIVED"
mkdir -p "$DERIVED"

echo "[3/5] xcodebuild ($CONFIG / $SDK), Apple signing disabled"
xcodebuild \
  -project REScout.xcodeproj \
  -scheme REScout \
  -configuration "$CONFIG" \
  -sdk "$SDK" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP="$ARCHIVE_DIR/$CONFIG-$SDK/REScout.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: app not found at $APP" >&2
  exit 1
fi

echo "[4/5] Embed entitlements with ldid"
if [[ -z "$LDID_BIN" ]]; then
  echo "ERROR: ldid/ldid2 not found. brew install ldid" >&2
  exit 1
fi
if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "ERROR: missing $ENTITLEMENTS" >&2
  exit 1
fi
cp "$ENTITLEMENTS" "$APP/REScout.entitlements"
"$LDID_BIN" -S"$ENTITLEMENTS" "$APP/REScout"
"$LDID_BIN" -S"$ENTITLEMENTS" "$APP"

APPEX="$APP/PlugIns/PacketTunnel.appex"
if [[ -d "$APPEX" ]]; then
  if [[ ! -f "$TUNNEL_ENTITLEMENTS" ]]; then
    echo "ERROR: missing $TUNNEL_ENTITLEMENTS" >&2
    exit 1
  fi
  cp "$TUNNEL_ENTITLEMENTS" "$APPEX/PacketTunnel.entitlements"
  if [[ -f "$APPEX/PacketTunnel" ]]; then
    "$LDID_BIN" -S"$TUNNEL_ENTITLEMENTS" "$APPEX/PacketTunnel"
  fi
  "$LDID_BIN" -S"$TUNNEL_ENTITLEMENTS" "$APPEX"
  echo "Signed PacketTunnel.appex"
else
  echo "WARNING: PacketTunnel.appex not embedded at $APPEX" >&2
fi

echo "[5/5] Package IPA"
STAGE="$DERIVED/ipa_stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
(
  cd "$STAGE"
  rm -f "$ROOT/REScout.ipa"
  zip -qr "$ROOT/REScout.ipa" Payload
)

echo "OK: $ROOT/REScout.ipa"
ls -lh "$ROOT/REScout.ipa"
echo "Entitlements check:"
"$LDID_BIN" -e "$APP/REScout" | head -40
