#!/usr/bin/env bash
# fetch-ci.sh - descarga el Image.gz del ultimo build de la CI (MIUI OC build)
# Uso: ./fetch-ci.sh [repo] [rama]
#   repo  por defecto Danxigod/Jujutsu-kernel (fork con la rama oc-miui)
#   rama  por defecto oc-miui
set -euo pipefail

REPO="${1:-Danxigod/Jujutsu-kernel}"
BRANCH="${2:-oc-miui}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$OUT_DIR"

CRED="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null || true)"
TOKEN="$(printf '%s\n' "$CRED" | grep '^password=' | cut -d= -f2- || true)"
if [ -z "$TOKEN" ]; then
	echo "No hay token de GitHub guardado. Haz 'git credential fill' o exporta GITHUB_TOKEN." >&2
	exit 1
fi
export GITHUB_TOKEN="$TOKEN"

api() { curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$1"; }

RUN_ID="$(api "https://api.github.com/repos/$REPO/actions/runs?branch=$BRANCH&per_page=1" \
	| python -c "import json,sys; print(json.load(sys.stdin)['workflow_runs'][0]['id'])")"

INFO="$(api "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID")"
STATUS="$(printf '%s' "$INFO" | python -c "import json,sys; d=json.load(sys.stdin); print(d['status'], d['conclusion'])")"
echo "== run $RUN_ID  $STATUS"

case "$STATUS" in
*completed*success*)
	echo "== build correcto" ;;
*)
	echo "El build no ha terminado o ha fallado ($STATUS):" >&2
	echo "   https://github.com/$REPO/actions/runs/$RUN_ID" >&2
	exit 2 ;;
esac

ART_ID="$(api "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID/artifacts" \
	| python -c "
import json,sys
for a in json.load(sys.stdin)['artifacts']:
    if a['name'].startswith('Image.gz'):
        print(a['id']); break
")"
[ -n "$ART_ID" ] || { echo "No hay artefacto Image.gz en el run" >&2; exit 4; }

echo "== descargando artefacto $ART_ID"
curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
	"https://api.github.com/repos/$REPO/actions/artifacts/$ART_ID/zip" -o oc-ci.zip

rm -rf oc-ci && mkdir oc-ci && (cd oc-ci && unzip -o ../oc-ci.zip >/dev/null)
cp oc-ci/Image.gz ./Image.gz
rm -rf oc-ci oc-ci.zip

ls -l Image.gz
echo
echo "== version string dentro del kernel:"
zcat Image.gz | strings | grep -m1 "Linux version" || true
echo
echo "Siguiente paso:"
echo "   python scripts/repack-boot.py backup/boot_stock.img Image.gz boot_oc.img"
echo "   bash scripts/flash.sh boot_oc.img"
