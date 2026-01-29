#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Moltbot Unified Installer
# =============================================================================
# Supports:
#   - Modes: gateway (Caddy/Nginx + Moltbot) | node (Moltbot only)
#   - OS: macOS, Debian/Ubuntu, Rocky Linux
#   - Install methods: npm | git
# =============================================================================

MODE="${MODE:-gateway}"
PROXY="${PROXY:-caddy}"
INSTALL_METHOD="${INSTALL_METHOD:-npm}"
GIT_REPO="${GIT_REPO:-https://github.com/cloud-neutral-toolkit/clawdbot.svc.plus.git}"
CLAWDBOT_VERSION="${CLAWDBOT_VERSION:-latest}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
PUBLIC_SCHEME="https"

# =============================================================================
# Detect OS
# =============================================================================
OS_NAME="$(uname -s 2>/dev/null || true)"
OS_FAMILY="unknown"
OS_DISTRO=""

case "$OS_NAME" in
  Darwin)
    OS_FAMILY="darwin"
    ;;
  Linux)
    OS_FAMILY="linux"
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      OS_DISTRO="${ID:-unknown}"
    else
      echo "❌ Unsupported Linux (missing /etc/os-release)."
      exit 1
    fi
    ;;
  *)
    echo "❌ Unsupported OS: ${OS_NAME:-unknown}"
    exit 1
    ;;
esac

# =============================================================================
# Usage
# =============================================================================
usage() {
  cat <<'EOF'
Usage:
  init.sh [domain]

Environment Variables:
  MODE            - Deployment mode: "gateway" (default) or "node"
                    gateway: Caddy/Nginx + Moltbot + Node.js 24
                    node: Moltbot + Node.js 24 only
  PROXY           - Proxy type: "caddy" (default) or "nginx" (gateway mode only)
  INSTALL_METHOD  - "npm" (default) or "git"
  CLAWDBOT_VERSION - Version to install (default: "latest")
  CERTBOT_EMAIL   - Email for Certbot (nginx mode only)
  GIT_REPO        - Git repository URL (git install method only)

Examples:
  # Gateway mode with Caddy (default)
  ./init.sh clawdbot.svc.plus

  # Node mode (no proxy)
  MODE=node ./init.sh clawdbot.svc.plus

  # Gateway mode with Nginx
  PROXY=nginx CERTBOT_EMAIL=admin@example.com ./init.sh clawdbot.svc.plus

  # Install from Git
  INSTALL_METHOD=git ./init.sh clawdbot.svc.plus

Supported OS:
  - macOS (Homebrew required for gateway mode)
  - Debian/Ubuntu
  - Rocky Linux / RHEL-based

EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# =============================================================================
# Validate Parameters
# =============================================================================
MODE="$(tr '[:upper:]' '[:lower:]' <<< "$MODE")"
if [[ "$MODE" != "gateway" && "$MODE" != "node" ]]; then
  echo "❌ Unsupported MODE '$MODE'. Use 'gateway' or 'node'."
  exit 1
fi

PROXY="$(tr '[:upper:]' '[:lower:]' <<< "$PROXY")"
if [[ "$PROXY" != "caddy" && "$PROXY" != "nginx" ]]; then
  echo "❌ Unsupported PROXY '$PROXY'. Use 'caddy' or 'nginx'."
  exit 1
fi

if [[ "$MODE" == "node" && "$PROXY" != "caddy" ]]; then
  echo "⚠️  Node mode does not use a proxy. Ignoring PROXY setting."
fi

INSTALL_METHOD="$(tr '[:upper:]' '[:lower:]' <<< "$INSTALL_METHOD")"
if [[ "$INSTALL_METHOD" != "npm" && "$INSTALL_METHOD" != "git" ]]; then
  echo "❌ Unsupported INSTALL_METHOD '$INSTALL_METHOD'. Use 'npm' or 'git'."
  exit 1
fi

# =============================================================================
# Determine Domain
# =============================================================================
DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  DOMAIN="$(hostname -f 2>/dev/null || true)"
  if [[ -z "$DOMAIN" ]]; then
    DOMAIN="$(hostname 2>/dev/null || true)"
  fi
fi

if [[ -z "$DOMAIN" ]]; then
  echo "❌ Failed to determine domain (hostname). Pass one explicitly."
  exit 1
fi

# =============================================================================
# Helper Functions
# =============================================================================
as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    if [[ "${1:-}" == "-E" ]]; then
      shift
    fi
    "$@"
  else
    sudo "$@"
  fi
}

