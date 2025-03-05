# Lightweight RTSP Server Implementation Guide

This guide explains how to implement a modern, lightweight RTSP streaming solution for your USB webcam using GStreamer in a Kubernetes environment.

## Overview

This implementation offers several advantages over the previous approach:

- **Automatic format detection** - adapts to your webcam's capabilities
- **Multiple output options** - provides both RTSP and UDP streams
- **Reduced resource usage** - optimized container and pipeline
- **Better error handling** - improved diagnostics and recovery
- **Advanced pipeline options** - tuned for low latency and stability

## Implementation Steps

### 1. Build the Docker Image

First, create the Dockerfile and streaming script:

1. Save the Dockerfile to a new directory
2. Save the `stream-rtsp.sh` script to the same directory
3. Build the Docker image:

```bash
docker build -t webcam-rtsp:latest .
```

Optional: Push to your registry if using a remote cluster:

```bash
docker tag webcam-rtsp:latest your-registry/webcam-rtsp:latest
docker push your-registry/webcam-rtsp:latest
```

### 2. Update Kubernetes Resources

1. Update your Kubernetes deployment YAML to match the provided template
2. Make sure the ConfigMap contains all required parameters:

```bash
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

### 3. Test the Stream

Once deployed, you can connect to the RTSP stream using:

- **RTSP Stream**: `rtsp://<service-ip>:8554/webcam`
- **Alternative UDP Stream**: Available on port 5000

You can test playback with VLC or ffplay:

```bash
# For RTSP stream
vlc rtsp://<service-ip>:8554/webcam

# For UDP stream (if RTSP isn't working)
ffplay -i udp://<service-ip>:5000
```

## Tuning Parameters

You can adjust these parameters in the ConfigMap:

| Parameter | Description | Default |
|-----------|-------------|---------|
| WEBCAM_DEVICE | Path to webcam device | /dev/video0 |
| VIDEO_WIDTH | Width of video stream | 640 |
| VIDEO_HEIGHT | Height of video stream | 480 |
| VIDEO_FRAMERATE | Frames per second | 30 |
| VIDEO_FORMAT | Format (auto, h264, mjpeg, raw) | auto |
| RTSP_PORT | Port for RTSP server | 8554 |
| RTSP_MOUNT_POINT | URL path for RTSP stream | /webcam |
| BUFFER_SIZE | Size of GStreamer buffer pool | 64 |

## Troubleshooting

### Check container logs for issues:

```bash
kubectl logs -f deployment/webcam-rtsp-server
```

### Verify webcam is accessible:

```bash
kubectl exec -it deployment/webcam-rtsp-server -- ls -la /dev/video*
kubectl exec -it deployment/webcam-rtsp-server -- v4l2-ctl --device=/dev/video0 --list-formats-ext
```

### Test direct streaming from pod:

```bash
kubectl exec -it deployment/webcam-rtsp-server -- gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! xvimagesink
```

## Advanced Options

### Lower Latency Mode

For applications requiring minimal latency, add these settings to the ConfigMap:

```yaml
  LOW_LATENCY: "true"
  KEY_FRAME_INTERVAL: "15"
  GOP_SIZE: "15"
  TUNE_OPTIONS: "zerolatency"
```

And update the script to use these parameters.

### Hardware Acceleration

For devices with hardware acceleration (like Raspberry Pi), you can modify the pipeline to use hardware encoders:

- For Raspberry Pi: Replace `x264enc` with `v4l2h264enc`
- For NVIDIA GPUs: Replace `x264enc` with `nvh264enc`

Adjust the Dockerfile and script accordingly.

## Final Notes

- This implementation prioritizes lightweight operation and compatibility
- For recording functionality, consider adding a separate sidecar container
- Motion detection could be added with additional GStreamer elements

If you need further customization, refer to the GStreamer documentation for more pipeline options.