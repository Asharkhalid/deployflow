#!/bin/bash
set -e

APP_NAME="sample-api"
BASE_DIR="/home/deployer/apps/$APP_NAME"
RELEASES_DIR="$BASE_DIR/releases"
CURRENT_SYMLINK="$BASE_DIR/current"
NGINX_UPSTREAM_FILE="/etc/nginx/conf.d/${APP_NAME}_upstream.conf"

echo "Initiating manual rollback procedure..."

cd "$RELEASES_DIR" || exit 1

# List all directories, sort them chronologically
RELEASES=( $(ls -d 20* | sort) )
COUNT=${#RELEASES[@]}

if [ "$COUNT" -lt 2 ]; then
    echo "Not enough releases to perform a rollback. Found $COUNT releases."
    exit 1
fi

PREVIOUS_RELEASE_DIR="$RELEASES_DIR/${RELEASES[$COUNT-2]}"
CURRENT_RELEASE_DIR="$RELEASES_DIR/${RELEASES[$COUNT-1]}"

echo "Rolling back from ${RELEASES[$COUNT-1]} to ${RELEASES[$COUNT-2]}"

PREV_PORT=$(cat "$PREVIOUS_RELEASE_DIR/.port")
PREV_CONTAINER=$(cat "$PREVIOUS_RELEASE_DIR/.container")

# 1. Restart previous container if it was stopped
if [ "$(docker ps -q -f name=$PREV_CONTAINER)" == "" ]; then
    echo "Restarting previous container $PREV_CONTAINER..."
    if docker ps -aq -f name=$PREV_CONTAINER | grep -q .; then
        docker start "$PREV_CONTAINER"
    else
        echo "Error: Previous container does not exist. Cannot rollback."
        exit 1
    fi
fi

# 2. Ensure the previous container is healthy
echo "Awaiting health check on previous container (port $PREV_PORT)..."
if bash "$BASE_DIR/scripts/health-check.sh" "$PREV_PORT"; then
    echo "Previous container is healthy."
else
    echo "Previous container is NOT healthy. Rollback aborted."
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

# 5. Stop and remove the faulty current container
CURRENT_CONTAINER=$(cat "$CURRENT_RELEASE_DIR/.container")
echo "Cleaning up faulty container $CURRENT_CONTAINER..."
docker stop "$CURRENT_CONTAINER" || true
docker rm "$CURRENT_CONTAINER" || true

# Clean up faulty release directory
rm -rf "$CURRENT_RELEASE_DIR"

echo "Rollback successfully completed."
