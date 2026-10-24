#!/bin/bash
# Cria, uma única vez, o certificado local "Redragon Battery Local" para assinar o app.
# Com a mesma assinatura em toda compilação, o macOS mantém a permissão de Monitoramento de Entrada.
set -euo pipefail

NAME="Redragon Battery Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "The certificate \"$NAME\" already exists in the keychain. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# /usr/bin/openssl é o LibreSSL do macOS; o .p12 dele é o formato que o "security import" aceita.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:temporaria

security import "$WORK/id.p12" -k "$KEYCHAIN" -P temporaria -T /usr/bin/codesign

echo "macOS will now ask for your password to trust the certificate for code signing."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "Certificate \"$NAME\" created. Next: bash build.sh"
