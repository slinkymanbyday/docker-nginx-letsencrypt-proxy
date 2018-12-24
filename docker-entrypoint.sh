#!/bin/bash

set -e

# Updated on April 17, 2016
# TLS Protocols and cipher suites recommended by Mozilla
# https://wiki.mozilla.org/Security/Server_Side_TLS
# Be sure to escape !'s
declare -A TLS_SETTING_PROTOS;
TLS_SETTING_PROTOS["MODERN"]="TLSv1.2"
TLS_SETTING_PROTOS["INTERMEDIATE"]="TLSv1 TLSv1.1 TLSv1.2"
TLS_SETTING_PROTOS["OLD"]="SSLv3 TLSv1 TLSv1.1 TLSv1.2"

declare -A TLS_SETTING_CIPHER;
TLS_SETTING_CIPHER["MODERN"]="ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256"
TLS_SETTING_CIPHER["INTERMEDIATE"]="ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:\!DSS"
TLS_SETTING_CIPHER["OLD"]="ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:DES-CBC3-SHA:HIGH:SEED:\!aNULL:\!eNULL:\!EXPORT:\!DES:\!RC4:\!MD5:\!PSK:\!RSAPSK:\!aDH:\!aECDH:\!EDH-DSS-DES-CBC3-SHA:\!KRB5-DES-CBC3-SHA:\!SRP"


if [ -n "$PROXY_PORT" ]; then
	export PROXY_PORT_FWD=":$PROXY_PORT"
fi

export PROXY_PORT="${PROXY_PORT:-443}"

# Substitute environment variables for logrotate nginx config
export LOGROTATE_SIZE=${LOGROTATE_SIZE:-10k}
export LOGROTATE_FILE_LIMIT=${LOGROTATE_FILE_LIMIT:-7}
envsubst < /etc/logrotate.d/nginx.tmpl > /etc/logrotate.d/nginx

# set up cron for logrotate
export CRON_SCHEDULE=${CRON_SCHEDULE:-'0 * * * *'}
echo "$CRON_SCHEDULE /usr/sbin/logrotate /etc/logrotate.d/nginx" | crontab -

# Check to see if let's encrypt has certificates already issued to a volume.
# If so, immediately overwrite fake certificates.
if [ -z "$LE_DOMAIN" ] && [ -z "$LE_EMAIL" ] && [ -z "$PROXY_DEST" ]; then
	echo "DOCKER NGINX LET'S ENCRYPT: The env variables LE_DOMAIN, LE_EMAIL, and PROXY_DEST are required for setup.";
	exit 1;
else
	# Generate a local fake cert so nginx will start regardless of the success of LE, if it's configured to run.
	echo "DOCKER NGINX LET'S ENCRYPT: Generate temporary certificate";
	# Parse domains and Proxy destinations
	IFS=',' read -ra DOMAINS <<< "$LE_DOMAIN"
	IFS=',' read -ra DESTINATIONS <<< "$PROXY_DEST"

	openssl req -passout pass: -subj "/C=US/ST=CA/L=San Diego/O=$DOMAINS/OU=TS/CN=$DOMAINS/emailAddress=support@$DOMAINS" -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt

	# Determine TLS_SETTING
	# Check to see if env is set and it's one of MODERN, INTERMEDIATE, or OLD.
	# If check fails, set to MODERN
	if [ ! -z "$TLS_SETTING" ] && ( [ $TLS_SETTING="MODERN" ] || [ $TLS_SETTING="INTERMEDIATE" ] ||  [ $TLS_SETTING="OLD" ]} ] ); then
		echo "DOCKER NGINX LET'S ENCRYPT: TLS_SETTING set to $TLS_SETTING";
	else

		echo "DOCKER NGINX LET'S ENCRYPT: TLS_SETTING not set. Using MODERN";
		TLS_SETTING="MODERN";
	fi

	#GENERATE DHPARAM
	echo "DOCKER NGINX LET'S ENCRYPT: Generating DH parameters";

	# https://github.com/Annixa/docker-nginx-letsencrypt-proxy/issues/3
	# Cache generated dhparams.pem
	TLS_DHPARAMS="/etc/letsencrypt/dhparam.pem"
	if [ -e $TLS_DHPARAMS ]; then
		echo "DOCKER NGINX LET'S ENCRYPT: DHPARAMS already exist";
	else
		openssl dhparam -out "$TLS_DHPARAMS" 2048
	fi
	cp -f $TLS_DHPARAMS /etc/nginx/ssl/dhparam.pem

	echo "DOCKER NGINX LET'S ENCRYPT: render nginx configuration with proxy and destination details details";
	# echo "" > /etc/nginx/conf.d/webapp.conf

	# Updating to support changes in LE
	envsubst '$PROXY_PORT_FWD' < /etc/nginx/sites-available/wellknown.conf > /etc/nginx/conf.d/webapp.conf

	CT=0
	for i in "${DOMAINS[@]}"; do
		# By default, grab the first PROXY_DEST in the array
		THIS_DEST="$DESTINATIONS"
		if [ $CT -lt ${#DESTINATIONS[@]} ]; then
			# Get right VALUE
			THIS_DEST="${DESTINATIONS[$CT]}"
		fi
		envsubst '$PROXY_PORT' < /etc/nginx/sites-available/webapp.1.conf >> /etc/nginx/conf.d/webapp.conf

		echo "ssl_protocols	${TLS_SETTING_PROTOS["$TLS_SETTING"]};" >> /etc/nginx/conf.d/webapp.conf
		echo "ssl_ciphers '${TLS_SETTING_CIPHER["$TLS_SETTING"]}';" >> /etc/nginx/conf.d/webapp.conf

		echo "server_name $i;" >> /etc/nginx/conf.d/webapp.conf
		echo "location / {" >> /etc/nginx/conf.d/webapp.conf


		echo "        proxy_pass          $THIS_DEST;" >> /etc/nginx/conf.d/webapp.conf
		envsubst '$PROXY_PORT' < /etc/nginx/sites-available/webapp.2.conf >> /etc/nginx/conf.d/webapp.conf

		CT=$(($CT + 1))
	done


fi

# start cron
/etc/init.d/cron start

# start up supervisor
/usr/bin/supervisord
