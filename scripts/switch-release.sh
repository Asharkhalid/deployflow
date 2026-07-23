#!/bin/bash
set -e

NEW_RELEASE_DIR=$1
if [ -z "$NEW_RELEASE_DIR" ]; then
    echo "Error: Release directory required."
    exit 1
fi

APP_NAME="sample-api"
BASE_DIR="/home/deployer/apps/$APP_NAME"
CURRENT_SYMLINK="$BASE_DIR/current"
NGINX_UPSTREAM_FILE="/etc/nginx/conf.d/${APP_NAME}_upstream.conf"

NEW_PORT=$(cat "$NEW_RELEASE_DIR/.port")
NEW_CONTAINER=$(cat "$NEW_RELEASE_DIR/.container")

echo "Switching proxy traffic to port $NEW_PORT..."

# Generate new upstream config dynamically
echo "upstream deployflow_upstream { server 127.0.0.1:$NEW_PORT; }" | sudo tee "$NGINX_UPSTREAM_FILE" > /dev/null

# Test nginx config before reloading
if sudo nginx -t; then
    echo "Nginx config test passed. Reloading Nginx gracefully..."
    sudo nginx -s reload
else
    echo "Nginx config test failed! Traffic switch aborted."
    exit 1
fi

# Determine the old container to stop it
if [ -L "$CURRENT_SYMLINK" ]; then
    OLD_RELEASE_DIR=$(readlink -f "$CURRENT_SYMLINK")
    if [ -f "$OLD_RELEASE_DIR/.container" ]; then
        OLD_CONTAINER=$(cat "$OLD_RELEASE_DIR/.container")
    fi
fi

# Atomic update of the symlink
ln -sfn "$NEW_RELEASE_DIR" "$CURRENT_SYMLINK"
echo "Symlink 'current' updated to $NEW_RELEASE_DIR"

# Gracefully stop and remove the old container
if [ -n "$OLD_CONTAINER" ] && [ "$OLD_CONTAINER" != "$NEW_CONTAINER" ]; then
    echo "Stopping previous container: $OLD_CONTAINER"
    docker stop "$OLD_CONTAINER" || true
    docker rm "$OLD_CONTAINER" || true
fi

echo "Traffic switch successful!"
