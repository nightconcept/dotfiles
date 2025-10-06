# Obsidian LiveSync with CouchDB

Self-hosted Obsidian synchronization using CouchDB and the Self-hosted LiveSync plugin.

## Current Status

✅ CouchDB container is running and healthy
✅ Accessible at: https://obsidian-db.local.solivan.dev/
✅ Local storage configured at `/var/lib/obsidian-sync`

## Configuration

- **CouchDB Admin**: `obsidian_user` / `changeme` (configured in host config)
- **Database Port**: 5984
- **Domain**: obsidian-db.local.solivan.dev

## Remaining Setup Steps

### 1. Access CouchDB Admin Interface

Navigate to https://obsidian-db.local.solivan.dev/_utils and log in with the admin credentials.

### 2. Create Obsidian Database

1. Click "Create Database" in the CouchDB admin interface
2. Name the database: `obsidian`
3. Ensure it's **not** a partitioned database (uncheck if prompted)
4. Click "Create"

### 3. Configure Database Permissions

Set proper permissions for the `obsidian_user`:

1. Go to the `obsidian` database
2. Click on "Permissions" tab
3. Add `obsidian_user` to both:
   - **Admin roles**: For full database control
   - **Member roles**: For read/write access

### 4. Configure CORS (if needed)

For external access, enable CORS in CouchDB:

1. Go to Configuration in CouchDB admin
2. Find `httpd` section
3. Add/modify:
   - `enable_cors = true`
4. Add CORS origins if needed under `cors` section

### 5. Install Obsidian Self-hosted LiveSync Plugin

1. Open Obsidian
2. Go to Settings → Community Plugins
3. Search for "Self-hosted LiveSync"
4. Install and enable the plugin

### 6. Configure LiveSync Plugin

In the plugin settings:

1. **Setup URI**: `https://obsidian-db.local.solivan.dev/obsidian`
2. **Username**: `obsidian_user`
3. **Password**: `changeme` (or whatever you configured)
4. **Database name**: `obsidian`
5. Click "Test Connection" to verify
6. If successful, click "Check and Fix Database Configuration"
7. Enable "Live Sync"

### 7. Configure Additional Devices

To sync other devices:

1. In the plugin settings on the primary device:
   - Go to "Setup wizard" → "Copy setup URI"
   - This creates an encrypted URI
2. On the new device:
   - Install the LiveSync plugin
   - Use "Setup via URI" option
   - Paste the URI and enter your passphrase

## Docker Healthcheck

The container includes a healthcheck that verifies CouchDB is responding:

```yaml
healthcheck:
  test: curl --fail -s http://localhost:5984/_up | grep -Eo '\"status\":\"ok\"' || exit 1
  start_period: 60s
  interval: 30s
  timeout: 10s
  retries: 3
```

**Note**: You may see `401 Unauthorized` messages in logs when healthcheck runs, but as long as the endpoint returns with status `ok`, the healthcheck passes.

## Troubleshooting

### "_users database does not exist" errors
These are normal notices on first run. They'll resolve once you configure the LiveSync plugin and it creates necessary system databases.

### Permission Issues
If the container fails to start with permission errors:
- The module automatically creates directories with UID/GID 5984:5984 (CouchDB user)
- Verify with: `ls -la /var/lib/obsidian-sync/couchdb/`

### Connection Issues from Obsidian
- Ensure the URL includes the database name: `https://obsidian-db.local.solivan.dev/obsidian`
- Verify CORS is enabled if accessing from external devices
- Check that credentials match the configured admin user

## References

- [Self-hosting Obsidian Guide](https://pinggy.io/blog/self_hosting_obsidian/)
- [Self-hosted LiveSync Plugin](https://github.com/vrtmrz/obsidian-livesync)
- [CouchDB Documentation](https://docs.couchdb.org/)
