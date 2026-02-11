#!/usr/bin/env bash
set -e

CONTAINER_ROLE=${CONTAINER_ROLE:-'app'}
APP_ENV=${APP_ENV:-'production'}
CACHE_MODE=${CACHE_MODE:-'cloudflare'}

# Scheduler settings (only used when CONTAINER_ROLE=scheduler)
SCHEDULER_COMMAND=${SCHEDULER_COMMAND:-"wp cron event run --due-now --allow-root --path=/var/www/html"}
SCHEDULER_SLEEP=${SCHEDULER_SLEEP:-"60s"}
SCHEDULER_READY_TIMEOUT=${SCHEDULER_READY_TIMEOUT:-60}

log() {
    echo "[$1] $2"
}

run_scheduler() {
    while true; do
        log "INFO" "Running scheduled tasks."
        # Intentionally unquoted to allow argv-style splitting without shell re-evaluation.
        if $SCHEDULER_COMMAND 2>&1; then
            log "INFO" "Scheduled tasks completed successfully."
        else
            log "ERROR" "Failed to run scheduled tasks"
        fi
        sleep $SCHEDULER_SLEEP
    done
}

trap 'log "INFO" "Stopping container..."; exit 0;' SIGTERM SIGINT

is_dev() {
    [ "$APP_ENV" = "local" ] || [ "$APP_ENV" = "development" ]
}

# -- PHP config: dev vs prod -------------------------------------------------
if is_dev; then
    cp $PHP_INI_DIR/conf.d/opcache-dev.ini.dist $PHP_INI_DIR/conf.d/opcache.ini 2>/dev/null || true
    cp $PHP_INI_DIR/conf.d/error-dev.ini.dist $PHP_INI_DIR/conf.d/error-logging.ini 2>/dev/null || true
    log "INFO" "PHP: development mode (OPcache revalidate, display_errors=On, JIT off)"
else
    cp $PHP_INI_DIR/conf.d/opcache-prod.ini.dist $PHP_INI_DIR/conf.d/opcache.ini 2>/dev/null || true
    cp $PHP_INI_DIR/conf.d/error-prod.ini.dist $PHP_INI_DIR/conf.d/error-logging.ini 2>/dev/null || true
    log "INFO" "PHP: production mode (OPcache optimized, display_errors=Off, JIT tracing)"
fi

# -- Cache Mode: cloudflare vs sidekick --------------------------------------
if [ "$CACHE_MODE" = "sidekick" ]; then
    export CACHE_RESPONSE_CODES=${CACHE_RESPONSE_CODES:-"2XX,404,405"}
    export TTL=${TTL:-6000}
    export BYPASS_PATH_PREFIXES=${BYPASS_PATH_PREFIXES:-"/wp-admin,/wp-json,/wp-content,/wp-includes,/feed"}
    export BYPASS_HOME=${BYPASS_HOME:-"false"}
    export PURGE_PATH=${PURGE_PATH:-"/__cache/purge"}
    log "INFO" "Cache mode: SIDEKICK (full-page cache local ativo)"
    log "INFO" "  CACHE_RESPONSE_CODES=$CACHE_RESPONSE_CODES"
    log "INFO" "  TTL=${TTL}s | BYPASS_HOME=$BYPASS_HOME"
else
    export CACHE_RESPONSE_CODES="000"
    export BYPASS_PATH_PREFIXES="/"
    export BYPASS_HOME="true"
    log "INFO" "Cache mode: CLOUDFLARE (Sidekick desabilitado, Cloudflare gerencia o cache)"
fi

case "$CONTAINER_ROLE" in
    app)
        log "INFO" "Launching FrankenPHP..."
        if [ $# -eq 0 ]; then
            set -- frankenphp run --config /etc/caddy/Caddyfile
        fi
        exec "$@"
        ;;
    scheduler)
        if [ $# -gt 0 ] && [ "$1" != "frankenphp" ]; then
            log "INFO" "Running custom scheduler command: $*"
            exec "$@"
        fi

        log "INFO" "Waiting for WordPress to be ready (timeout: ${SCHEDULER_READY_TIMEOUT}s)..."
        attempts=0
        max_attempts=$((SCHEDULER_READY_TIMEOUT / 5))
        until wp core is-installed --allow-root --path=/var/www/html 2>/dev/null; do
            attempts=$((attempts + 1))
            if [ $attempts -ge $max_attempts ]; then
                log "WARN" "WordPress not ready after ${SCHEDULER_READY_TIMEOUT}s, starting scheduler anyway."
                break
            fi
            sleep 5
        done
        run_scheduler
        ;;
    *)
        log "ERROR" "Could not match the container role \"$CONTAINER_ROLE\""
        exit 1
        ;;
esac
