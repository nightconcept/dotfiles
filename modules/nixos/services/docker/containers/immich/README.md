# Immich

Self-hosted photo and video management solution.

## Access
- **URL**: https://photos.local.solivan.dev
- **Port**: 2283 (internal)

## Configuration

### Environment Variables
Located in `.env`:
- `UPLOAD_LOCATION`: `/mnt/titan/Photos/immich` - Where photos/videos are stored
- `DB_DATA_LOCATION`: `~/config/immich/postgres` - Database storage location
- `TZ`: `America/Los_Angeles` - Timezone
- `DB_PASSWORD`: Generated secure password for PostgreSQL

### Storage Paths
- **Media**: `/mnt/titan/Photos/immich`
- **Database**: `~/config/immich/postgres`
- **ML Models**: Docker volume `immich_model-cache`

## Services

### immich-server
Main application server handling web interface and API

### immich-machine-learning
ML service for face recognition, object detection, and smart search

### redis
In-memory data store for caching and queues

### database
PostgreSQL database with vector extensions for similarity search

## First Time Setup

1. Create necessary directories:
```bash
mkdir -p ~/config/immich/postgres
mkdir -p /mnt/titan/Photos/immich
```

2. Start the services:
```bash
docker compose up -d
```

3. Access the web interface at https://photos.local.solivan.dev

4. Create your admin account on first access

## Mobile App Configuration
1. Download Immich app from App Store or Google Play
2. Server URL: `https://photos.local.solivan.dev`
3. Use your created account credentials

## Maintenance

### View logs:
```bash
docker compose logs -f
```

### Restart services:
```bash
docker compose restart
```

### Update Immich:
```bash
docker compose pull
docker compose up -d
```

### Backup Database:
```bash
docker exec -t immich_postgres pg_dumpall -c -U postgres > ~/backup/immich_dump_$(date +%Y%m%d).sql
```

## Troubleshooting

### Machine Learning Not Working
Check ML container logs:
```bash
docker logs immich_machine_learning
```

### Database Connection Issues
Verify PostgreSQL is running:
```bash
docker exec immich_postgres pg_isready
```

### Storage Space
Monitor available space:
```bash
df -h /mnt/titan/Photos/immich
```

## Resources
- [Official Documentation](https://immich.app/docs)
- [GitHub Repository](https://github.com/immich-app/immich)
- [Environment Variables](https://immich.app/docs/install/environment-variables)