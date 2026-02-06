FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    portaudio19-dev \
    pulseaudio \
    build-essential \
    libmpv-dev \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone the repository
RUN git clone https://github.com/OHF-Voice/linux-voice-assistant.git .

# Install python dependencies
RUN pip install --no-cache-dir -e .

# Set the entrypoint
ENTRYPOINT ["python3", "-m", "linux_voice_assistant"]

# Default arguments
CMD []
