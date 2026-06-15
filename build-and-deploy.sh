#!/bin/bash
set -e

SERVER_IP="42.121.164.112"
SERVER_USER="Administrator"
SERVER_PASS="gh03vk9B!"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAR_PATH="$SCRIPT_DIR/happy-server-src.tar.gz"
MASTER_SECRET="b0b69f778d4464b50b13609af01b6b919fc19087ffd47a9317a87ed71c95e19c"
PUBLIC_URL="https://${SERVER_IP}:3006"

SSH="SSHPASS='${SERVER_PASS}' sshpass -e ssh -o StrictHostKeyChecking=no ${SERVER_USER}@${SERVER_IP}"
SCP="SSHPASS='${SERVER_PASS}' sshpass -e scp -o StrictHostKeyChecking=no"

echo "=== Happy Server: Build & Deploy to ${SERVER_IP} ==="

# ── 1. Build webapp ──────────────────────────────────────────────────────────
echo ""
echo "[1/6] Building webapp..."
cd "$SCRIPT_DIR"
node packages/happy-cli/scripts/bundle-webapp.cjs --out-dir packages/happy-server/webapp
echo "Webapp built."

# ── 2. Build standalone.mjs (bun, local Mac) ────────────────────────────────
echo ""
echo "[2/6] Building standalone.mjs..."
cd "$SCRIPT_DIR/packages/happy-server"
bun run build:runtime
echo "standalone.mjs: $(du -sh dist/standalone.mjs | cut -f1)"
cd "$SCRIPT_DIR"

# ── 3. Package source tarball ────────────────────────────────────────────────
echo ""
echo "[3/6] Packaging source..."
tar czf "$TAR_PATH" \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='tmp-build' \
  --exclude='*.tar.gz' \
  --exclude='.expo' \
  --exclude='.claude' \
  --exclude='packages/happy-app/ios' \
  --exclude='packages/happy-app/android' \
  -C "$SCRIPT_DIR" .
echo "Package: $(du -sh "$TAR_PATH" | cut -f1)"

# Package pre-generated Prisma client (WASM engine, platform-independent)
echo "Packaging Prisma client..."
tar czf /tmp/prisma-prebuilt.tar.gz \
  --exclude='libquery_engine-darwin-arm64.dylib.node' \
  --exclude='schema-engine-darwin-arm64' \
  -C "$SCRIPT_DIR/node_modules/.prisma" client
echo "Prisma client: $(du -sh /tmp/prisma-prebuilt.tar.gz | cut -f1)"

# ── 4. Generate TLS cert ─────────────────────────────────────────────────────
echo ""
echo "[4/6] Generating TLS certificate..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /tmp/happy-key.pem -out /tmp/happy-cert.pem \
  -subj "/CN=${SERVER_IP}" \
  -addext "subjectAltName=IP:${SERVER_IP}" 2>/dev/null
echo "Cert generated."

# ── 5. Upload ────────────────────────────────────────────────────────────────
echo ""
echo "[5/6] Uploading..."
SSHPASS="${SERVER_PASS}" sshpass -e scp -o StrictHostKeyChecking=no \
  "$TAR_PATH" \
  /tmp/prisma-prebuilt.tar.gz \
  /tmp/happy-key.pem \
  /tmp/happy-cert.pem \
  "${SERVER_USER}@${SERVER_IP}:C:/"
echo "Upload done."

# ── 6. Server setup ──────────────────────────────────────────────────────────
echo ""
echo "[6/6] Setting up server..."

# Extract source
SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "if exist C:\\happy-server rmdir /s /q C:\\happy-server && mkdir C:\\happy-server && tar -xzf C:\\happy-server-src.tar.gz -C C:\\happy-server && echo Extracted."

# Install pnpm if missing, then install deps
SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "where pnpm 2>nul || npm install -g pnpm && cd C:\\happy-server && set ELECTRON_SKIP_BINARY_DOWNLOAD=1 && set SKIP_HAPPY_WIRE_BUILD=1 && pnpm install --no-frozen-lockfile --ignore-scripts && echo pnpm install done."

# Restore pre-generated Prisma client
SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "if exist C:\\happy-server\\node_modules\\.prisma\\client rmdir /s /q C:\\happy-server\\node_modules\\.prisma\\client && mkdir C:\\happy-server\\node_modules\\.prisma\\client && tar -xzf C:\\prisma-prebuilt.tar.gz -C C:\\happy-server\\node_modules\\.prisma && echo Prisma client restored."

