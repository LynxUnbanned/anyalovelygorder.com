# Anya Gorder Portfolio

Static portfolio site for `anyalovelygorder.com`.

## Deploy on Oracle Free Tier Ubuntu 24

Point the DNS `A` record for `anyalovelygorder.com` to the Oracle instance public IP first. If you want `www.anyalovelygorder.com`, point that record at the same server too.

On the server:

```bash
git clone <repo-url> anya-website
cd anya-website
sudo bash deploy.sh
```

The deploy script installs nginx, certbot, rsync, and ufw; syncs the site to `/var/www/anyalovelygorder.com`; issues a Let's Encrypt certificate; configures HTTP to HTTPS redirects; enables nginx and certbot renewal; and adds a systemd restart policy for nginx.

Useful overrides:

```bash
sudo CERTBOT_EMAIL="you@example.com" bash deploy.sh
sudo INCLUDE_WWW=false bash deploy.sh
sudo SKIP_CERT=1 bash deploy.sh
```
