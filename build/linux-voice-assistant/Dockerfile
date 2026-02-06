FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    portaudio19-dev \
    pulseaudio \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Clone the repository
RUN git clone https://github.com/OHF-Voice/linux-voice-assistant.git /app
WORKDIR /app

# Install python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy example config
RUN cp config.yaml.example config.yaml

# Set the command to run the application
CMD ["python3", "-m", "lva"]