run_as_user() {
  local user="${SUDO_USER:-$USER}"
  if [[ "$user" == "root" ]]; then
    echo "❌ Run this installer as a non-root user (with sudo available)."
    exit 1
  fi
  sudo -u "$user" -H "$@"
}

# =============================================================================
# Package Installation
# =============================================================================
ensure_packages_debian() {
  local packages=(git curl ca-certificates)
  if [[ "$MODE" == "gateway" ]]; then
    if [[ "$PROXY" == "nginx" ]]; then
      packages+=(nginx certbot python3-certbot-nginx ufw)
    else
      packages+=(caddy ufw)
    fi
  fi
  as_root apt-get update
  as_root apt-get install -y "${packages[@]}"
}

ensure_packages_rocky() {
  local packages=(git curl ca-certificates)
  if [[ "$MODE" == "gateway" ]]; then
    if [[ "$PROXY" == "nginx" ]]; then
      packages+=(nginx certbot python3-certbot-nginx firewalld)
    else
      # Caddy requires EPEL or manual installation on Rocky
      echo "⚠️  Caddy installation on Rocky Linux requires EPEL or manual setup."
      echo "    Installing dependencies only. You may need to install Caddy manually."
      packages+=(firewalld)
    fi
  fi
  as_root dnf install -y epel-release || true
  as_root dnf install -y "${packages[@]}"
}

ensure_packages_darwin() {
  if [[ "$MODE" == "gateway" && "$PROXY" == "nginx" ]]; then
    echo "❌ nginx + Certbot is not supported on macOS. Use PROXY=caddy."
    exit 1
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Homebrew is required on macOS. Install from https://brew.sh"
    exit 1
  fi
  local packages=(git curl)
  if [[ "$MODE" == "gateway" ]]; then
    packages+=(caddy)
  fi
  brew install "${packages[@]}"
}

ensure_packages() {
  case "$OS_FAMILY" in
    darwin)
      ensure_packages_darwin
      ;;
    linux)
      case "$OS_DISTRO" in
        debian|ubuntu)
          ensure_packages_debian
          ;;
        rocky|rhel|centos|fedora)
          ensure_packages_rocky
          ;;
        *)
          echo "❌ Unsupported Linux distribution: $OS_DISTRO"
          exit 1
          ;;
      esac
      ;;
  esac
}

# =============================================================================
# Node.js 24 Installation
# =============================================================================
ensure_node24_debian() {
  local need_install=1
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "${major:-0}" -ge 24 ]]; then
      need_install=0
    fi
  fi
  if [[ "$need_install" -eq 1 ]]; then
    as_root apt-get update
    as_root apt-get install -y curl ca-certificates
    if [[ $(id -u) -eq 0 ]]; then
      curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
    else
      curl -fsSL https://deb.nodesource.com/setup_24.x | as_root -E bash -
    fi
    as_root apt-get install -y nodejs
  fi
}

ensure_node24_rocky() {
  local need_install=1
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "${major:-0}" -ge 24 ]]; then
      need_install=0
    fi
  fi
  if [[ "$need_install" -eq 1 ]]; then
    if [[ $(id -u) -eq 0 ]]; then
      curl -fsSL https://rpm.nodesource.com/setup_24.x | bash -
    else
      curl -fsSL https://rpm.nodesource.com/setup_24.x | as_root -E bash -
    fi
    as_root dnf install -y nodejs
  fi
}

