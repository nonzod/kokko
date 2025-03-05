#!/bin/bash
set -e

# Configuration from environment variables
DEVICE="${WEBCAM_DEVICE:-/dev/video0}"
WIDTH="${VIDEO_WIDTH:-640}"
HEIGHT="${VIDEO_HEIGHT:-480}"
FRAMERATE="${VIDEO_FRAMERATE:-30}"
FORMAT="${VIDEO_FORMAT:-auto}"
PORT="${RTSP_PORT:-8554}"
MOUNT_POINT="${RTSP_MOUNT_POINT:-/webcam}"
BUFFER_SIZE="${BUFFER_SIZE:-64}"

# Verify webcam exists
if [ ! -e "$DEVICE" ]; then
    echo "ERROR: Webcam device $DEVICE not found!"
    echo "Available video devices:"
    ls -la /dev/video* 2>/dev/null || echo "No video devices found"
    exit 1
fi

# Find best supported format if auto
if [ "$FORMAT" = "auto" ]; then
    echo "Detecting optimal video format..."
    
    # Check if H.264 is supported directly by camera (preferred)
    if v4l2-ctl --device=$DEVICE --list-formats-ext 2>/dev/null | grep -q "H.264"; then
        FORMAT="h264"
        echo "Native H.264 support detected - using direct encoding"
    # Check if MJPEG is supported (good alternative)
    elif v4l2-ctl --device=$DEVICE --list-formats-ext 2>/dev/null | grep -q "MJPG\|MJPEG"; then
        FORMAT="mjpeg"
        echo "MJPEG support detected - using hardware MJPEG encoding"
    # Fall back to raw (requires more CPU for encoding)
    else
        FORMAT="raw"
        echo "Using raw format with software encoding"
    fi
fi

# Log startup information
echo "────────────────────────────────────────────"
echo "🎥 Starting lightweight Video Streaming Server"
echo "────────────────────────────────────────────"
echo "Device:     $DEVICE"
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo "Framerate:  $FRAMERATE fps"
echo "Format:     $FORMAT"
echo "UDP Stream: udp://SERVER_IP:5000"
echo "────────────────────────────────────────────"

# Set up better buffer management
export GST_BUFFER_POOL_MAX_SIZE=$BUFFER_SIZE

# Build the GStreamer pipeline based on detected format
ENCODER_TYPE="unknown"
case $FORMAT in
    "h264")
        # Native H.264 - most efficient
        ENCODER_TYPE="h264"
        gst-launch-1.0 -v \
            v4l2src device=$DEVICE io-mode=mmap ! \
            video/x-h264,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 ! \
            h264parse ! \
            rtph264pay config-interval=1 pt=96 ! \
            udpsink host=0.0.0.0 port=5000 sync=false async=false &
        ;;
    "mjpeg")
        # MJPEG - hardware accelerated on many devices
        if gst-inspect-1.0 avenc_h264 >/dev/null 2>&1; then
            ENCODER_TYPE="h264"
            echo "Using avenc_h264 encoder"
            gst-launch-1.0 -v \
                v4l2src device=$DEVICE io-mode=mmap ! \
                image/jpeg,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 ! \
                jpegdec ! \
                videoconvert ! \
                avenc_h264 preset=ultrafast tune=zerolatency ! \
                h264parse ! \
                rtph264pay config-interval=1 pt=96 ! \
                udpsink host=0.0.0.0 port=5000 sync=false async=false &
        else
            ENCODER_TYPE="jpeg"
            echo "Using jpeg encoding directly"
            gst-launch-1.0 -v \
                v4l2src device=$DEVICE io-mode=mmap ! \
                image/jpeg,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 ! \
                rtpjpegpay ! \
                udpsink host=0.0.0.0 port=5000 sync=false async=false &
        fi
        ;;
    *)
        # Try multiple encoders in order of preference
        echo "Trying encoders in sequence until we find one that works..."
        
        # First try x264enc (if available)
        if gst-inspect-1.0 x264enc >/dev/null 2>&1; then
            ENCODER_TYPE="h264"
            echo "Using x264enc encoder"
            gst-launch-1.0 -v \
                v4l2src device=$DEVICE io-mode=mmap ! \
                video/x-raw,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 ! \
                videoconvert ! \
                x264enc tune=zerolatency speed-preset=ultrafast bitrate=1000 ! \
                h264parse ! \
                rtph264pay config-interval=1 pt=96 ! \
                udpsink host=0.0.0.0 port=5000 sync=false async=false &
        
        # Next try avenc_h264 from libav (usually available with gstreamer1.0-libav)
        elif gst-inspect-1.0 avenc_h264 >/dev/null 2>&1; then
            ENCODER_TYPE="h264"
            echo "Using avenc_h264 encoder"
            gst-launch-1.0 -v \
                v4l2src device=$DEVICE io-mode=mmap ! \
                video/x-raw,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 ! \
                videoconvert ! \
                avenc_h264 preset=ultrafast tune=zerolatency ! \
                h264parse ! \
                rtph264pay config-interval=1 pt=96 ! \
                udpsink host=0.0.0.0 port=5000 sync=false async=false &
        
        # Finally try JPEG encoding as a fallback
        elif gst-inspect-1.0 jpegenc >/dev/null 2>&1; then
            ENCODER_TYPE="jpeg"
            echo "Using jpeg encoding as fallback"
            gst-launch-1.0 -v \
                v4l2src device=$DEVICE io-mode=mmap ! \
                video/x-raw,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 ! \
                videoconvert ! \
                jpegenc quality=70 ! \
                rtpjpegpay ! \
                udpsink host=0.0.0.0 port=5000 sync=false async=false &
        
        # If nothing else works, try raw video (very high bandwidth)
        else
            ENCODER_TYPE="raw"
            echo "WARNING: No suitable video encoders found, using raw video (high bandwidth)"
            gst-launch-1.0 -v \
                v4l2src device=$DEVICE io-mode=mmap ! \
                video/x-raw,width=$WIDTH,height=$HEIGHT,framerate=$FRAMERATE/1 ! \
                videoconvert ! \
                rtpvrawpay ! \
                udpsink host=0.0.0.0 port=5000 sync=false async=false &
        fi
        ;;
