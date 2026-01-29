---
summary: "Step-by-step testing guide for unified installer across different platforms and modes"
read_when:
  - You want to validate the unified installer
  - You need to test deployment scenarios
  - You're preparing for production deployment
---

# Unified Installer Testing Guide

This guide provides detailed test scenarios for validating the unified installer (`scripts/init.sh`) across different platforms and deployment modes.

## Test Environment Requirements

### Ubuntu/Debian Test Environment

**Recommended Setup**:
- Fresh Ubuntu 22.04 LTS or Debian 12 VM/container
- Minimum 2GB RAM, 2 vCPU
- Root/sudo access
- Public IP or domain name (for gateway mode with real TLS)

**Quick VM Setup Options**:
```bash
# Option 1: Multipass (macOS/Linux/Windows)
multipass launch --name moltbot-test --cpus 2 --memory 2G --disk 10G 22.04
multipass shell moltbot-test

# Option 2: Docker (for testing, not production)
docker run -it --rm -p 80:80 -p 443:443 -p 18789:18789 ubuntu:22.04 bash
apt-get update && apt-get install -y sudo curl

# Option 3: Cloud provider (DigitalOcean, Linode, etc.)
# Create a $5/month droplet with Ubuntu 22.04
```

### macOS Test Environment

**Requirements**:
- macOS 12+ (Monterey or later)
- Homebrew installed
- Terminal access

**Homebrew Installation** (if needed):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Test Scenario 1: Ubuntu/Debian Gateway Mode (Caddy)

### Prerequisites

1. **Fresh Ubuntu/Debian system**
2. **Domain name** pointing to the server's IP
3. **Ports 80/443** accessible from the internet

### Test Steps

#### Step 1: Download the Installer

```bash
# SSH into your Ubuntu/Debian server
ssh user@your-server-ip

# Clone the repository (or download the script)
git clone https://github.com/cloud-neutral-toolkit/clawdbot.svc.plus.git
cd clawdbot.svc.plus

# Or download the script directly
# curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/clawdbot.svc.plus/main/scripts/init.sh -o init.sh
# chmod +x init.sh
```

#### Step 2: Run the Installer

```bash
# Replace with your actual domain
DOMAIN="moltbot.example.com"

# Run installer in gateway mode with Caddy (default)
sudo ./scripts/init.sh "$DOMAIN"
```

#### Step 3: Monitor Installation

**Expected Output**:
```
==> Moltbot Installer
    Mode: gateway
    Domain: moltbot.example.com
    OS: linux (ubuntu)
    Proxy: caddy

[Installing packages...]
[Installing Node.js 24...]
[Installing pnpm...]
[Configuring firewall...]
[Installing Moltbot...]
[Configuring Moltbot...]
[Configuring Caddy...]
[Running health checks...]

✅ Done.

Gateway is listening on http://127.0.0.1:18789 and proxied via https://moltbot.example.com.
Access control and TLS are handled by CADDY.
```

#### Step 4: Verify Installation

**Check Services**:
```bash
# Check Caddy status
sudo systemctl status caddy

# Check Moltbot status
systemctl --user status clawdbot-gateway

# Check Node.js version
node --version  # Should be v24.x.x
```

**Check Firewall**:
```bash
sudo ufw status verbose

# Expected output:
# Status: active
# To                         Action      From
# --                         ------      ----
# 22/tcp                     ALLOW       Anywhere
# 80/tcp                     ALLOW       Anywhere
# 443/tcp                    ALLOW       Anywhere
# 18789/tcp                  ALLOW       Anywhere
```

**Check Caddy Configuration**:
```bash
cat /etc/caddy/Caddyfile

# Expected output:
# moltbot.example.com {
#   reverse_proxy 127.0.0.1:18789
# }
```

**Test Local Gateway**:
```bash
curl -I http://127.0.0.1:18789

# Expected: HTTP/1.1 200 OK or 302 redirect
```

**Test Public HTTPS**:
```bash
curl -I https://moltbot.example.com

# Expected: HTTP/2 200 OK (with valid TLS certificate)
```

