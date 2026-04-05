#!/bin/bash
set -e

# Encrypt sample.pdf → sample.dat using RSA+AES hybrid encryption (OpenSSL)
#
# Generates:
#   key.json   — RSA private key (PKCS#8 DER, base64) for browser decryption
#   sample.dat — encrypted PDF
#
# .dat format:
#   [2 bytes]  encrypted AES key length (big-endian)
#   [N bytes]  RSA-OAEP-SHA256 encrypted AES-256 key
#   [16 bytes] AES-CBC IV
#   [rest]     AES-256-CBC ciphertext (PKCS#7 padded)

echo "Generating RSA-2048 key pair..."
openssl genrsa -out _secret.pem 2048 2>/dev/null
openssl pkcs8 -topk8 -inform PEM -outform DER -in _secret.pem -out _key.der -nocrypt
openssl rsa -in _secret.pem -pubout -out _public.pem 2>/dev/null

echo "Generating AES-256 key and IV..."
openssl rand 32 > _aes_key.bin
openssl rand 16 > _aes_iv.bin

echo "Encrypting PDF with AES-256-CBC..."
openssl enc -aes-256-cbc -in sample.pdf -out _encrypted.bin \
  -K "$(xxd -p -c 64 _aes_key.bin)" \
  -iv "$(xxd -p -c 32 _aes_iv.bin)"

echo "Wrapping AES key with RSA-OAEP (SHA-256)..."
openssl pkeyutl -encrypt -pubin -inkey _public.pem \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -pkeyopt rsa_mgf1_md:sha256 \
  -in _aes_key.bin -out _encrypted_key.bin

echo "Packing sample.dat..."
KEY_LEN=$(wc -c < _encrypted_key.bin | tr -d ' ')
printf "\\x$(printf '%04x' "$KEY_LEN" | cut -c1-2)\\x$(printf '%04x' "$KEY_LEN" | cut -c3-4)" > sample.dat
cat _encrypted_key.bin >> sample.dat
cat _aes_iv.bin >> sample.dat
cat _encrypted.bin >> sample.dat

echo "Exporting key.json..."
printf '{"key":"%s"}' "$(base64 < _key.der | tr -d '\n')" > key.json

rm -f _secret.pem _public.pem _key.der _aes_key.bin _aes_iv.bin _encrypted.bin _encrypted_key.bin

echo "Done!"
echo "  sample.dat : $(wc -c < sample.dat | tr -d ' ') bytes"
echo "  key.json   : decryption key for the browser"
