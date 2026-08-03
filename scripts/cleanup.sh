#!/bin/bash
set -e

APP_NAME="sample-api"
BASE_DIR="/home/deployer/apps/$APP_NAME"
RELEASES_DIR="$BASE_DIR/releases"
KEEP_RELEASES=3

echo "Starting cleanup of old releases..."

cd "$RELEASES_DIR" || exit 1

# Find releases and count them
RELEASES=( $(ls -d 20* | sort) )
COUNT=${#RELEASES[@]}

if [ "$COUNT" -gt "$KEEP_RELEASES" ]; then
    REMOVE_COUNT=$((COUNT - KEEP_RELEASES))
    echo "Found $COUNT releases. Limit is $KEEP_RELEASES. Removing $REMOVE_COUNT oldest releases..."
    
    for (( i=0; i<REMOVE_COUNT; i++ )); do
        DIR_TO_REMOVE="${RELEASES[$i]}"
        echo "Removing release directory: $DIR_TO_REMOVE"
        
        # Remove old containers if they still exist
        if [ -f "$DIR_TO_REMOVE/.container" ]; then
            OLD_CONTAINER=$(cat "$DIR_TO_REMOVE/.container")
            docker rm -f "$OLD_CONTAINER" 2>/dev/null || true
        fi
        
        rm -rf "$DIR_TO_REMOVE"
    done
    
    echo "Cleanup of old release directories complete."
else
    echo "Found $COUNT releases. No cleanup needed."
fi

# Free up disk space by removing unused, untagged images
echo "Pruning dangling Docker images..."
docker image prune -f

echo "Cleanup finished."
