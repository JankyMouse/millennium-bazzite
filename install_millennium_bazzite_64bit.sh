#!/usr/bin/env bash
set -euo pipefail

sudo -k
sudo -v

REPO="SteamClientHomebrew/Millennium"
RELEASE_API="https://api.github.com/repos/SteamClientHomebrew/Millennium/releases/latest"
EXT_DIR="/var/lib/extensions/millennium"
DEST="${EXT_DIR}/usr/lib/millennium"
STEAM="${STEAM_PATH:-$HOME/.local/share/Steam}"

for cmd in curl jq tar sudo grep sha256sum cp chmod mv mktemp rm mkdir systemctl systemd-sysext tee; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd not installed" >&2; exit 1; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/millennium-bazzite.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "checking latest Millennium release..."
RELEASE="$(curl -fsSL "$RELEASE_API")"
MILLENNIUM_TAG="$(jq -er '.tag_name | select(type == "string" and length > 0)' <<< "$RELEASE")"
VERSION="${MILLENNIUM_TAG#v}"
ARCHIVE="millennium-v${VERSION}-linux-x86_64.tar.gz"
CHECKSUM_ASSET="millennium-v${VERSION}-linux-x86_64.sha256"
ARCHIVE_URL="$(jq -er --arg name "$ARCHIVE" \
  '.assets[] | select(.name == $name) | .browser_download_url' <<< "$RELEASE")"
CHECKSUM_URL="$(jq -er --arg name "$CHECKSUM_ASSET" \
  '.assets[] | select(.name == $name) | .browser_download_url' <<< "$RELEASE")"

echo "downloading official Millennium ${MILLENNIUM_TAG}..."
curl -fL --progress-bar -o "$WORK/millennium.tar.gz" "$ARCHIVE_URL"
curl -fsSL -o "$WORK/millennium.sha256" "$CHECKSUM_URL"

read -r UPSTREAM_SHA _ < "$WORK/millennium.sha256"
if [[ ! "$UPSTREAM_SHA" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "error: invalid Millennium release checksum file" >&2
  exit 1
fi
printf '%s  %s\n' "$UPSTREAM_SHA" "$WORK/millennium.tar.gz" | sha256sum -c --status \
  || { echo "error: Millennium release checksum mismatch" >&2; exit 1; }
echo "checksum ok"

tar -xzf "$WORK/millennium.tar.gz" -C "$WORK"
SRC="$WORK/usr/lib/millennium"
[[ -d "$SRC" ]] || { echo "error: unexpected tarball layout (missing usr/lib/millennium)" >&2; exit 1; }

echo "closing Steam before updating libraries..."
killall -9 steam 2>/dev/null || true
sleep 1

echo "installing Millennium ${MILLENNIUM_TAG} to ${DEST}..."
sudo rm -rf "$DEST"
sudo mkdir -p "$DEST"
sudo cp -f "$SRC"/* "$DEST/"
for bin in libmillennium_pvs64 libmillennium_luavm_x64; do
  if [[ -f "$DEST/$bin" ]]; then
    sudo chmod +x "$DEST/$bin"
  fi
done

echo "syncing Bazzite OS release metadata and systemd-sysext overlay..."
sudo mkdir -p "${EXT_DIR}/usr/lib/extension-release.d"
grep -E '^(ID|VERSION_ID)=' /etc/os-release \
  | sudo tee "${EXT_DIR}/usr/lib/extension-release.d/extension-release.millennium" >/dev/null

sudo tee /etc/systemd/system/millennium-sysext-sync.service >/dev/null <<'EOF'
[Unit]
Description=Sync Millennium systemd-sysext OS release metadata
DefaultDependencies=no
After=local-fs.target
Before=systemd-sysext.service
ConditionPathExists=/var/lib/extensions/millennium/usr/lib/millennium

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'mkdir -p /var/lib/extensions/millennium/usr/lib/extension-release.d && grep -E "^(ID|VERSION_ID)=" /etc/os-release > /var/lib/extensions/millennium/usr/lib/extension-release.d/extension-release.millennium'

[Install]
WantedBy=sysinit.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now millennium-sysext-sync.service >/dev/null 2>&1 || true
sudo systemctl enable --now systemd-sysext >/dev/null 2>&1 || true
sudo systemd-sysext unmerge >/dev/null 2>&1 || true
sudo systemd-sysext merge

if [[ ! -f "/usr/lib/millennium/libmillennium_x64.so" ]]; then
  echo "error: /usr/lib/millennium/libmillennium_x64.so did not appear after systemd-sysext merge" >&2
  exit 1
fi

copy_into_steam() {
  local source="$1"
  local target="$2"
  local temporary="${target}.tmp.$$"

  cp "$source" "$temporary"
  chmod --reference="$source" "$temporary"
  mv -fT "$temporary" "$target"
}

echo "installing 64-bit Millennium bootstrap libraries into Steam..."
mkdir -p "$STEAM/steamrt64"
copy_into_steam "/usr/lib/millennium/libmillennium_bootstrap_x64.so" "$STEAM/steamrt64/libXtst.so.6"
copy_into_steam "/usr/lib/millennium/libmillennium_hhx64.so" "$STEAM/steamrt64/libmillennium_hhx64.so"

rm -f "$STEAM/ubuntu12_32/libXtst.so.6" \
      "$STEAM/ubuntu12_64/libXtst.so.6" \
      "$STEAM/ubuntu12_64/libmillennium_hhx64.so" \
      "$STEAM/.cef-enable-remote-debugging"

rm -rf "$STEAM/config/htmlcache/Default/Cache" "$STEAM/config/htmlcache/Default/Code Cache"

echo "done; Millennium ${MILLENNIUM_TAG} installed. Start Steam to apply."
