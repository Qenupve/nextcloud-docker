FROM nextcloud:24.0.6-fpm-alpine

# NOTE (Qenupve) - taken from nextcloud/docker GitHub, in .examples/dockerfiles/full/fpm-alpine/Dockerfile
RUN set -ex; \
    \
    apk add --no-cache \
        ffmpeg \
        imagemagick \
        coreutils \
        bash \
        logrotate \
# NOTE (Qenupve) - these were included in the example Dockerfile, but I don't think I need/want them
#        procps \
#        samba-client \
#        supervisor \
#       libreoffice \
    ;

COPY logrotate_image_rename.conf /etc/logrotate.d/image_rename.conf

# NOTE: this overwrites the default crontab
COPY crontab_www-data /var/spool/cron/crontabs/www-data
# root crontab for logrotate of image_rename.log
COPY crontab_root /var/spool/cron/crontabs/root

# for first time setup
COPY config_defaults.json /tmp/config.json

RUN sed -i 's/pm.max_children =.*/pm.max_children = 120/' /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/pm.start_servers =.*/pm.start_servers = 12/" /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/pm.min_spare_servers =.*/pm.min_spare_servers = 6/" /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/pm.max_spare_servers =.*/pm.max_spare_servers = 18/" /usr/local/etc/php-fpm.d/www.conf; \
    sed -i "s/;pm.max_requests =.*/pm.max_requests = 1000/" /usr/local/etc/php-fpm.d/www.conf;
