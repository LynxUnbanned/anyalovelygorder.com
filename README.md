# Anya Gorder Portfolio

Static portfolio site for `anyalovelygorder.com`.

## Deploy on Oracle Free Tier Ubuntu 24

Point the DNS `A` record for `anyalovelygorder.com` to the Oracle instance public IP first. If you want `www.anyalovelygorder.com`, point that record at the same server too.

In Oracle Cloud, open these ingress rules on the VCN security list or network security group attached to the instance:

| Source CIDR | Protocol | Destination port |
| --- | --- | --- |
| `0.0.0.0/0` | TCP | `80` |
| `0.0.0.0/0` | TCP | `443` |

On the server:

```bash
git clone https://github.com/LynxUnbanned/anyalovelygorder.com.git anya-website
cd anya-website
sudo bash deploy.sh
```

The deploy script installs nginx, certbot, git-lfs, and rsync; pulls Git LFS media assets; opens the local firewall for HTTP/HTTPS; syncs the site to `/var/www/anyalovelygorder.com`; verifies public port 80 reachability; issues a Let's Encrypt certificate; configures HTTP to HTTPS redirects; enables nginx and certbot renewal; and adds a systemd restart policy for nginx.

Useful overrides:

```bash
sudo CERTBOT_EMAIL="you@example.com" bash deploy.sh
sudo INCLUDE_WWW=false bash deploy.sh
sudo SKIP_CERT=1 bash deploy.sh
sudo RUN_PUBLIC_HTTP_CHECK=0 bash deploy.sh
```

If Certbot reports `Timeout during connect`, nginx is running but Oracle Cloud is blocking public inbound HTTP. Add the ingress rules above, then rerun `sudo bash deploy.sh`.
