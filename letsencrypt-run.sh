#!/bin/bash

# Only run if this variable is set; local stacks should generate a fake certificate.
# https://github.com/Annixa/docker-nginx-letsencrypt-proxy/issues/4
# Reintroduce LE_ENABLED mode
if [ "$LE_ENABLED" = false ]; then
	echo "DOCKER NGINX LET'S ENCRYPT: Let's Encrypt is disabled according to the environment variable LE_ENABLED. Using self-signed certificates instead.";
	exit 0;
fi

cd /opt/letsencrypt
# https://github.com/Annixa/docker-nginx-letsencrypt-proxy/issues/6
# Add --expand flag to LE: "When adding domains to the LE_DOMAIN env variable, you may be prompted to expand and replace the existing certificate with a new one."
source /root/.bashrc
LE="acme.sh --install-cert --key-file /etc/nginx/ssl/key.pem  --fullchain-file etc/nginx/ssl/cert.pem -w /var/www/challenges"

# Parse domains
IFS=',' read -ra DOMAINS <<< "$LE_DOMAIN"
for i in "${DOMAINS[@]}"; do
    # process "$i"
    LE="$LE -d $i "
done
supervisorctl restart nginx

LE_OUTPUT=$($LE);
LE_EXIT=$?;
echo $LE_EXIT