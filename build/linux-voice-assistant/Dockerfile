FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    portaudio19-dev \
    pulseaudio \
    pulseaudio-utils \
    alsa-utils \
    libasound2-plugins \
    build-essential \
    libmpv-dev \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Allow PulseAudio system mode for root
RUN adduser root pulse-access 2>/dev/null || true

WORKDIR /app

# Clone the repository
RUN git clone https://github.com/OHF-Voice/linux-voice-assistant.git .

# Install python dependencies
RUN pip install --no-cache-dir -e .

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

# Default arguments
CMD []
