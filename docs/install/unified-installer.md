---
summary: "Unified installer for gateway and node deployments across macOS, Linux (Debian/Ubuntu/Rocky)"
read_when:
  - You want to deploy Moltbot with a reverse proxy (gateway mode)
  - You want to deploy Moltbot standalone (node mode)
  - You need multi-OS support (macOS, Debian/Ubuntu, Rocky Linux)
---

# Unified Installer (init.sh)

The unified installer script (`scripts/init.sh`) merges the functionality of `init_macos.sh` and `init_vhost.sh` into a single, cross-platform deployment tool.

## Quick Start

```bash
# Gateway mode with Caddy (default)
./scripts/init.sh clawdbot.svc.plus

# Node mode (no proxy)
MODE=node ./scripts/init.sh clawdbot.svc.plus

# Gateway mode with Nginx
PROXY=nginx CERTBOT_EMAIL=admin@example.com ./scripts/init.sh clawdbot.svc.plus
```

## Deployment Modes

### Gateway Mode (default)

Installs and configures:
- **Reverse Proxy** (Caddy or Nginx)
- **Moltbot** (gateway service)
- **Node.js 24** runtime
- **Automatic TLS** (via Caddy or Certbot)
- **Firewall rules** (ports 22, 80, 443, 18789)

**Use cases**:
- Production deployments with public HTTPS access
- Multi-tenant setups requiring TLS termination
- Environments needing centralized access control

**Example**:
```bash
# Caddy with automatic TLS
./scripts/init.sh moltbot.example.com

# Nginx with Certbot
PROXY=nginx CERTBOT_EMAIL=ops@example.com ./scripts/init.sh moltbot.example.com
```

### Node Mode

Installs and configures:
- **Moltbot** (gateway service)
- **Node.js 24** runtime

**Use cases**:
- Development environments
- Internal deployments behind existing reverse proxies
- Docker/Kubernetes environments (where ingress is handled externally)

**Example**:
```bash
MODE=node ./scripts/init.sh localhost
```

## Supported Platforms

| OS | Gateway Mode | Node Mode | Notes |
|---|---|---|---|
| **macOS** | ✅ Caddy only | ✅ | Requires Homebrew |
| **Debian/Ubuntu** | ✅ Caddy or Nginx | ✅ | UFW firewall |
| **Rocky Linux / RHEL** | ⚠️ Nginx only* | ✅ | firewalld |

\* Caddy requires manual installation or EPEL on Rocky Linux

## Environment Variables

### Core Configuration

| Variable | Default | Description |
|---|---|---|
| `MODE` | `gateway` | Deployment mode: `gateway` or `node` |
| `PROXY` | `caddy` | Proxy type: `caddy` or `nginx` (gateway mode only) |
| `INSTALL_METHOD` | `npm` | Install method: `npm` or `git` |
| `CLAWDBOT_VERSION` | `latest` | Version to install (npm method only) |

### Proxy Configuration

| Variable | Default | Description |
|---|---|---|
| `CERTBOT_EMAIL` | _(empty)_ | Email for Certbot (nginx mode only) |
| `GIT_REPO` | `https://github.com/cloud-neutral-toolkit/clawdbot.svc.plus.git` | Git repository URL (git install method) |

## Installation Methods

### NPM Install (default)

Installs the latest published version from npm:

```bash
./scripts/init.sh clawdbot.svc.plus
```

**Pros**:
- Fast installation
- Stable releases
- Automatic updates via npm

**Cons**:
- Cannot use unreleased features
- Requires npm registry access

### Git Install

Clones and builds from the source repository:

```bash
INSTALL_METHOD=git ./scripts/init.sh clawdbot.svc.plus
```

**Pros**:
- Access to latest development features
- Full source code available
- Custom modifications possible

**Cons**:
- Longer installation time (build required)
- Requires Git and pnpm
- May include unstable features

## Proxy Comparison

### Caddy (Recommended)

**Advantages**:
- Automatic TLS certificate management (ACME)
- Zero configuration for HTTPS
- Built-in HTTP/2 and HTTP/3 support
- Simpler configuration syntax

**Disadvantages**:
- Not available in default Rocky Linux repos
- Less mature than Nginx

**Configuration location**:
- Linux: `/etc/caddy/Caddyfile`
- macOS: `$(brew --prefix)/etc/Caddyfile`

**Example Caddyfile**:
```
clawdbot.svc.plus {
  reverse_proxy 127.0.0.1:18789
}
```

### Nginx + Certbot

**Advantages**:
- Widely available in all Linux distributions
- Mature and battle-tested
- Extensive ecosystem and documentation

**Disadvantages**:
- Requires separate Certbot setup for TLS
- More complex configuration
- Manual certificate renewal management

**Configuration location**:
- `/etc/nginx/sites-available/clawdbot-<domain>.conf`

**Example Nginx config**:
```nginx
server {
  listen 80;
  server_name clawdbot.svc.plus;

  location / {
    proxy_pass http://127.0.0.1:18789;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```

## Firewall Configuration

### Debian/Ubuntu (UFW)

The installer automatically configures UFW:

```bash
# Ports opened
- 22/tcp   (SSH)
- 80/tcp   (HTTP)
- 443/tcp  (HTTPS)
- 18789/tcp (Moltbot gateway)

# Default policies
- Outgoing: ALLOW
- Incoming: DENY (except allowed ports)
```

### Rocky Linux / RHEL (firewalld)

The installer automatically configures firewalld:

