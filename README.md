# cleanuparr-monitor

Here is a simple utility container that enables/disables Cleanuparr Queue Cleaner based on internet connectivity.

On startup, the container does an initial network connectivity check and either enables/disables the Queue Cleaner in Cleanuparr, then continues to monitor connectivity at the configured interval.

I made this so the Queue Cleaner doesn't empty any queues should my internet be down for an exteded duration.

Minimal / No support

## Usage

Docker compose:
```
services:

  cleanuparr:
    image: ghcr.io/cleanuparr/cleanuparr:latest
    container_name: cleanuparr
    restart: unless-stopped
    volumes:
      - ./cleanup:/config
    networks:
      Other_NetworksABC:
      Cleanuparr_Net:         # Shared internal network
    environment:
      - PORT=11011
    depends_on:
      cleanuparr-monitor:
        condition: service_started

  cleanuparr-monitor:
    build: ./cleanup-monitor # This repo
    container_name: cleanuparr-monitor
    restart: unless-stopped
    networks:
      Other_NetworksXYZ:
      Cleanuparr_Net:         # Shared internal network
    environment:
      - ENDPOINT=http://cleanuparr:11011/api/configuration/queue_cleaner # Cleanuparr API
      - INTERVAL=300                                                     # Interval to check internet connectivity
      - SUCCESS_THRESHOLD=3                                              # Successive checks needed to (re)enable Queue Cleaner
      
networks:
  Cleanuparr_Net:
    internal: true
```
