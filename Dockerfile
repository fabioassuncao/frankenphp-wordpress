ARG WORDPRESS_VERSION=6.9.1
ARG WORDPRESS_LOCALE=pt_BR
ARG PHP_VERSION=8.4
ARG USER=www-data
ARG WITH_SIDEKICK=true
ARG WPCLI_VERSION=2.12.0

# -- Stage 1: Builder --------------------------------------------------------
FROM dunglas/frankenphp:builder-php${PHP_VERSION} AS builder

COPY --from=caddy:builder /usr/bin/xcaddy /usr/bin/xcaddy

ARG WITH_SIDEKICK
COPY ./sidekick/middleware/cache ./cache

RUN set -eux; \
  if [ "$WITH_SIDEKICK" = "true" ]; then \
  CGO_ENABLED=1 \
  XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
  CGO_CFLAGS=$(php-config --includes) \
  CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
  xcaddy build \
  --output /usr/local/bin/frankenphp \
  --with github.com/dunglas/frankenphp=./ \
  --with github.com/dunglas/frankenphp/caddy=./caddy/ \
  --with github.com/dunglas/caddy-cbrotli \
  --with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=./cache; \
  else \
  CGO_ENABLED=1 \
  XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
  CGO_CFLAGS=$(php-config --includes) \
  CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
  xcaddy build \
  --output /usr/local/bin/frankenphp \
  --with github.com/dunglas/frankenphp=./ \
  --with github.com/dunglas/frankenphp/caddy=./caddy/ \
  --with github.com/dunglas/caddy-cbrotli; \
  fi

# -- Stage 2: Final image ----------------------------------------------------
FROM dunglas/frankenphp:php${PHP_VERSION} AS base

ENV PHP_INI_SCAN_DIR=$PHP_INI_DIR/conf.d

# 1. System dependencies (rarely change — cached aggressively)
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl ghostscript \
  libcurl4-openssl-dev libjpeg-dev libonig-dev \
  libssl-dev libwebp-dev libxml2-dev libzip-dev \
  unzip zlib1g-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. PHP extensions (rarely change)
RUN install-php-extensions \
  bcmath exif gd intl mysqli zip \
  imagick \
  opcache

# 3. PHP ini configs (entrypoint selects dev/prod at runtime)
RUN cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY ./config/php/php.ini $PHP_INI_DIR/conf.d/wp.ini
COPY ./config/php/opcache-dev.ini.dist $PHP_INI_DIR/conf.d/opcache-dev.ini.dist
COPY ./config/php/opcache-prod.ini.dist $PHP_INI_DIR/conf.d/opcache-prod.ini.dist
COPY ./config/php/error-dev.ini.dist $PHP_INI_DIR/conf.d/error-dev.ini.dist
COPY ./config/php/error-prod.ini.dist $PHP_INI_DIR/conf.d/error-prod.ini.dist

# 4. WordPress core files (changes when WP version bumps)
ARG WORDPRESS_VERSION
ARG WORDPRESS_LOCALE
RUN curl -fsSL "https://br.wordpress.org/wordpress-${WORDPRESS_VERSION}-${WORDPRESS_LOCALE}.zip" \
         -o /tmp/wordpress.zip && \
    unzip -q /tmp/wordpress.zip -d /tmp && \
    mv /tmp/wordpress/* /var/www/html/ && \
    rm -rf /tmp/wordpress /tmp/wordpress.zip

WORKDIR /var/www/html

# 5. Custom FrankenPHP binary (changes when Sidekick/Brotli modules change)
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

# 6. mu-plugins (forceUrlRewrite + contentCachePurge)
COPY ./config/mu-plugins /var/www/html/wp-content/mu-plugins
RUN mkdir -p /var/www/html/wp-content/cache

# WP-CLI (pinned version)
ARG WPCLI_VERSION
RUN curl -fsSL "https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar" \
  -o /usr/local/bin/wp && \
  chmod +x /usr/local/bin/wp

# Caddyfile (select based on WITH_SIDEKICK)
ARG WITH_SIDEKICK
COPY ./config/caddy/Caddyfile /tmp/Caddyfile
COPY ./config/caddy/Caddyfile.sidekick /tmp/Caddyfile.sidekick
RUN if [ "$WITH_SIDEKICK" = "true" ]; then \
  cp /tmp/Caddyfile.sidekick /etc/caddy/Caddyfile; \
  else \
  cp /tmp/Caddyfile /etc/caddy/Caddyfile; \
  fi && rm -f /tmp/Caddyfile /tmp/Caddyfile.sidekick

# Custom entrypoint
COPY ./entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Security: run as non-root
ARG USER
RUN useradd -r -s /usr/sbin/nologin ${USER} 2>/dev/null || true && \
  setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp && \
  chown -R ${USER}:${USER} /data/caddy /config/caddy /var/www/html \
  /usr/local/bin/entrypoint

USER $USER

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
