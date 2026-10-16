#!/usr/bin/env bash
# Uso: scripts/set-domain.sh frescoregourmet.com
# Cambia la URL de GitHub Pages por el dominio final en todos los archivos que la usan
# (vista previa al compartir, datos para Google, robots.txt y sitemap.xml).
set -euo pipefail
DOMAIN="${1:?Indica el dominio, ej: frescoregourmet.com}"
OLD="https://yamiltejedal.github.io/frescore-gourmet/"
NEW="https://${DOMAIN}/"
cd "$(dirname "$0")/.."
for f in index.html robots.txt sitemap.xml; do
  sed -i.bak "s#${OLD}#${NEW}#g" "$f" && rm -f "$f.bak"
done
sed -i.bak "s#<lastmod>[0-9-]*</lastmod>#<lastmod>$(date +%F)</lastmod>#" sitemap.xml && rm -f sitemap.xml.bak
echo "Listo. Ocurrencias restantes de github.io: $(grep -c 'github.io' index.html robots.txt sitemap.xml | awk -F: '{s+=$2} END {print s}')"