**Check TLS Certificate**:
```bash
echo | openssl s_client -connect moltbot.example.com:443 -servername moltbot.example.com 2>/dev/null | openssl x509 -noout -dates

# Expected output showing valid certificate dates
```

#### Step 5: Test Moltbot Functionality

**Access Web Interface**:
```bash
# Open in browser
https://moltbot.example.com
```

**Check Logs**:
```bash
# Moltbot logs
journalctl --user -u clawdbot-gateway -n 50 --no-pager

# Caddy logs
sudo journalctl -u caddy -n 50 --no-pager
```

### Expected Results

✅ **Success Criteria**:
- [ ] Caddy service running and enabled
- [ ] Moltbot gateway service running
- [ ] Node.js 24+ installed
- [ ] UFW firewall configured with correct rules
- [ ] TLS certificate obtained automatically
- [ ] HTTPS endpoint accessible from public internet
- [ ] HTTP redirects to HTTPS
- [ ] Moltbot web interface loads successfully

### Troubleshooting

**Issue**: TLS certificate not obtained

**Solution**:
```bash
# Check Caddy logs for ACME errors
sudo journalctl -u caddy -f

# Verify DNS is correct
dig +short moltbot.example.com

# Manually trigger certificate
sudo systemctl restart caddy
```

**Issue**: Firewall blocking access

**Solution**:
```bash
# Check UFW status
sudo ufw status verbose

# Manually allow ports if needed
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

---

## Test Scenario 2: Ubuntu/Debian Gateway Mode (Nginx)

### Prerequisites

Same as Scenario 1, plus:
- **Email address** for Certbot notifications

### Test Steps

#### Step 1: Download the Installer

Same as Scenario 1.

#### Step 2: Run the Installer with Nginx

```bash
DOMAIN="moltbot.example.com"
EMAIL="admin@example.com"

# Run installer with Nginx proxy
PROXY=nginx CERTBOT_EMAIL="$EMAIL" sudo ./scripts/init.sh "$DOMAIN"
```

#### Step 3: Monitor Installation

**Expected Output**:
```
==> Moltbot Installer
    Mode: gateway
    Domain: moltbot.example.com
    OS: linux (ubuntu)
    Proxy: nginx

[Installing packages including nginx, certbot...]
[Installing Node.js 24...]
[Installing pnpm...]
[Configuring firewall...]
[Installing Moltbot...]
[Configuring Moltbot...]
[Configuring Nginx...]
[Running Certbot...]

Saving debug log to /var/log/letsencrypt/letsencrypt.log
Requesting a certificate for moltbot.example.com
Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/moltbot.example.com/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/moltbot.example.com/privkey.pem

✅ Done.

Gateway is listening on http://127.0.0.1:18789 and proxied via https://moltbot.example.com.
Access control and TLS are handled by NGINX.
```

#### Step 4: Verify Installation

**Check Services**:
```bash
# Check Nginx status
sudo systemctl status nginx

# Check Moltbot status
systemctl --user status clawdbot-gateway
```

**Check Nginx Configuration**:
```bash
cat /etc/nginx/sites-available/clawdbot-moltbot.example.com.conf

# Verify it's enabled
ls -l /etc/nginx/sites-enabled/
```

**Test Nginx Configuration**:
```bash
sudo nginx -t

# Expected: syntax is ok, test is successful
```

**Check Certbot Certificate**:
```bash
sudo certbot certificates

# Expected output showing certificate for moltbot.example.com
```

**Test HTTPS**:
```bash
curl -I https://moltbot.example.com

# Expected: HTTP/1.1 200 OK (or 302)
```

**Test HTTP to HTTPS Redirect**:
```bash
curl -I http://moltbot.example.com

# Expected: HTTP/1.1 301 Moved Permanently
# Location: https://moltbot.example.com/
```

#### Step 5: Test Certificate Auto-Renewal

```bash
# Dry-run renewal
sudo certbot renew --dry-run

