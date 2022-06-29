FROM nextcloud:24.0.1-fpm-alpine

# NOTE (Qenupve) - taken from nextcloud/docker GitHub, in .examples/dockerfiles/full/fpm-alpine/Dockerfile
RUN set -ex; \
    \
    apk add --no-cache \
        ffmpeg \
        imagemagick \
        coreutils \
        bash \
        tini \
# TODO (Qenupve) - add logrotate configs
        logrotate \
# NOTE (Qenupve) - these were included in the example Dockerfile, but I don't think I need/want them
#        procps \
#        samba-client \
#        supervisor \
#       libreoffice \
    ;

RUN sed -i 's/pm.max_children =.*/pm.max_children = 120/' /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/pm.start_servers =.*/pm.start_servers = 12/" /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/pm.min_spare_servers =.*/pm.min_spare_servers = 6/" /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/pm.max_spare_servers =.*/pm.max_spare_servers = 18/" /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/;pm.max_requests =.*/pm.max_requests = 1000/" /usr/local/etc/php-fpm.d/www.conf; \
    # NOTE (Qenupve) - crontab in base container runs every 5 minute
    # I want it every minute so it quickly runs my Workflow Scripts on new files
    echo '* * * * * php -f /var/www/html/cron.php' > /var/spool/cron/crontabs/www-data; \
    # TODO (Qenupve): Add logrotate so it doesn't need to be handled on the host.
    echo '* * * * * /opt/image_rename_scan.sh >> /opt/log/image_rename.log 2>&1' >> /var/spool/cron/crontabs/www-data; \
