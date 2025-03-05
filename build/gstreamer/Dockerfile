FROM debian:bookworm-slim

# Install essential packages and GStreamer with minimal dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-rtsp \
    gstreamer1.0-libav \
    v4l-utils \
    procps \
    netcat-openbsd \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables with defaults
ENV WEBCAM_DEVICE="/dev/video0" \
    VIDEO_WIDTH="640" \
    VIDEO_HEIGHT="480" \
    VIDEO_FRAMERATE="30" \
    VIDEO_FORMAT="auto" \
    RTSP_PORT="8554" \
    RTSP_MOUNT_POINT="/webcam" \
    BUFFER_SIZE="64"

# Copy the streaming script
COPY micro-rtsp-server /usr/local/bin/
RUN chmod +x /usr/local/bin/micro-rtsp-server

# Expose ports for RTSP and UDP streaming
EXPOSE 8554/tcp
EXPOSE 5000/udp

# ENV DEVICE=${WEBCAM_DEVICE:-/dev/video0}
# ENV WIDTH=${VIDEO_WIDTH:-640}
# ENV HEIGHT=${VIDEO_HEIGHT:-480}
# ENV FRAMERATE=${VIDEO_FRAMERATE:-30}
# ENV PORT=${RTSP_PORT:-8554}
# ENV MOUNT_POINT=${RTSP_MOUNT_POINT:-/webcam}

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/micro-rtsp-server"]


