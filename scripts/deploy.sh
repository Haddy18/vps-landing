#!/usr/bin/env bash
# scripts/deploy.sh — sube la landing al VPS (http://212.227.41.107/).
#
# Mismo patrón que solar-system-threejs y opencode-runner: la configuración
# vive en .env (gitignored; plantilla en .env.example) y las credenciales NO
# se copian nunca al repo. El despliegue es atómico (se extrae en <ruta>.tmp
# y se intercambia), así que la landing nunca queda a medias.
#
# Acceso: VPS_SSH (helper del escritorio) o, con VPS_SSH vacío, ssh con clave
# y host key fijado en .github/known_hosts (modo CI).
#
# Uso:
#   bash scripts/deploy.sh            despliega
#   bash scripts/deploy.sh --dry-run  qué viajaría, sin tocar nada
set -euo pipefail
cd "$(dirname "$0")/.."

# .env alimenta solo a este script; quitamos CR por si alguien lo edita en Windows.
if [ -f .env ]; then set -a; . <(tr -d '\r' < .env); set +a; fi

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

missing=""
for var in VPS_HOST VPS_USER VPS_SSH_PORT VPS_DEPLOY_PATH; do
  [ -n "${!var:-}" ] || missing="$missing $var"
done
if [ -n "$missing" ]; then
  echo "ERROR: faltan variables:$missing" >&2
  echo "       cp .env.example .env   # y rellena" >&2
  exit 1
fi

case "$VPS_DEPLOY_PATH" in
  /*) ;;
  *) echo "ERROR: VPS_DEPLOY_PATH debe ser una ruta absoluta del VPS" >&2; exit 1 ;;
esac
case "$VPS_DEPLOY_PATH" in
  "/"|"/root"|"/var"|"/var/www"|"/var/www/html")
    echo "ERROR: ruta de despliegue no permitida: $VPS_DEPLOY_PATH" >&2; exit 1 ;;
esac

# Acceso al VPS: helper local (con credenciales) o ssh con clave (CI).
run_remote() {
  local cmd=$1
  if [ -n "${VPS_SSH:-}" ]; then
    bash -c "$VPS_SSH \"\$@\"" _ "$cmd"
  else
    ssh -i "${VPS_SSH_KEY:-$HOME/.ssh/github-actions-deploy}" \
        -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile=.github/known_hosts \
        -p "$VPS_SSH_PORT" "$VPS_USER@$VPS_HOST" "$cmd"
  fi
}

# Solo la landing viaja; .git, .env y scripts se quedan aquí.
SHIP=(index.html style.css favicon.svg favicon.ico favicon.png)

echo "▸ destino  $VPS_USER@$VPS_HOST:$VPS_SSH_PORT → $VPS_DEPLOY_PATH"
echo "▸ acceso   ${VPS_SSH:-ssh (clave)}"

if $DRY_RUN; then
  echo "▸ dry-run: nothing se envía, esto es lo que viajaría:"
  tar -czf - "${SHIP[@]}" | tar -tzvf - | sed 's/^/    /'
  exit 0
fi

P="$VPS_DEPLOY_PATH"

echo "▸ subiendo…"
tar -czf - "${SHIP[@]}" | run_remote \
  "rm -rf '$P.tmp' && mkdir -p '$P.tmp' && tar -xzf - -C '$P.tmp' && chmod -R a+rX '$P.tmp' && echo '  recibido OK'"

echo "▸ intercambiando…"
run_remote \
  "rm -rf '$P.old'; if [ -d '$P' ]; then mv '$P' '$P.old'; fi; mv '$P.tmp' '$P'; rm -rf '$P.old'; ls '$P'"

# Verificación real: la URL pública tiene que responder como debe.
# SITE_URL=/ (la raíz) o algo tipo http://…/landing/.
if [ -n "${SITE_URL:-}" ]; then
  # /admin/ redirige (302) a su página de login, así que se acepta cualquier
  # 2xx o 3xx: lo que se comprueba es que el backend responde, no su ruta.
  ok=true
  case "$SITE_URL" in
    http://*|https://*) base="${SITE_URL%/}/" ;;
    # ruta relativa ("/" o "/landing/"): se antepone el host del VPS.
    *) base="http://$VPS_HOST${SITE_URL%/}/" ;;
  esac
  for u in "$base" "${base}style.css" "${base}favicon.svg" "${base}admin/"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "$u" || echo 000)
    printf '  %-56s %s\n' "$u" "$code"
    case "$code" in
      [23]??) ;;
      *) ok=false ;;
    esac
  done
  # La raíz tiene que servir ESTA landing, no otra cosa (el tipo y un texto
  # propio del índice). Si nginx sigue apuntando al :3000, se nota aquí.
  ctype=$(curl -s -o /dev/null -w '%{content_type}' --max-time 25 "$base" || echo "")
  case "$ctype" in
    text/html*) ;;
    *) echo "ERROR: la raíz no es HTML (content-type: ${ctype:-vacío})" >&2; ok=false ;;
  esac
  if ! curl -s --max-time 25 "$base" | grep -q "Sistema Solar"; then
    echo "ERROR: la raíz responde, pero no contiene el índice de proyectos" >&2
    ok=false
  fi
  if $ok; then
    echo "✓ desplegado y verificado: $base"
  else
    echo "ERROR: la landing no responde como debe; mira nginx (location / de la raíz)" >&2
    exit 1
  fi
else
  echo "✓ desplegado (sin SITE_URL configurada, verificación omitida)"
fi
