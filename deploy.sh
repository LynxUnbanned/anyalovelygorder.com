#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${DOMAIN:-anyalovelygorder.com}"
PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-$DOMAIN}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-anya.gorder@icloud.com}"
SITE_ROOT="${SITE_ROOT:-/var/www/$DOMAIN}"
NGINX_SITE="/etc/nginx/sites-available/$DOMAIN"
NGINX_LINK="/etc/nginx/sites-enabled/$DOMAIN"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDE_WWW="${INCLUDE_WWW:-auto}"
SKIP_CERT="${SKIP_CERT:-0}"
RUN_PUBLIC_HTTP_CHECK="${RUN_PUBLIC_HTTP_CHECK:-1}"

log() {
  printf '\n[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script with sudo: sudo bash $0" >&2
    exit 1
  fi
}

domain_resolves() {
  local name="$1"
  getent ahosts "$name" >/dev/null 2>&1
}

build_domain_args() {
  CERT_DOMAINS=("$PRIMARY_DOMAIN")

  case "$INCLUDE_WWW" in
    1|true|yes)
      CERT_DOMAINS+=("www.$PRIMARY_DOMAIN")
      ;;
    0|false|no)
      ;;
    auto)
      if domain_resolves "www.$PRIMARY_DOMAIN"; then
        CERT_DOMAINS+=("www.$PRIMARY_DOMAIN")
      fi
      ;;
    *)
      echo "INCLUDE_WWW must be auto, true, or false." >&2
      exit 1
      ;;
  esac

  CERTBOT_DOMAIN_ARGS=()
  for cert_domain in "${CERT_DOMAINS[@]}"; do
    CERTBOT_DOMAIN_ARGS+=("-d" "$cert_domain")
  done
}

install_packages() {
  log "Installing nginx, certbot, git-lfs, and rsync"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    certbot \
    curl \
    git \
    git-lfs \
    nginx \
    python3-certbot-nginx \
    rsync
}

fetch_lfs_assets() {
  if git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "Fetching Git LFS assets"
    git -C "$SOURCE_DIR" lfs install --local
    git -C "$SOURCE_DIR" lfs pull
  fi
}

install_site_files() {
  log "Syncing site files to $SITE_ROOT"
  install -d -m 0755 "$SITE_ROOT"
  rsync -a --delete \
    --exclude ".git/" \
    --exclude ".github/" \
    --exclude ".DS_Store" \
    --exclude "deploy.sh" \
    "$SOURCE_DIR/" "$SITE_ROOT/"
  chown -R www-data:www-data "$SITE_ROOT"
  find "$SITE_ROOT" -type d -exec chmod 0755 {} +
  find "$SITE_ROOT" -type f -exec chmod 0644 {} +
}

configure_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    log "Allowing SSH, HTTP, and HTTPS through ufw"
    ufw allow OpenSSH >/dev/null || true
    ufw allow 80/tcp >/dev/null || true
    ufw allow 443/tcp >/dev/null || true
    if ufw status | grep -q "Status: inactive"; then
      ufw --force enable >/dev/null || true
    fi
  fi

  if command -v iptables >/dev/null 2>&1; then
    log "Allowing HTTP and HTTPS through the local iptables firewall"
    install -m 0755 /dev/stdin /usr/local/sbin/anya-site-firewall <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

allow_port() {
  local port="$1"
  local reject_line

  if iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    return
  fi

  reject_line="$(iptables -L INPUT --line-numbers | awk '/REJECT/ { print $1; exit }')"
  if [[ -n "$reject_line" ]]; then
    iptables -I INPUT "$reject_line" -p tcp --dport "$port" -j ACCEPT
  else
    iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
  fi
}

allow_port 80
allow_port 443
EOF
    /usr/local/sbin/anya-site-firewall

    cat >/etc/systemd/system/anya-site-firewall.service <<'EOF'
[Unit]
Description=Allow HTTP and HTTPS before Oracle image firewall rejects
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/anya-site-firewall
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable anya-site-firewall.service >/dev/null || true

    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save >/dev/null || true
    elif command -v iptables-save >/dev/null 2>&1 && [[ -d /etc/iptables ]]; then
      iptables-save >/etc/iptables/rules.v4 || true
    fi
  fi
}