ensure_node24_darwin() {
  local need_install=1
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "${major:-0}" -ge 24 ]]; then
      need_install=0
    fi
  fi
  if [[ "$need_install" -eq 1 ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install node@24 || brew install node
      if brew list node@24 >/dev/null 2>&1; then
        brew link --overwrite --force node@24
      fi
    else
      local arch pkg_name pkg_url pkg_path
      arch="$(uname -m)"
      case "$arch" in
        arm64) arch="arm64" ;;
        x86_64) arch="x64" ;;
        *)
          echo "❌ Unsupported macOS architecture: ${arch}"
          exit 1
          ;;
      esac
      pkg_name="$(curl -fsSL https://nodejs.org/dist/latest-v24.x/ \
        | awk -F\" -v arch="$arch" '/node-v24.*-darwin-/{if ($2 ~ ("-darwin-" arch "\\.pkg$")) {print $2; exit}}')"
      if [[ -z "$pkg_name" ]]; then
        echo "❌ Failed to find Node.js v24 macOS installer."
        exit 1
      fi
      pkg_url="https://nodejs.org/dist/latest-v24.x/${pkg_name}"
      pkg_path="/tmp/${pkg_name}"
      curl -fsSL "$pkg_url" -o "$pkg_path"
      as_root installer -pkg "$pkg_path" -target /
    fi
  fi
}

ensure_node24() {
  case "$OS_FAMILY" in
    darwin)
      ensure_node24_darwin
      ;;
    linux)
      case "$OS_DISTRO" in
        debian|ubuntu)
          ensure_node24_debian
          ;;
        rocky|rhel|centos|fedora)
          ensure_node24_rocky
          ;;
      esac
      ;;
  esac
}

# =============================================================================
# pnpm Installation
# =============================================================================
ensure_pnpm() {
  run_as_user corepack enable
  run_as_user corepack prepare pnpm@latest --activate
}

# =============================================================================
# Firewall Configuration
# =============================================================================
configure_firewall_debian() {
  local ports=(22/tcp 80/tcp 443/tcp 18789/tcp)
  for port in "${ports[@]}"; do
    as_root ufw allow "${port}" >/dev/null
  done
  as_root ufw default allow outgoing >/dev/null
  as_root ufw default deny incoming >/dev/null
  if as_root ufw status | grep -q "Status: inactive"; then
    as_root ufw --force enable >/dev/null
  fi
}

configure_firewall_rocky() {
  local ports=(22 80 443 18789)
  as_root systemctl enable --now firewalld
  for port in "${ports[@]}"; do
    as_root firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null
  done
  as_root firewall-cmd --reload >/dev/null
}

configure_firewall_darwin() {
  # macOS uses application-level firewall
  return 0
}

configure_firewall() {
  if [[ "$MODE" != "gateway" ]]; then
    return 0
  fi
  case "$OS_FAMILY" in
    darwin)
      configure_firewall_darwin
      ;;
    linux)
      case "$OS_DISTRO" in
        debian|ubuntu)
          configure_firewall_debian
          ;;
        rocky|rhel|centos|fedora)
          configure_firewall_rocky
          ;;
      esac
      ;;
  esac
}

# =============================================================================
# Moltbot Installation
# =============================================================================
install_clawdbot_npm() {
  as_root npm install -g "clawdbot@${CLAWDBOT_VERSION}"
}

install_clawdbot_git() {
  local install_dir="/opt/clawdbot-svc-plus"
  if [[ ! -d "$install_dir" ]]; then
    as_root mkdir -p "$install_dir"
    run_as_user git clone "$GIT_REPO" "$install_dir"
  else
    run_as_user git -C "$install_dir" fetch --all --prune
    run_as_user git -C "$install_dir" checkout main
    run_as_user git -C "$install_dir" reset --hard origin/main
  fi
  run_as_user bash -c "cd $install_dir && pnpm install && pnpm build"
  as_root npm install -g "$install_dir"
}

install_clawdbot() {
  if [[ "$INSTALL_METHOD" == "git" ]]; then
    install_clawdbot_git
  else
    install_clawdbot_npm
  fi
}

# =============================================================================
# Moltbot Configuration
# =============================================================================
configure_clawdbot() {
  run_as_user clawdbot onboard --install-daemon
  if [[ "$MODE" == "gateway" ]]; then
    run_as_user clawdbot config set gateway.trustedProxies.0 127.0.0.1
  fi
}

