# ── Versions (extracted from Dockerfile, overridable via CLI) ─────────────────
PHP_VERSION  ?= $(shell grep -m1 '^ARG PHP_VERSION='        Dockerfile | cut -d= -f2)
WP_VERSION   ?= $(shell grep -m1 '^ARG WORDPRESS_VERSION='  Dockerfile | cut -d= -f2)

# ── Image settings ───────────────────────────────────────────────────────────
IMAGE        ?= ghcr.io/fabioassuncao/frankenphp-wordpress
DEFAULT_ARCH ?= linux/amd64
TAG          := php$(PHP_VERSION)-wp$(WP_VERSION)

# ── Cache (empty by default, injected by CI) ─────────────────────────────────
CACHE_FROM_STD ?=
CACHE_TO_STD   ?=
CACHE_FROM_SK  ?=
CACHE_TO_SK    ?=

# ── Internal helpers ─────────────────────────────────────────────────────────
_CACHE_STD := $(if $(CACHE_FROM_STD),--cache-from $(CACHE_FROM_STD)) $(if $(CACHE_TO_STD),--cache-to $(CACHE_TO_STD))
_CACHE_SK  := $(if $(CACHE_FROM_SK),--cache-from $(CACHE_FROM_SK)) $(if $(CACHE_TO_SK),--cache-to $(CACHE_TO_SK))

.PHONY: help info build build-sidekick build-all release release-sidekick release-all \
        check check-sidekick check-all

## ── Help ────────────────────────────────────────────────────────────────────

help: ## Show available targets
	@echo "Usage: make <target> [VAR=value ...]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables (override via CLI):"
	@echo "  PHP_VERSION        PHP version         (current: $(PHP_VERSION))"
	@echo "  WP_VERSION         WordPress version   (current: $(WP_VERSION))"
	@echo "  IMAGE              Image name          (current: $(IMAGE))"
	@echo "  DEFAULT_ARCH       Platform            (current: $(DEFAULT_ARCH))"

## ── Info ────────────────────────────────────────────────────────────────────

info: ## Show resolved versions and tags
	@echo "PHP_VERSION  = $(PHP_VERSION)"
	@echo "WP_VERSION   = $(WP_VERSION)"
	@echo "IMAGE        = $(IMAGE)"
	@echo "ARCH         = $(DEFAULT_ARCH)"
	@echo ""
	@echo "Standard tags:"
	@echo "  $(IMAGE):$(TAG)"
	@echo "  $(IMAGE):latest"
	@echo ""
	@echo "Sidekick tags:"
	@echo "  $(IMAGE):$(TAG)-sidekick"
	@echo "  $(IMAGE):latest-sidekick"

## ── Build (local, --load) ───────────────────────────────────────────────────

build: ## Build standard image locally
	docker buildx build \
		--platform $(DEFAULT_ARCH) \
		--build-arg WITH_SIDEKICK=false \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg WORDPRESS_VERSION=$(WP_VERSION) \
		-t $(IMAGE):$(TAG) \
		-t $(IMAGE):latest \
		$(_CACHE_STD) \
		--load .

build-sidekick: ## Build sidekick image locally
	docker buildx build \
		--platform $(DEFAULT_ARCH) \
		--build-arg WITH_SIDEKICK=true \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg WORDPRESS_VERSION=$(WP_VERSION) \
		-t $(IMAGE):$(TAG)-sidekick \
		-t $(IMAGE):latest-sidekick \
		$(_CACHE_SK) \
		--load .

build-all: build build-sidekick ## Build both variants locally

## ── Release (build + push) ──────────────────────────────────────────────────

release: ## Build and push standard image
	docker buildx build \
		--platform $(DEFAULT_ARCH) \
		--build-arg WITH_SIDEKICK=false \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg WORDPRESS_VERSION=$(WP_VERSION) \
		-t $(IMAGE):$(TAG) \
		-t $(IMAGE):latest \
		$(_CACHE_STD) \
		--push .

release-sidekick: ## Build and push sidekick image
	docker buildx build \
		--platform $(DEFAULT_ARCH) \
		--build-arg WITH_SIDEKICK=true \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg WORDPRESS_VERSION=$(WP_VERSION) \
		-t $(IMAGE):$(TAG)-sidekick \
		-t $(IMAGE):latest-sidekick \
		$(_CACHE_SK) \
		--push .

release-all: release release-sidekick ## Build and push both variants

## ── Smoke tests ─────────────────────────────────────────────────────────────

check: ## Smoke-test standard image
	@echo "==> Checking standard image ($(IMAGE):$(TAG))..."
	@docker run --rm $(IMAGE):$(TAG) php -v
	@docker run --rm $(IMAGE):$(TAG) wp --version --allow-root

check-sidekick: ## Smoke-test sidekick image
	@echo "==> Checking sidekick image ($(IMAGE):$(TAG)-sidekick)..."
	@docker run --rm $(IMAGE):$(TAG)-sidekick php -v
	@docker run --rm $(IMAGE):$(TAG)-sidekick wp --version --allow-root

check-all: check check-sidekick ## Smoke-test both variants
