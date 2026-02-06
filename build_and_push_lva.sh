#!/bin/bash

echo "Building Docker image for linux-voice-assistant..."
docker build -t nonzod/linux-voice-assistant:latest build/linux-voice-assistant

if [ $? -eq 0 ]; then
    echo "Docker image built successfully. Pushing to Docker Hub..."
    docker push nonzod/linux-voice-assistant:latest
    if [ $? -eq 0 ]; then
        echo "Docker image pushed to Docker Hub successfully."
    else
        echo "Error: Failed to push Docker image to Docker Hub."
    fi
else
    echo "Error: Failed to build Docker image."
fi