# =============================================================================
# Proxy Configuration
# =============================================================================
configure_nginx() {
  local vhost="/etc/nginx/sites-available/clawdbot-${DOMAIN}.conf"
  if [[ ! -f "$vhost" ]]; then
    cat <<EOF | as_root tee "$vhost" >/dev/null
server {
  listen 80;
  server_name ${DOMAIN};

  location / {
    proxy_pass http://127.0.0.1:18789;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
EOF
  fi
  as_root ln -sf "$vhost" "/etc/nginx/sites-enabled/$(basename "$vhost")"
  as_root nginx -t
  as_root systemctl enable --now nginx
  as_root systemctl reload nginx
}

configure_certbot() {
  local email_args=("--register-unsafely-without-email")
  if [[ -n "$CERTBOT_EMAIL" ]]; then
    email_args=("--email" "$CERTBOT_EMAIL" "--agree-tos" "--no-eff-email")
  fi
  as_root certbot --nginx "${email_args[@]}" --redirect -d "$DOMAIN" || true
}

configure_caddy() {
  local service="/etc/caddy/Caddyfile"
  if [[ "$OS_FAMILY" == "darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      service="$(brew --prefix)/etc/Caddyfile"
    fi
  fi
  cat <<EOF | as_root tee "$service" >/dev/null
${DOMAIN} {
  reverse_proxy 127.0.0.1:18789
}
EOF
  if [[ "$OS_FAMILY" == "darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew services start caddy || brew services restart caddy
    else
      as_root caddy start --config "$service"
    fi
  else
    as_root systemctl enable --now caddy
    as_root systemctl reload caddy
  fi
}

configure_proxy() {
  if [[ "$MODE" != "gateway" ]]; then
    return 0
  fi
  if [[ "$PROXY" == "nginx" ]]; then
    configure_nginx
    configure_certbot
  else
    configure_caddy
  fi
}

# =============================================================================
# Health Checks
# =============================================================================
health_check_url() {
  local url="$1"
  for i in $(seq 1 5); do
    if curl -fsS --max-time 5 --retry 3 --retry-delay 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

run_health_checks() {
  if ! health_check_url http://127.0.0.1:18789; then
    echo "⚠️  Warning: local gateway health check failed."
  fi
  if [[ "$MODE" == "gateway" ]]; then
    local target="${PUBLIC_SCHEME}://${DOMAIN}"
    if ! health_check_url "${target}"; then
      echo "⚠️  Warning: public health check failed for ${target}. TLS might not be active yet."
    fi
  fi
}

# =============================================================================
# Main Execution
# =============================================================================
echo "==> Moltbot Installer"
echo "    Mode: ${MODE}"
echo "    Domain: ${DOMAIN}"
echo "    OS: ${OS_FAMILY} (${OS_DISTRO:-N/A})"
if [[ "$MODE" == "gateway" ]]; then
  echo "    Proxy: ${PROXY}"
fi
echo ""

ensure_packages
ensure_node24
ensure_pnpm
configure_firewall
install_clawdbot
configure_clawdbot
configure_proxy
run_health_checks

cat <<EOF

✅ Done.

EOF

if [[ "$MODE" == "gateway" ]]; then
  cat <<EOF
Gateway is listening on http://127.0.0.1:18789 and proxied via ${PUBLIC_SCHEME}://${DOMAIN}.
Access control and TLS are handled by ${PROXY^^}.

EOF
else
  cat <<EOF
Moltbot is running in node mode (no proxy).
Gateway is listening on http://127.0.0.1:18789.

EOF
fi

cat <<EOF
Configuration:
  - View config: \`clawdbot config get gateway.trustedProxies\`
EOF

if [[ "$OS_FAMILY" == "darwin" ]]; then
  cat <<'EOF'
  - View logs: `tail -f /tmp/clawdbot/clawdbot-gateway.log`
EOF
else
  cat <<'EOF'
  - View logs: `journalctl --user -u clawdbot-gateway --no-pager`
EOF
fi
