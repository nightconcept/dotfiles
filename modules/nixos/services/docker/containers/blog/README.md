# Blog Static Site Container

This module deploys a static website using nginx:alpine, serving pre-built artifacts from a deployment directory.

## Architecture

- **URL**: `blog.local.solivan.dev`
- **Container**: nginx:alpine
- **Deployment Directory**: `/var/www/blog` (built artifacts only)
- **Source Repository**: `solivan-dev` (built in CI, not on server)
- **Reverse Proxy**: Traefik with automatic HTTPS
- **Auto-updates**: Watchtower enabled for nginx image updates

## Deployment Method

This container uses **Build-in-CI deployment** - builds happen in the CI pipeline, artifacts are deployed to the server.

### How it Works

1. **In CI/CD (Forgejo/GitHub Actions)**:
   - Repository is checked out
   - Build runs: `nix develop --command just build`
   - Creates `dist/` folder with static HTML/CSS/JS
   - Artifacts are packaged and transferred to rinoa

2. **On rinoa**:
   - Artifacts extracted to `/var/www/blog/`
   - nginx container mounts this directory (read-only)
   - nginx serves the built files
   - No build dependencies needed on the server

3. **Benefits**:
   - Rinoa doesn't need Nix, Moon-Build, or build tools
   - Clean separation: source code vs deployment artifacts
   - Faster deploys (no build time on server)
   - Build failures caught in CI before deployment

### CI/CD Workflow Setup

Example Forgejo Actions / GitHub Actions workflow:

```yaml
name: Deploy Blog

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v24
        with:
          nix_path: nixpkgs=channel:nixos-unstable

      - name: Enable flakes
        run: |
          mkdir -p ~/.config/nix
          echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

      - name: Build site
        run: nix develop --command just build

      - name: Package artifacts
        run: tar czf blog-dist.tar.gz -C dist .

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          ssh-keyscan -H ${{ secrets.SSH_HOST }} >> ~/.ssh/known_hosts

      - name: Deploy to rinoa
        run: |
          scp -i ~/.ssh/deploy_key blog-dist.tar.gz ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }}:/tmp/
          ssh -i ~/.ssh/deploy_key ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }} << 'EOF'
            mkdir -p /var/www/blog
            cd /var/www/blog
            tar xzf /tmp/blog-dist.tar.gz
            rm /tmp/blog-dist.tar.gz
          EOF
```

### Required Secrets

Configure these in your Forgejo/GitHub repository settings:

- **SSH_PRIVATE_KEY**: Private SSH key for rinoa access
  ```bash
  ssh-keygen -t ed25519 -C "blog-deploy" -f ~/.ssh/blog_deploy
  # Add public key to rinoa: ~/.ssh/authorized_keys
  # Add private key content to repository secret
  ```

- **SSH_HOST**: Hostname or IP of rinoa (e.g., `rinoa.local` or `192.168.1.100`)

- **SSH_USER**: User account on rinoa (e.g., `danny`)

### SSH Key Setup on rinoa

1. **Add public key to authorized_keys**:
   ```bash
   # On rinoa
   cat >> ~/.ssh/authorized_keys << 'EOF'
   ssh-ed25519 AAAA... blog-deploy
   EOF
   ```

2. **Optional: Restrict key permissions** (recommended):
   ```bash
   # Prepend command restriction to authorized_keys entry
   command="cd /var/www/blog && tar xzf /tmp/blog-dist.tar.gz && rm /tmp/blog-dist.tar.gz" ssh-ed25519 AAAA...
   ```

### Manual Deployment

For testing or emergency deploys:

```bash
# On your local machine (from solivan-dev repo)
nix develop --command just build
tar czf blog-dist.tar.gz -C dist .
scp blog-dist.tar.gz rinoa:/tmp/
ssh rinoa "cd /var/www/blog && tar xzf /tmp/blog-dist.tar.gz && rm /tmp/blog-dist.tar.gz"
```

## Configuration Options

```nix
modules.nixos.docker.containers.blog = {
  enable = true;                    # Enable the blog container
  domain = "local.solivan.dev";     # Base domain
  subdomain = "blog";               # Subdomain (blog.local.solivan.dev)
  port = 8080;                      # Internal port
  sitePath = "/var/www/blog";       # Path to deployment artifacts
  enableWatchtower = true;          # Auto-update nginx image
};
```

## Directory Structure on rinoa

```
/var/www/blog/           # Deployment directory (auto-created by NixOS)
├── index.html           # Built files extracted here
├── assets/
│   ├── css/
│   ├── js/
│   └── images/
└── ...                  # Other static assets
```

The `/var/www/blog` directory is:
- Created automatically by systemd-tmpfiles (owner: danny, group: users)
- Mounted read-only into the nginx container
- Overwritten on each deployment (tar extracts in place)

## Manual Operations

```bash
# Restart the container
systemctl restart docker-container-blog

# View container logs
docker logs blog

# Check container status
docker ps | grep blog

# View service status
systemctl status docker-container-blog

# Check deployment directory contents
ls -la /var/www/blog

# Test nginx can read files
docker exec blog ls -la /usr/share/nginx/html
```

## Troubleshooting

**Site shows 404 or empty page?**
- Check files exist: `ls -la /var/www/blog`
- Verify build created output: Check CI logs for `just build` step
- Ensure tar extracted correctly: Files should be at `/var/www/blog/index.html`, not `/var/www/blog/dist/index.html`
- Check tar command: Use `-C dist .` to extract dist contents, not the dist folder itself

**Site not updating after deployment?**
- nginx serves files directly from disk - updates should be instant
- Verify tar extracted new files: `stat /var/www/blog/index.html`
- Check container mount: `docker inspect blog | grep -A 5 Mounts`
- Try restarting container: `systemctl restart docker-container-blog`

**CI deployment fails with permission denied?**
- Check SSH key is correctly configured
- Verify user has write access to `/var/www/blog` (should be owned by danny)
- Test SSH connection: `ssh -i ~/.ssh/deploy_key danny@rinoa "ls -la /var/www/blog"`

**502 Bad Gateway?**
- Check container is running: `docker ps | grep blog`
- Verify Traefik can reach the blog service on port 80 (internal)
- Check Traefik logs: `docker logs traefik`

**Can't access blog.local.solivan.dev?**
- Verify DNS/mDNS resolution to rinoa
- Check Traefik router: `docker logs traefik | grep blog`
- Confirm container is on proxy network: `docker inspect blog | grep proxy`

## Build Requirements

The build process (runs in CI, not on rinoa):
- **Nix** with flakes enabled
- **Moon-Build** (Lua-based build tool)
- **just** (command runner)
- Source repository: `solivan-dev`
- Build command: `nix develop --command just build`
- Output: `dist/` directory with static files
