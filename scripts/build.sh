#!/bin/bash
# scripts/build.sh —— 按 variant 准备 control 并产出 .deb
#
# 用法:
#   ./scripts/build.sh                # 默认 rootless
#   ./scripts/build.sh rootless
#   ./scripts/build.sh roothide       # RELAXIN / roothide
#   ./scripts/build.sh rootful

set -euo pipefail

VARIANT="${1:-${THEOS_PACKAGE_SCHEME:-rootless}}"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT/XiaocanNoAds"

case "$VARIANT" in
  roothide)
    [ -f control.roothide ] || { echo "missing control.roothide"; exit 1; }
    cp -f control.roothide control
    export THEOS_PACKAGE_SCHEME=roothide
    echo "==> Building roothide deb"
    ;;
  rootless|rootful|"")
    [ -f control.rootless ] || { echo "missing control.rootless"; exit 1; }
    cp -f control.rootless control
    if [ "$VARIANT" = "rootful" ]; then
      unset THEOS_PACKAGE_SCHEME
    else
      export THEOS_PACKAGE_SCHEME=rootless
    fi
    echo "==> Building $VARIANT deb"
    ;;
  *)
    echo "Unknown variant: $VARIANT  (rootless|roothide|rootful)"
    exit 2
    ;;
esac

make package FINALPACKAGE=1

echo
echo "==> Done. Output packages:"
ls -la packages/ 2>/dev/null || true