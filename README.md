# FrankenPHP WordPress — Base Image

Imagem base para com FrankenPHP, WordPress core, PHP 8.4, WP-CLI, mu-plugins e configurações do servidor.

## Conteudo da imagem

| Componente | Descricao |
|------------|-----------|
| FrankenPHP | Caddy + PHP embarcado (processo unico) |
| WordPress | Core baixado do br.wordpress.org |
| PHP 8.4 | Extensoes: bcmath, exif, gd, intl, mysqli, zip, imagick, opcache |
| WP-CLI | Gerenciamento WordPress via linha de comando |
| Caddy-CBrotli | Compressao Brotli nativa no Caddy |
| Sidekick | Cache full-page em memoria+disco (variante `-sidekick`) |
| mu-plugins | `forceUrlRewrite.php` + `contentCachePurge.php` |

## Variantes

| Tag | Descricao |
|-----|-----------|
| `php8.4-wp6.9.4` | Sem Sidekick — usar com `CACHE_MODE=cloudflare` |
| `php8.4-wp6.9.4-sidekick` | Com Sidekick compilado — usar com `CACHE_MODE=sidekick` |

## Build local

```bash
# Ver versoes e tags resolvidas
make info

# Build standard (sem Sidekick)
make build

# Build com Sidekick
make build-sidekick

# Build ambas variantes
make build-all

# Build + push ambas variantes
make release-all

# Smoke-test ambas variantes
make check-all

# Override de versoes
make build PHP_VERSION=8.3 WP_VERSION=6.8.1
```

### Build args

| ARG | Padrao | Descricao |
|-----|--------|-----------|
| `PHP_VERSION` | `8.4` | Versao do PHP |
| `WORDPRESS_VERSION` | `6.9.4` | Versao do WordPress |
| `WORDPRESS_LOCALE` | `pt_BR` | Locale do WordPress |
| `WPCLI_VERSION` | `2.12.0` | Versao do WP-CLI |
| `WITH_SIDEKICK` | `true` | Compilar Sidekick no binario FrankenPHP |

## CI/CD

O workflow `.github/workflows/docker-publish.yml` delega toda a logica de build ao `Makefile`.

### Triggers

| Evento | Comportamento |
|--------|---------------|
| Push em `main` | `make build-all` + `make verify-all` + `make push-all` — build, verificação de segurança do PHP e push das mesmas imagens verificadas |
| Pull Request para `main` | `make build-all` + `make verify-all` — build e verificação (sem push), para validacao |
| Dispatch manual | Mesmo fluxo do push, com versoes customizaveis (`PHP_VERSION`, `WP_VERSION`) |

O `make verify-all` (`scripts/verify-php.sh`) falha o pipeline se o PHP da imagem (CLI e o embutido no FrankenPHP) for vulnerável ao CVE-2026-109618/CVE-2026-109619 (PHP2Shell). Os builds usam `--pull` para sempre partir da imagem base mais recente.

### Tags geradas

| Evento | Variante Standard | Variante Sidekick |
|--------|-------------------|-------------------|
| Push `main` | `php8.4-wp6.9.4`, `latest` | `php8.4-wp6.9.4-sidekick`, `latest-sidekick` |
| PR | nenhuma (build only) | nenhuma (build only) |
| Manual | idem push (com versoes customizadas) | idem push (com versoes customizadas) |

### Pull das imagens

```bash
# Standard (sem Sidekick)
docker pull ghcr.io/fabioassuncao/frankenphp-wordpress:php8.4-wp6.9.4
docker pull ghcr.io/fabioassuncao/frankenphp-wordpress:latest

# Com Sidekick
docker pull ghcr.io/fabioassuncao/frankenphp-wordpress:php8.4-wp6.9.4-sidekick
docker pull ghcr.io/fabioassuncao/frankenphp-wordpress:latest-sidekick
```

## Estrutura de arquivos

```
.
├── Dockerfile                          # Multi-stage build (builder + final)
├── Makefile                            # Build, release e smoke-test targets
├── entrypoint.sh                       # CONTAINER_ROLE, CACHE_MODE, OPcache
├── .dockerignore
├── config/
│   ├── caddy/
│   │   ├── Caddyfile                   # Configuracao padrao (sem Sidekick)
│   │   └── Caddyfile.sidekick          # Configuracao com wp_cache middleware
│   ├── php/
│   │   ├── php.ini                     # Configuracoes gerais do PHP
│   │   ├── opcache-dev.ini.dist        # OPcache para desenvolvimento
│   │   ├── opcache-prod.ini.dist       # OPcache para producao (JIT tracing)
│   │   ├── error-dev.ini.dist          # Erros visiveis (desenvolvimento)
│   │   └── error-prod.ini.dist         # Erros em log apenas (producao)
│   └── mu-plugins/
│       ├── forceUrlRewrite.php         # Pretty permalinks no FrankenPHP
│       └── contentCachePurge.php       # Purge automatico do cache Sidekick
└── sidekick/
    └── middleware/cache/               # Modulo Go do Sidekick (wp_cache)
        ├── cache.go
        ├── store.go
        ├── writer.go
        ├── go.mod
        └── go.sum
```

## Entrypoint

O `entrypoint.sh` configura o container em runtime:

- **`CONTAINER_ROLE=app`** — Inicia o FrankenPHP
- **`CONTAINER_ROLE=scheduler`** — Executa `wp cron event run --due-now` a cada 60s
- **`APP_ENV=local|development`** — Ativa OPcache em modo dev (revalidate, display_errors)
- **`APP_ENV=production`** — Ativa OPcache otimizado (JIT tracing, sem display_errors)
- **`CACHE_MODE=sidekick`** — Configura variaveis para o cache Sidekick
- **`CACHE_MODE=cloudflare`** — Desabilita Sidekick (Cloudflare gerencia o cache)