```bash
# Ports opened
- 22/tcp
- 80/tcp
- 443/tcp
- 18789/tcp

# Service enabled
systemctl enable --now firewalld
```

### macOS

macOS uses application-level firewall. Port management is left to the operator.

## Health Checks

The installer performs automatic health checks:

1. **Local Gateway Check**:
   ```bash
   curl http://127.0.0.1:18789
   ```

2. **Public HTTPS Check** (gateway mode only):
   ```bash
   curl https://<domain>
   ```

**Retry logic**:
- 5 attempts
- 2-second delay between attempts
- 5-second timeout per attempt

## Post-Installation

### View Configuration

```bash
# View trusted proxies
clawdbot config get gateway.trustedProxies

# View all gateway config
clawdbot config get gateway
```

### View Logs

**macOS**:
```bash
tail -f /tmp/clawdbot/clawdbot-gateway.log
```

**Linux**:
```bash
journalctl --user -u clawdbot-gateway --no-pager -f
```

### Restart Services

**Caddy**:
```bash
# macOS
brew services restart caddy

# Linux
sudo systemctl restart caddy
```

**Nginx**:
```bash
sudo systemctl restart nginx
```

**Moltbot**:
```bash
# macOS
clawdbot restart

# Linux
systemctl --user restart clawdbot-gateway
```

## Troubleshooting

### TLS Certificate Issues (Caddy)

**Symptom**: HTTPS not working after installation

**Solution**:
1. Check Caddy logs:
   ```bash
   # macOS
   tail -f $(brew --prefix)/var/log/caddy.log
   
   # Linux
   sudo journalctl -u caddy -f
   ```

2. Verify DNS points to server:
   ```bash
   dig +short <domain>
   ```

3. Ensure ports 80/443 are accessible:
   ```bash
   curl -I http://<domain>
   ```

### TLS Certificate Issues (Nginx + Certbot)

**Symptom**: Certbot fails to obtain certificate

**Solution**:
1. Check Certbot logs:
   ```bash
   sudo tail -f /var/log/letsencrypt/letsencrypt.log
   ```

2. Verify Nginx is serving HTTP:
   ```bash
   curl -I http://<domain>
   ```

3. Manually run Certbot:
   ```bash
   sudo certbot --nginx -d <domain>
   ```

### Node.js Version Issues

**Symptom**: `node: command not found` or version < 24

**Solution**:
```bash
# Debian/Ubuntu
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs

# Rocky Linux
curl -fsSL https://rpm.nodesource.com/setup_24.x | sudo -E bash -
sudo dnf install -y nodejs

# macOS
brew install node@24
brew link --overwrite --force node@24
```

### Permission Issues (npm global install)

**Symptom**: `EACCES` errors during npm install

**Solution**:
The installer automatically configures npm prefix to `~/.npm-global`. If issues persist:

```bash
# Verify npm prefix
npm config get prefix

# Should output: /home/<user>/.npm-global

# Add to PATH if missing
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Firewall Blocking Access

**Symptom**: Cannot access service from external network

**Solution**:

**UFW (Debian/Ubuntu)**:
```bash
# Check status
sudo ufw status verbose

# Manually allow ports
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**firewalld (Rocky Linux)**:
```bash
# Check status
sudo firewall-cmd --list-all

# Manually allow ports
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload
```

## Advanced Usage

### Custom Git Repository

```bash
GIT_REPO=https://github.com/myorg/clawdbot-fork.git \
INSTALL_METHOD=git \
./scripts/init.sh clawdbot.svc.plus
```

### Specific Version (npm)

```bash
CLAWDBOT_VERSION=1.2.3 ./scripts/init.sh clawdbot.svc.plus
```

### Non-Interactive Installation

```bash
# Ensure no prompts (useful for automation)
MODE=gateway \
PROXY=caddy \
INSTALL_METHOD=npm \
./scripts/init.sh clawdbot.svc.plus
```

### Development Setup

```bash
# Node mode for local development
MODE=node \
INSTALL_METHOD=git \
./scripts/init.sh localhost
```

## Security Considerations

1. **TLS Certificates**: Always use HTTPS in production (gateway mode)
2. **Firewall**: The installer configures basic firewall rules, but review and adjust based on your security requirements
3. **SSH Access**: Port 22 is opened by default; consider changing SSH port or using key-based authentication only
4. **Updates**: Regularly update Moltbot and system packages
5. **Certbot Email**: Provide a valid email for certificate expiration notifications

## Comparison with Legacy Installers

| Feature | init.sh (Unified) | init_macos.sh | init_vhost.sh |
|---|---|---|---|
| macOS Support | ✅ | ✅ | ❌ |
| Linux Support | ✅ | ❌ | ✅ |
| Rocky Linux | ✅ | ❌ | ❌ |
| Node Mode | ✅ | ❌ | ❌ |
| Gateway Mode | ✅ | ✅ | ✅ |
| Caddy Support | ✅ | ✅ | ✅ |
| Nginx Support | ✅ | ❌ | ✅ |
| Auto Firewall | ✅ | ❌ | ✅ |

## Migration from Legacy Installers

If you previously used `init_macos.sh` or `init_vhost.sh`, you can migrate to the unified installer:

1. **Backup current configuration**:
   ```bash
   clawdbot config export > clawdbot-config-backup.json
   ```

2. **Run unified installer**:
   ```bash
   ./scripts/init.sh <your-domain>
   ```

3. **Restore configuration if needed**:
   ```bash
   clawdbot config import < clawdbot-config-backup.json
   ```

The unified installer will detect existing installations and update them appropriately.