# Create data dir and run migrations
SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "mkdir C:\\happy-data 2>nul & cd C:\\happy-server\\packages\\happy-server && set NODE_ENV=production && set DATA_DIR=C:\\happy-data && set PGLITE_DIR=C:\\happy-data\\pglite && set HANDY_MASTER_SECRET=${MASTER_SECRET} && set PORT=3005 && \"C:\\Program Files\\nodejs\\node.exe\" dist\\standalone.mjs migrate && echo Migrations done."

# Upload https-proxy.mjs
cat > /tmp/https-proxy.mjs << 'PROXY_EOF'
import https from 'https';
import http from 'http';
import net from 'net';
import fs from 'fs';

const cert = fs.readFileSync('C:/happy-cert.pem');
const key = fs.readFileSync('C:/happy-key.pem');

const server = https.createServer({ cert, key }, (req, res) => {
  const options = {
    hostname: '127.0.0.1',
    port: 3005,
    path: req.url,
    method: req.method,
    headers: req.headers,
  };
  const proxy = http.request(options, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res, { end: true });
  });
  proxy.on('error', (e) => {
    console.error('Proxy error:', e.message);
    res.writeHead(502);
    res.end('Bad Gateway');
  });
  req.pipe(proxy, { end: true });
});

server.on('upgrade', (req, socket, head) => {
  const conn = net.connect(3005, '127.0.0.1', () => {
    let headerStr = `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      headerStr += `${req.rawHeaders[i]}: ${req.rawHeaders[i+1]}\r\n`;
    }
    headerStr += '\r\n';
    conn.write(headerStr);
    if (head && head.length > 0) conn.write(head);
    conn.pipe(socket);
    socket.pipe(conn);
  });
  conn.on('error', (e) => {
    console.error('WS proxy error:', e.message);
    socket.destroy();
  });
});

server.listen(3006, '0.0.0.0', () => {
  console.log('HTTPS proxy :3006 -> :3005');
});
PROXY_EOF

SSHPASS="${SERVER_PASS}" sshpass -e scp -o StrictHostKeyChecking=no \
  /tmp/https-proxy.mjs "${SERVER_USER}@${SERVER_IP}:C:/https-proxy.mjs"

# Create startup bat files
SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "( echo @echo off & echo set NODE_ENV=production & echo set DATA_DIR=C:/happy-data & echo set PGLITE_DIR=C:/happy-data/pglite & echo set HANDY_MASTER_SECRET=${MASTER_SECRET} & echo set PORT=3005 & echo \"C:\\Program Files\\nodejs\\node.exe\" C:\\happy-server\\packages\\happy-server\\dist\\standalone.mjs serve ) > C:\\start-happy.bat"

SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "( echo @echo off & echo \"C:\\Program Files\\nodejs\\node.exe\" C:\\https-proxy.mjs ) > C:\\start-proxy.bat"

# Kill old node processes and start fresh
SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "taskkill /f /im node.exe 2>nul & echo Killed old node processes."

# Start happy-server and proxy as background tasks
SSHPASS="${SERVER_PASS}" sshpass -e ssh -o StrictHostKeyChecking=no "${SERVER_USER}@${SERVER_IP}" \
  "powershell -command \"Start-Process -FilePath 'C:\\start-happy.bat' -WindowStyle Hidden; Start-Sleep -Seconds 3; Start-Process -FilePath 'C:\\start-proxy.bat' -WindowStyle Hidden; Write-Host 'Services started.'\""

echo ""
echo "=== Waiting for server to boot (8s)... ==="
sleep 8

# Quick health check
echo "Health check..."
curl -sk "https://${SERVER_IP}:3006/" -o /dev/null -w "HTTP %{http_code}\n" || echo "(not reachable yet)"

# Trust cert on this Mac
echo ""
echo "Trusting cert on Mac (may ask sudo password)..."
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/happy-cert.pem 2>/dev/null && echo "Cert trusted." || echo "Cert trust skipped (may already exist)."

# Update local settings.json
SETTINGS_DIR="$HOME/.aif4"
mkdir -p "$SETTINGS_DIR"
echo "{\"serverUrl\":\"${PUBLIC_URL}\",\"webappUrl\":\"${PUBLIC_URL}\"}" > "$SETTINGS_DIR/settings.json"
echo "Updated ~/.aif4/settings.json → ${PUBLIC_URL}"

echo ""
echo "=== Deploy complete! ==="
echo "  Webapp:  ${PUBLIC_URL}"
echo "  Server:  ${PUBLIC_URL}"
echo ""
echo "Next: run 'aif4' to connect."
