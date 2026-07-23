#!/bin/bash
set -e

PORT=$1
if [ -z "$PORT" ]; then
    echo "Error: Port required for health check."
    exit 1
fi

URL="http://127.0.0.1:$PORT/health"
MAX_RETRIES=10
RETRY_INTERVAL=3
ATTEMPT=1

echo "Checking health at $URL"

while [ $ATTEMPT -le $MAX_RETRIES ]; do
    echo "Attempt $ATTEMPT of $MAX_RETRIES..."
    
    if curl -s -f "$URL" > /dev/null; then
        echo "Application is healthy and ready to receive traffic!"
        exit 0
    fi
    
    echo "Not ready yet. Waiting $RETRY_INTERVAL seconds..."
    sleep $RETRY_INTERVAL
    ATTEMPT=$((ATTEMPT + 1))
done

echo "Health check timed out after $MAX_RETRIES attempts."
exit 1
