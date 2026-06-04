#!/bin/bash
set -e

SERVER="root@154.26.180.195"
REMOTE_DIR="/root/happy-claude"
IMAGE_NAME="happy-server:latest"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAR_PATH="$SCRIPT_DIR/happy-server.tar.gz"
REPO_DIR="$SCRIPT_DIR"

echo "=== AIF4 Happy Server: Build & Deploy ==="

# Step 1: Build Docker image
echo ""
echo "[1/4] Building Docker image..."
cd "$REPO_DIR"
docker build -t "$IMAGE_NAME" -f Dockerfile .
echo "Build complete."

# Step 2: Save & compress
echo ""
echo "[2/4] Saving & compressing image..."
docker save "$IMAGE_NAME" | gzip > "$TAR_PATH"
SIZE=$(du -sh "$TAR_PATH" | cut -f1)
echo "Saved: $TAR_PATH ($SIZE)"

# Step 3: Upload to server
echo ""
echo "[3/4] Uploading to server (password required)..."
ssh "$SERVER" "mkdir -p $REMOTE_DIR"
scp "$TAR_PATH" "$SERVER:$REMOTE_DIR/happy-server.tar.gz"
scp "$SCRIPT_DIR/deploy.sh" "$SERVER:$REMOTE_DIR/deploy.sh"
echo "Upload complete."

# Step 4: Run deploy script on server
echo ""
echo "[4/4] Running deploy script on server..."
ssh "$SERVER" "bash $REMOTE_DIR/deploy.sh"

echo ""
echo "=== All done ==="
