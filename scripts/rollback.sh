#!/bin/bash
set -e

APP_NAME="sample-api"
BASE_DIR="/home/deployer/apps/$APP_NAME"
RELEASES_DIR="$BASE_DIR/releases"
CURRENT_SYMLINK="$BASE_DIR/current"
NGINX_UPSTREAM_FILE="/etc/nginx/conf.d/${APP_NAME}_upstream.conf"
DRAIN_SECONDS=${DRAIN_SECONDS:-10}

echo "Initiating manual rollback procedure..."

cd "$RELEASES_DIR" || exit 1

# The live release is whatever 'current' points at, not the newest directory
if [ ! -L "$CURRENT_SYMLINK" ]; then
    echo "Error: $CURRENT_SYMLINK does not exist. Nothing to roll back from."
    exit 1
fi
CURRENT_RELEASE_DIR=$(readlink -f "$CURRENT_SYMLINK")
CURRENT_RELEASE=$(basename "$CURRENT_RELEASE_DIR")

# Rollback target is the release immediately before the live one
RELEASES=( $(ls -d 20* | sort) )
PREVIOUS_RELEASE=""
for RELEASE in "${RELEASES[@]}"; do
    if [ "$RELEASE" == "$CURRENT_RELEASE" ]; then
        break
    fi
    # Skip incomplete releases that have no image to restore
    if [ -f "$RELEASES_DIR/$RELEASE/.image" ]; then
        PREVIOUS_RELEASE="$RELEASE"
    fi
done

if [ -z "$PREVIOUS_RELEASE" ]; then
    echo "No release older than the live one ($CURRENT_RELEASE). Cannot rollback."
    exit 1
fi

PREVIOUS_RELEASE_DIR="$RELEASES_DIR/$PREVIOUS_RELEASE"

echo "Rolling back from $CURRENT_RELEASE to $PREVIOUS_RELEASE"

PREV_CONTAINER=$(cat "$PREVIOUS_RELEASE_DIR/.container" 2>/dev/null || true)

# 1. Bring the previous release back: restart its stopped container, or recreate
#    it from the recorded image if the container is gone or cannot start
if [ -n "$PREV_CONTAINER" ] && docker ps -q -f name="^${PREV_CONTAINER}$" | grep -q .; then
    echo "Previous container $PREV_CONTAINER is already running."
elif [ -n "$PREV_CONTAINER" ] && docker ps -aq -f name="^${PREV_CONTAINER}$" | grep -q . \
     && docker start "$PREV_CONTAINER"; then
    echo "Restarted previous container $PREV_CONTAINER."
else
    echo "Previous container unavailable. Recreating it from $(cat "$PREVIOUS_RELEASE_DIR/.image")..."
    if ! bash "$BASE_DIR/scripts/start-container.sh" "$PREVIOUS_RELEASE_DIR"; then
        echo "Error: Could not recreate the previous release. Rollback aborted."
        exit 1
    fi
    PREV_CONTAINER=$(cat "$PREVIOUS_RELEASE_DIR/.container")
fi
PREV_PORT=$(cat "$PREVIOUS_RELEASE_DIR/.port")

# 2. Ensure the previous container is healthy
echo "Awaiting health check on previous container (port $PREV_PORT)..."
if bash "$BASE_DIR/scripts/health-check.sh" "$PREV_PORT"; then
    echo "Previous container is healthy."
else
    echo "Previous container is NOT healthy. Rollback aborted."
    docker stop "$PREV_CONTAINER" || true
    exit 1
fi

# 3. Switch traffic back in Nginx
echo "upstream deployflow_upstream { server 127.0.0.1:$PREV_PORT; }" | sudo tee "$NGINX_UPSTREAM_FILE" > /dev/null
if sudo nginx -t; then
    sudo nginx -s reload
    echo "Traffic restored to previous release."
else
    echo "Nginx config failed during rollback."
    exit 1
fi

# 4. Update symlink
ln -sfn "$PREVIOUS_RELEASE_DIR" "$CURRENT_SYMLINK"

# 5. Let in-flight requests finish, then remove the faulty container
CURRENT_CONTAINER=$(cat "$CURRENT_RELEASE_DIR/.container")
echo "Draining in-flight requests for ${DRAIN_SECONDS}s..."
sleep "$DRAIN_SECONDS"
echo "Cleaning up faulty container $CURRENT_CONTAINER..."
docker stop "$CURRENT_CONTAINER" || true
docker rm "$CURRENT_CONTAINER" || true

# Clean up faulty release directory
rm -rf "$CURRENT_RELEASE_DIR"

echo "Rollback successfully completed."
