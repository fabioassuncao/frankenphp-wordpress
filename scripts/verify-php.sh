#!/usr/bin/env bash
# Fails if the image ships a PHP release vulnerable to
# CVE-2026-109618 / CVE-2026-109619 (PHP2Shell).
# Usage: scripts/verify-php.sh <image>
set -euo pipefail

IMAGE="$1"

CHECK='$fixed = ["8.2" => "8.2.35", "8.3" => "8.3.36", "8.4" => "8.4.27", "8.5" => "8.5.12"];
$series = PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;
$ok = isset($fixed[$series]) ? version_compare(PHP_VERSION, $fixed[$series], ">=") : version_compare(PHP_VERSION, "8.6", ">=");
echo PHP_VERSION, $ok ? " ok" : " VULNERABLE", PHP_EOL;
exit($ok ? 0 : 1);'

status=0
echo "==> $IMAGE"
echo -n "php cli:        " && docker run --rm --entrypoint php "$IMAGE" -r "$CHECK" || status=1
echo -n "frankenphp php: " && docker run --rm --entrypoint frankenphp "$IMAGE" php-cli -r "$CHECK" || status=1

if [ "$status" -ne 0 ]; then
  echo "::error::$IMAGE ships a PHP version vulnerable to CVE-2026-109618/CVE-2026-109619"
fi
exit "$status"
