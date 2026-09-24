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

# Pull before creating the release folder, so a failed pull leaves nothing behind
echo "Pulling image..."
if ! docker pull "$IMAGE_NAME"; then
    echo "Image pull failed. No release created. Traffic remains untouched."
    exit 1
fi

mkdir -p "$RELEASE_DIR"
echo "$IMAGE_NAME" > "$RELEASE_DIR/.image"

# Starts the candidate on a free port and records .port, .container and .env
if ! bash "$SCRIPTS_DIR/start-container.sh" "$RELEASE_DIR"; then
    echo "Candidate container failed to start. Traffic remains untouched."
    rm -rf "$RELEASE_DIR"
    exit 1
fi
PORT=$(cat "$RELEASE_DIR/.port")
CONTAINER_NAME=$(cat "$RELEASE_DIR/.container")

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
