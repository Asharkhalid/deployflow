#!/bin/bash
set -e

APP_NAME="sample-api"
IMAGE_NAME=$1
if [ -z "$IMAGE_NAME" ]; then
    echo "Error: Image name must be provided (e.g., ghcr.io/username/repo/sample-api:latest)."
    exit 1
fi

BASE_DIR="/home/deployer/apps/$APP_NAME"
RELEASES_DIR="$BASE_DIR/releases"
SCRIPTS_DIR="$BASE_DIR/scripts"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
RELEASE_DIR="$RELEASES_DIR/$TIMESTAMP"

echo "Starting deployment of $IMAGE_NAME"

mkdir -p "$RELEASE_DIR"

# Generate a random port between 10000 and 60000
PORT=$(shuf -i 10000-60000 -n 1)
CONTAINER_NAME="${APP_NAME}_${TIMESTAMP}"

echo "Pulling image..."
docker pull "$IMAGE_NAME"

echo "Starting new candidate container $CONTAINER_NAME on port $PORT..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p 127.0.0.1:$PORT:8080 \
    -e ASPNETCORE_ENVIRONMENT=Production \
    "$IMAGE_NAME"

# Save metadata for later scripts
echo "$PORT" > "$RELEASE_DIR/.port"
echo "$CONTAINER_NAME" > "$RELEASE_DIR/.container"
echo "$IMAGE_NAME" > "$RELEASE_DIR/.image"

echo "Candidate release started. Verifying application health..."

# Pass the port to the health check
if bash "$SCRIPTS_DIR/health-check.sh" "$PORT"; then
    echo "Health check passed. Switching traffic..."
    bash "$SCRIPTS_DIR/switch-release.sh" "$RELEASE_DIR"
    bash "$SCRIPTS_DIR/cleanup.sh"
    echo "Deployment completed successfully!"
else
    echo "Health check failed. Candidate container did not become ready."
    echo "Cleaning up candidate container $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME" || true
    docker rm "$CONTAINER_NAME" || true
    rm -rf "$RELEASE_DIR"
    echo "Deployment aborted safely. Traffic remains untouched."
    exit 1
fi
