#!/bin/bash
set -e

# Starts (or recreates) the container for a release directory from its recorded image.
# Used by deploy.sh for new releases and by rollback.sh when a retained release's
# container is gone or can no longer bind its old port.
# Writes .port and .container into the release directory.

RELEASE_DIR=$1
if [ -z "$RELEASE_DIR" ] || [ ! -f "$RELEASE_DIR/.image" ]; then
    echo "Error: Release directory with an .image file required."
    exit 1
fi

APP_NAME="sample-api"
RELEASES_DIR=$(dirname "$RELEASE_DIR")
RELEASE=$(basename "$RELEASE_DIR")
IMAGE_NAME=$(cat "$RELEASE_DIR/.image")
CONTAINER_NAME="${APP_NAME}_${RELEASE}"

# Runtime settings are recorded once so a recreated container matches the original.
# Releases deployed before this file existed get one derived from the image tag.
if [ ! -f "$RELEASE_DIR/.env" ]; then
    TAG=${IMAGE_NAME##*:}
    # The folder name is the local deploy time (YYYYMMDD-HHMMSS); fall back to now
    BUILD_DATE=$(date -u -d "${RELEASE:0:8} ${RELEASE:9:2}:${RELEASE:11:2}:${RELEASE:13:2}" \
        +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    {
        echo "ASPNETCORE_ENVIRONMENT=Production"
        echo "COMMIT_SHA=${TAG#sha-}"
        echo "APP_VERSION=1.0.${RELEASE}"
        echo "BUILD_DATE=$BUILD_DATE"
    } > "$RELEASE_DIR/.env"
fi

# Pick a port that nothing is listening on and no retained release has recorded,
# so a stopped container can always get its old port back on rollback
RESERVED_PORTS=$(cat "$RELEASES_DIR"/*/.port 2>/dev/null || true)
while :; do
    PORT=$(shuf -i 10000-60000 -n 1)
    if ! echo "$RESERVED_PORTS" | grep -qx "$PORT" && \
       ! ss -ltn | awk '{print $4}' | grep -q ":$PORT$"; then
        break
    fi
done

# Replace any leftover container with the same name
docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true

echo "Starting container $CONTAINER_NAME from $IMAGE_NAME on port $PORT..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p 127.0.0.1:$PORT:8080 \
    --env-file "$RELEASE_DIR/.env" \
    "$IMAGE_NAME"

echo "$PORT" > "$RELEASE_DIR/.port"
echo "$CONTAINER_NAME" > "$RELEASE_DIR/.container"
