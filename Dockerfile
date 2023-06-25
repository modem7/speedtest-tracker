# syntax = docker/dockerfile:latest

FROM serversideup/php:8.1-fpm-nginx AS build

WORKDIR /var/www/html

# Install app dependencies
COPY --link --chown=webuser:webgroup composer.json composer.lock /var/www/html
RUN composer install --no-dev --no-interaction --no-autoloader --no-scripts --no-cache

# Copy app
COPY --link --chown=webuser:webgroup . /var/www/html

# Install app dependencies
RUN <<EOF
    set -xe
    composer dump-autoload --optimize --no-dev --no-interaction --no-cache
    mkdir -p storage/logs
    php artisan optimize:clear
EOF

FROM serversideup/php:8.1-fpm-nginx AS app

# Add /config to allowed directory tree and Enable mixed ssl mode so port 80 or 443 can be used

ENV PHP_OPEN_BASEDIR=$WEBUSER_HOME:/config/:/dev/stdout:/tmp \
    SSL_MODE="mixed"

RUN --mount=type=cache,id=aptcache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=libcache,target=/var/lib/apt,sharing=locked \
    <<EOF
    set -x
    rm -fv /etc/apt/apt.conf.d/docker-clean
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
    # Install Speedtest cli & additional packages
    apt-get update
    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
    apt-get install -y --no-install-recommends \
            speedtest \
            php8.1-pgsql \
            cron

    # Install Cron file
    echo "MAILTO=\"\"\n* * * * * webuser /usr/bin/php /var/www/html/artisan schedule:run" > /etc/cron.d/laravel

    # Clean up 
    apt-get clean
    rm -rf /tmp/* \
           /var/tmp/* \
           /usr/share/doc/*
EOF

# Copy package configs
COPY --link --chmod=755 docker/deploy/etc/s6-overlay/ /etc/s6-overlay/
COPY --link --from=build --chown=webuser:webgroup /var/www/html /var/www/html

VOLUME /config

HEALTHCHECK --timeout=5s --interval=10s --start-period=30s \
  CMD curl -fSs http://localhost/ping || exit 1