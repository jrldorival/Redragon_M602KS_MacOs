#!/bin/bash
# Compila o main.swift e monta o RedragonBattery.app ao lado deste script.
set -euo pipefail
cd "$(dirname "$0")"

APP="RedragonBattery.app"
# Versão do app (versionamento semântico): única fonte é o arquivo VERSION.
VERSION="$(tr -d '[:space:]' < VERSION)"

# Monta e assina numa pasta temporária: na pasta do projeto o codesign recusou os arquivos por causa de atributos
# estendidos ("resource fork, Finder information, or similar detritus not allowed").
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BUNDLE="$WORK/$APP"
mkdir -p "$BUNDLE/Contents/MacOS"

swiftc -O main.swift Settings.swift Buttons.swift -o "$BUNDLE/Contents/MacOS/RedragonBattery" -framework AppKit -framework IOKit

# Ícone do app: o icon.png (1024x1024) vira AppIcon.icns em todos os tamanhos que o macOS usa.
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET" "$BUNDLE/Contents/Resources"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z $((SIZE * 2)) $((SIZE * 2)) icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>RedragonBattery</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.redragon-battery</string>
    <key>CFBundleName</key>
    <string>Redragon Battery</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
</dict>
</plist>
PLIST

# Com o certificado do criar-certificado.sh a assinatura é a mesma em toda compilação e a permissão de
# Monitoramento de Entrada continua valendo; sem ele, a assinatura ad-hoc muda a cada compilação.
# Garante que nada copiado da pasta do projeto (o icon.png, via sips) leve atributos estendidos para o bundle.
xattr -cr "$BUNDLE"
IDENTITY="Redragon Battery Local"
IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
if grep -q "\"$IDENTITY\"" <<< "$IDENTITIES"; then
    codesign --force --sign "$IDENTITY" "$BUNDLE"
else
    echo "Aviso: certificado \"$IDENTITY\" não encontrado (rode: bash criar-certificado.sh)."
    echo "Assinando ad-hoc: a permissão de Monitoramento de Entrada terá de ser dada de novo a cada compilação."
    codesign --force --sign - "$BUNDLE"
fi

rm -rf "$APP"
mv "$BUNDLE" "$APP"

echo "Pronto: $(pwd)/$APP (versão $VERSION)"
codesign -dv "$APP" 2>&1 | grep -E "^(Authority|Signature)=" || true