# Expected: Congratulations, all simulated renewals succeeded
```

### Expected Results

✅ **Success Criteria**:
- [ ] Nginx service running and enabled
- [ ] Moltbot gateway service running
- [ ] Certbot certificate obtained successfully
- [ ] HTTP to HTTPS redirect working
- [ ] Certificate auto-renewal configured
- [ ] Nginx configuration valid
- [ ] Public HTTPS endpoint accessible

### Troubleshooting

**Issue**: Certbot fails with "Connection refused"

**Solution**:
```bash
# Ensure Nginx is serving HTTP first
curl -I http://moltbot.example.com

# Check Nginx error logs
sudo tail -f /var/log/nginx/error.log

# Manually run Certbot with verbose output
sudo certbot --nginx -d moltbot.example.com --email admin@example.com --agree-tos -v
```

**Issue**: Nginx configuration error

**Solution**:
```bash
# Test configuration
sudo nginx -t

# Check syntax errors in config file
sudo cat /etc/nginx/sites-available/clawdbot-moltbot.example.com.conf

# Reload Nginx
sudo systemctl reload nginx
```

---

## Test Scenario 3: macOS Node Mode

### Prerequisites

- macOS 12+ (Monterey or later)
- Homebrew installed
- Terminal access
- **No domain required** (local deployment)

### Test Steps

#### Step 1: Download the Installer

```bash
# Clone the repository
git clone https://github.com/cloud-neutral-toolkit/clawdbot.svc.plus.git
cd clawdbot.svc.plus

# Or download the script
# curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/clawdbot.svc.plus/main/scripts/init.sh -o init.sh
# chmod +x init.sh
```

#### Step 2: Run the Installer in Node Mode

```bash
# Run installer in node mode (no proxy)
MODE=node ./scripts/init.sh localhost
```

#### Step 3: Monitor Installation

**Expected Output**:
```
==> Moltbot Installer
    Mode: node
    Domain: localhost
    OS: darwin (N/A)

[Installing packages: git, curl...]
[Installing Node.js 24...]
[Installing pnpm...]
[Installing Moltbot...]
[Configuring Moltbot...]
[Running health checks...]

✅ Done.

Moltbot is running in node mode (no proxy).
Gateway is listening on http://127.0.0.1:18789.

Configuration:
  - View config: `clawdbot config get gateway.trustedProxies`
  - View logs: `tail -f /tmp/clawdbot/clawdbot-gateway.log`
```

#### Step 4: Verify Installation

**Check Node.js Version**:
```bash
node --version

# Expected: v24.x.x
```

**Check pnpm**:
```bash
pnpm --version

# Expected: 9.x.x or later
```

**Check Moltbot Installation**:
```bash
which clawdbot

# Expected: /usr/local/bin/clawdbot or similar
```

**Check Moltbot Version**:
```bash
clawdbot --version

# Expected: version number
```

**Test Local Gateway**:
```bash
curl -I http://127.0.0.1:18789

# Expected: HTTP/1.1 200 OK or 302
```

**Check Moltbot Process**:
```bash
ps aux | grep clawdbot

# Expected: clawdbot-gateway process running
```

#### Step 5: Test Moltbot Functionality

**Access Web Interface**:
```bash
# Open in browser
open http://127.0.0.1:18789
```

**Check Logs**:
```bash
tail -f /tmp/clawdbot/clawdbot-gateway.log
```

**Test Configuration**:
```bash
# View all config
clawdbot config get

# View specific config
clawdbot config get gateway
```

**Test Restart**:
```bash
# Restart Moltbot
clawdbot restart

# Wait a few seconds
sleep 5

# Verify it's running
curl -I http://127.0.0.1:18789
```

### Expected Results

✅ **Success Criteria**:
- [ ] Node.js 24+ installed via Homebrew
- [ ] pnpm installed and configured
- [ ] Moltbot installed globally
- [ ] Gateway service running on port 18789
- [ ] Web interface accessible at http://127.0.0.1:18789
- [ ] Logs available in /tmp/clawdbot/
- [ ] No proxy configured (direct access only)

### Troubleshooting

**Issue**: Node.js not found after installation

**Solution**:
```bash
# Check Homebrew installation
brew list node@24

# Link Node.js 24
brew link --overwrite --force node@24

# Verify PATH
echo $PATH | grep -o '/usr/local/bin'