write_bootstrap_nginx() {
  log "Writing temporary HTTP nginx config for certificate validation"
  cat >"$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${CERT_DOMAINS[*]};

    root $SITE_ROOT;
    index index.html;

    location ^~ /.well-known/acme-challenge/ {
        root $SITE_ROOT;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

  ln -sfn "$NGINX_SITE" "$NGINX_LINK"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}

verify_http_reachability() {
  if [[ "$SKIP_CERT" == "1" || "$RUN_PUBLIC_HTTP_CHECK" == "0" ]]; then
    return
  fi

  log "Checking HTTP reachability before requesting the certificate"
  local challenge_dir="$SITE_ROOT/.well-known/acme-challenge"
  local token="deploy-preflight-$(date +%s)"
  local expected="ok-$token"
  local challenge_file="$challenge_dir/$token"
  install -d -m 0755 "$challenge_dir"
  printf '%s\n' "$expected" >"$challenge_file"
  chown -R www-data:www-data "$SITE_ROOT/.well-known"
  chmod 0644 "$challenge_file"

  if [[ "$(curl -fsS --max-time 5 -H "Host: $PRIMARY_DOMAIN" "http://127.0.0.1/.well-known/acme-challenge/$token" || true)" != "$expected" ]]; then
    echo "nginx is not serving the ACME challenge locally. Check: sudo systemctl status nginx" >&2
    exit 1
  fi

  if [[ "$(curl -fsS --max-time 15 "http://$PRIMARY_DOMAIN/.well-known/acme-challenge/$token" || true)" != "$expected" ]]; then
    cat >&2 <<EOF
$PRIMARY_DOMAIN is not reachable from the public internet on port 80.

Open Oracle Cloud ingress before requesting the certificate:
  Source CIDR: 0.0.0.0/0
  IP Protocol: TCP
  Destination Port Range: 80

Also open HTTPS for the finished site:
  Source CIDR: 0.0.0.0/0
  IP Protocol: TCP
  Destination Port Range: 443

In Oracle Cloud Console, edit the VCN security list or network security group attached to this instance's subnet/VNIC. Then rerun:
  cd $SOURCE_DIR
  sudo bash deploy.sh

To skip this preflight after manually confirming access, run:
  sudo RUN_PUBLIC_HTTP_CHECK=0 bash deploy.sh
EOF
    exit 1
  fi
}

issue_certificate() {
  if [[ "$SKIP_CERT" == "1" ]]; then
    log "Skipping certificate issuance because SKIP_CERT=1"
    return
  fi

  if ! domain_resolves "$PRIMARY_DOMAIN"; then
    echo "$PRIMARY_DOMAIN does not resolve in DNS yet. Point it at this server, then rerun this script." >&2
    exit 1
  fi

  log "Requesting or renewing Let's Encrypt certificate for ${CERT_DOMAINS[*]}"
  certbot certonly \
    --webroot \
    --webroot-path "$SITE_ROOT" \
    --non-interactive \
    --agree-tos \
    --email "$CERTBOT_EMAIL" \
    --keep-until-expiring \
    --expand \
    "${CERTBOT_DOMAIN_ARGS[@]}"
}

write_final_nginx() {
  if [[ "$SKIP_CERT" == "1" ]]; then
    log "Leaving HTTP-only nginx config in place because SKIP_CERT=1"
    return
  fi

  log "Writing final HTTPS nginx config"
  cat >"$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${CERT_DOMAINS[*]};

    location ^~ /.well-known/acme-challenge/ {
        root $SITE_ROOT;
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${CERT_DOMAINS[*]};

    root $SITE_ROOT;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    types {
        text/html html htm;
        text/css css;
        application/javascript js;
        application/pdf pdf;
        image/jpeg jpeg jpg;
        image/png png;
        image/webp webp;
        image/svg+xml svg;
        image/x-icon ico;
        font/ttf ttf;
        font/woff woff;
        font/woff2 woff2;
        video/mp4 mp4;
        video/quicktime mov;
        video/webm webm;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(?:css|js|jpg|jpeg|png|webp|svg|ico|ttf|woff|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    location ~* \.(?:mp4|mov|webm|pdf)$ {
        expires 7d;
        add_header Cache-Control "public";
        add_header Accept-Ranges bytes;
        try_files \$uri =404;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
EOF

  nginx -t
  systemctl reload nginx
}

configure_auto_restart() {
  log "Configuring nginx auto-restart and certificate renewal reload"
  install -d -m 0755 /etc/systemd/system/nginx.service.d
  cat >/etc/systemd/system/nginx.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=5s
EOF

  install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
  cat >/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
systemctl reload nginx
EOF
  chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

  systemctl daemon-reload
  systemctl enable nginx
  systemctl enable certbot.timer >/dev/null 2>&1 || true
}

main() {
  require_root
  build_domain_args
  install_packages
  fetch_lfs_assets
  install_site_files
  configure_firewall
  write_bootstrap_nginx
  verify_http_reachability
  issue_certificate
  write_final_nginx
  configure_auto_restart
  log "Deployment complete: https://$PRIMARY_DOMAIN"
}

main "$@"
