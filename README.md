# FrankenPHP WordPress — Base Image

Imagem base para o projeto Jornal Pequeno. Contém FrankenPHP, WordPress core, PHP 8.4, WP-CLI, mu-plugins e configurações do servidor. Publicada no GHCR como `ghcr.io/jornalpequeno/frankenphp-wordpress`.

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
| `php8.4-wp6.9.1` | Sem Sidekick — usar com `CACHE_MODE=cloudflare` |
| `php8.4-wp6.9.1-sidekick` | Com Sidekick compilado — usar com `CACHE_MODE=sidekick` |

## Build local

```bash
# Sem Sidekick (padrao para Cloudflare)
docker buildx build \
  --build-arg WITH_SIDEKICK=false \
  -t ghcr.io/jornalpequeno/frankenphp-wordpress:php8.4-wp6.9.1 \
  docker/base/

# Com Sidekick
docker buildx build \
  --build-arg WITH_SIDEKICK=true \
  -t ghcr.io/jornalpequeno/frankenphp-wordpress:php8.4-wp6.9.1-sidekick \
  docker/base/
```

### Build args

| ARG | Padrao | Descricao |
|-----|--------|-----------|
| `PHP_VERSION` | `8.4` | Versao do PHP |
| `WORDPRESS_VERSION` | `6.9.1` | Versao do WordPress |
| `WORDPRESS_LOCALE` | `pt_BR` | Locale do WordPress |
| `WPCLI_VERSION` | `2.12.0` | Versao do WP-CLI |
| `WITH_SIDEKICK` | `true` | Compilar Sidekick no binario FrankenPHP |

## CI/CD

O workflow `.github/workflows/build-base-image.yml` builda e publica automaticamente no GHCR quando:

- Arquivos em `docker/base/` sao alterados na branch `main`
- Dispatch manual via GitHub Actions (permite configurar versoes)

O build gera imagens multi-arch (`linux/amd64` + `linux/arm64`) para ambas as variantes (standard e sidekick).

## Estrutura de arquivos

```
docker/base/
├── Dockerfile                          # Multi-stage build (builder + final)
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