# Restart terminal and try again
```

**Issue**: Port 18789 already in use

**Solution**:
```bash
# Check what's using the port
lsof -i :18789

# Kill the process if needed
kill -9 <PID>

# Or configure Moltbot to use a different port
clawdbot config set gateway.port 18790
clawdbot restart
```

**Issue**: Permission denied errors

**Solution**:
```bash
# Check file permissions
ls -la /tmp/clawdbot/

# Fix permissions if needed
chmod -R u+rw /tmp/clawdbot/

# Restart Moltbot
clawdbot restart
```

---

## Automated Testing Script

For CI/CD or repeated testing, use this automated test script:

```bash
#!/usr/bin/env bash
set -euo pipefail

# test-installer.sh - Automated installer testing

MODE="${1:-gateway}"
PROXY="${2:-caddy}"
DOMAIN="${3:-test.local}"

echo "==> Testing Installer"
echo "    Mode: $MODE"
echo "    Proxy: $PROXY"
echo "    Domain: $DOMAIN"
echo ""

# Run installer
if [[ "$MODE" == "gateway" ]]; then
  PROXY="$PROXY" ./scripts/init.sh "$DOMAIN"
else
  MODE=node ./scripts/init.sh "$DOMAIN"
fi

# Wait for services to start
sleep 10

# Test local gateway
echo "==> Testing local gateway..."
if curl -fsS --max-time 10 http://127.0.0.1:18789 >/dev/null; then
  echo "✅ Local gateway is accessible"
else
  echo "❌ Local gateway is NOT accessible"
  exit 1
fi

# Test public endpoint (gateway mode only)
if [[ "$MODE" == "gateway" ]]; then
  echo "==> Testing public endpoint..."
  if curl -fsS --max-time 10 "https://$DOMAIN" >/dev/null; then
    echo "✅ Public HTTPS endpoint is accessible"
  else
    echo "⚠️  Public HTTPS endpoint is NOT accessible (may need time for TLS)"
  fi
fi

echo ""
echo "✅ All tests passed!"
```

**Usage**:
```bash
# Test Ubuntu/Debian Gateway + Caddy
./test-installer.sh gateway caddy moltbot.example.com

# Test Ubuntu/Debian Gateway + Nginx
./test-installer.sh gateway nginx moltbot.example.com

# Test macOS Node mode
./test-installer.sh node caddy localhost
```

---

## Test Results Template

Use this template to document your test results:

```markdown
## Test Results

**Date**: YYYY-MM-DD
**Tester**: Your Name
**Environment**: Ubuntu 22.04 / Debian 12 / macOS 13

### Scenario 1: Ubuntu/Debian Gateway (Caddy)
- [ ] Installation completed successfully
- [ ] Caddy service running
- [ ] TLS certificate obtained
- [ ] Public HTTPS accessible
- [ ] Logs available
- **Notes**: 

### Scenario 2: Ubuntu/Debian Gateway (Nginx)
- [ ] Installation completed successfully
- [ ] Nginx service running
- [ ] Certbot certificate obtained
- [ ] HTTP to HTTPS redirect working
- [ ] Auto-renewal configured
- **Notes**: 

### Scenario 3: macOS Node Mode
- [ ] Installation completed successfully
- [ ] Node.js 24 installed
- [ ] Gateway accessible locally
- [ ] No proxy configured
- [ ] Logs available
- **Notes**: 

### Issues Encountered
1. 
2. 

### Recommendations
1. 
2. 
```

---

## Next Steps After Testing

1. **Document any issues** found during testing
2. **Update the installer** if bugs are discovered
3. **Add edge case handling** based on test results
4. **Create automated tests** for CI/CD pipeline
5. **Update documentation** with real-world examples

## Contributing Test Results

If you encounter issues or have suggestions, please:

1. Open an issue on GitHub with test results
2. Include full logs and error messages
3. Specify OS version and environment details
4. Provide steps to reproduce

---

**Last Updated**: 2026-01-29
**Tested Platforms**: Ubuntu 22.04, Debian 12, macOS 13
**Installer Version**: v1.0.0 (unified)
