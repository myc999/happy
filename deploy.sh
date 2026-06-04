#!/bin/bash
set -e

IMAGE_TAR="/root/happy-claude/happy-server.tar.gz"
CONTAINER_NAME="happy-server"
PORT=3005
MASTER_SECRET="b0b69f778d4464b50b13609af01b6b919fc19087ffd47a9317a87ed71c95e19c"
PUBLIC_URL="http://154.26.180.195:3005"

echo "=== Happy Server Deploy ==="

# Load image
echo "[1/4] Loading Docker image..."
docker load < "$IMAGE_TAR"
echo "Done."

# Stop and remove existing container
echo "[2/4] Stopping existing container (if any)..."
docker stop "$CONTAINER_NAME" 2>/dev/null && docker rm "$CONTAINER_NAME" 2>/dev/null || true

# Run container
echo "[3/4] Starting container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -p ${PORT}:3005 \
  -e HANDY_MASTER_SECRET="$MASTER_SECRET" \
  -e PUBLIC_URL="$PUBLIC_URL" \
  -v happy-data:/data \
  --restart unless-stopped \
  happy-server:latest

# Verify
echo "[4/4] Verifying..."
sleep 3
if docker ps | grep -q "$CONTAINER_NAME"; then
  echo ""
  echo "=== Deploy successful ==="
  echo "Server running at: $PUBLIC_URL"
  echo "Container:         $(docker ps --filter name=$CONTAINER_NAME --format '{{.Status}}')"
else
  echo "ERROR: Container failed to start"
  docker logs "$CONTAINER_NAME" --tail 30
  exit 1
fi