esac

# Update HTML with actual encoder used
create_html_instructions "$ENCODER_TYPE"

STREAM_PID=$!

# Create a fallback HTML with connection instructions based on encoder
create_html_instructions() {
    local encoder_type=$1
    
    # Create HTML with appropriate instructions based on encoder
    cat > /tmp/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>WebCam Stream</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        pre { background: #f5f5f5; padding: 10px; border-radius: 5px; }
        .container { margin-top: 20px; }
    </style>
</head>
<body>
    <h1>WebCam Stream Available</h1>
    <p>Your webcam stream is running! You can connect to it using:</p>
EOF

    # Add appropriate connection instructions based on encoder
    if [[ "$encoder_type" == "h264" ]]; then
        cat >> /tmp/index.html << EOF
    <div class="container">
        <h3>For VLC:</h3>
        <pre>vlc udp://@:5000</pre>
        <p>Or open VLC, go to Media > Open Network Stream and enter: <code>udp://@:5000</code></p>
    </div>
    
    <div class="container">
        <h3>For FFPlay:</h3>
        <pre>ffplay -i udp://SERVER_IP:5000</pre>
    </div>
    
    <div class="container">
        <h3>For GStreamer:</h3>
        <pre>gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp,media=video,encoding-name=H264" ! rtph264depay ! h264parse ! avdec_h264 ! autovideosink</pre>
    </div>
EOF
    elif [[ "$encoder_type" == "jpeg" ]]; then
        cat >> /tmp/index.html << EOF
    <div class="container">
        <h3>For VLC:</h3>
        <pre>vlc udp://@:5000</pre>
        <p>Or open VLC, go to Media > Open Network Stream and enter: <code>udp://@:5000</code></p>
    </div>
    
    <div class="container">
        <h3>For GStreamer:</h3>
        <pre>gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp,media=video,encoding-name=JPEG" ! rtpjpegdepay ! jpegdec ! autovideosink</pre>
    </div>
EOF
    else
        cat >> /tmp/index.html << EOF
    <div class="container">
        <h3>For VLC:</h3>
        <pre>vlc udp://@:5000</pre>
        <p>Or open VLC, go to Media > Open Network Stream and enter: <code>udp://@:5000</code></p>
    </div>
EOF
    fi

    # Common HTML footer
    cat >> /tmp/index.html << EOF
    <div class="container">
        <h3>Stream Information:</h3>
        <ul>
            <li>Resolution: ${WIDTH}x${HEIGHT}</li>
            <li>Framerate: ${FRAMERATE} fps</li>
            <li>Protocol: RTP/UDP</li>
            <li>Port: 5000</li>
            <li>Encoder: ${encoder_type}</li>
        </ul>
    </div>
</body>
</html>
EOF
}

# Default to h264 for initial page creation
create_html_instructions "h264"

# Start a simple HTTP server on port 8554 to serve instructions
echo "Starting HTTP server on port 8554 to provide connection instructions..."
# Create a fallback method if netcat isn't available
if command -v nc > /dev/null 2>&1; then
    { echo -ne "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n"; cat /tmp/index.html; } | nc -l -p 8554 &
else
    echo "Netcat not found, skipping HTTP server"
    # Just print instructions to log
    echo "Connect using: vlc udp://@:5000"
fi

echo "────────────────────────────────────────────"
echo "🚀 Streaming started! UDP stream available at:"
echo "udp://SERVER_IP:5000"
echo ""
echo "Access http://SERVER_IP:8554 for connection instructions"
echo "────────────────────────────────────────────"

# Handle signals properly
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# Monitor the streaming process
while true; do
    # Check if process is running without using ps
    if [ ! -d "/proc/$STREAM_PID" ]; then
        echo "Stream process died, restarting..."
        # Restart the stream with the same configuration
        exec "$0"
    fi
    sleep 5
done