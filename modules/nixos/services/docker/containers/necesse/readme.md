# Necesse Docker Server

A containerized Necesse multiplayer game server using the [brammys/necesse-server](https://github.com/BrammyS/necesse-docker-server) Docker image.

## Overview

Necesse is a top-down sandbox action-adventure game. This configuration runs a dedicated server in Docker for multiplayer gameplay.

## Configuration

### Environment Variables

Edit the `.env` file to customize your server:

- `SERVER_PASSWORD`: Password required to join the server
- `OWNER_USERNAME`: Username of the player with owner permissions
- `WORLD`: World name (default: "world")
- `SLOTS`: Maximum player slots (default: 10)
- `PAUSE`: Pause world when empty - 0=no, 1=yes (default: 0)
- `LOGGING`: Generate session logs - 0=no, 1=yes (default: 1)
- `ZIP`: Compress save files - 0=no, 1=yes (default: 1)
- `JVMARGS`: Custom JVM arguments (e.g., "-Xmx2G" for 2GB RAM)
- `MOTD`: Message of the Day shown to players

### Network Configuration

The server uses:
- **Port 14159/UDP**: Game server communication
- **Network Mode**: Host networking for optimal performance

### Storage

Data is persisted in two locations:
- `~/config/necesse/saves`: World save files
- `~/config/necesse/logs`: Server logs

## Usage

### Starting the Server

```bash
# Copy and configure environment file
cp default.env .env
nano .env

# Start the server
docker compose up -d

# View logs
docker compose logs -f
```

### Stopping the Server

```bash
docker compose down
```

### Updating the Server

The server is configured with Watchtower labels for automatic updates. To manually update:

```bash
docker compose pull
docker compose up -d
```

## Connecting to the Server

1. Launch Necesse game client
2. Go to Multiplayer
3. Enter your server's IP address
4. Port: 14159
5. Enter the password you configured

## Firewall Configuration

Make sure to allow UDP port 14159 in your firewall:

```bash
# Ubuntu/Debian
sudo ufw allow 14159/udp

# For cloud providers, configure security groups to allow UDP 14159
```

## Performance Tuning

For servers with more players, increase memory allocation:

```env
JVMARGS=-Xmx4G  # 4GB RAM
```

## Troubleshooting

### Check server status
```bash
docker compose ps
docker compose logs
```

### Server not accessible
- Verify port 14159/UDP is open in firewall
- Check Docker is using host networking mode
- Ensure server password is correct

### High memory usage
- Reduce player slots (SLOTS)
- Adjust JVMARGS memory allocation
- Enable world pause when empty (PAUSE=1)

## Resources

- [Necesse Official Website](https://necessegame.com/)
- [Docker Image Repository](https://github.com/BrammyS/necesse-docker-server)
- [Necesse Wiki](https://necessewiki.com/)
