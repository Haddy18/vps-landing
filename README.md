# vps-landing

Índice de proyectos del servidor **`212.227.41.107`**: una landing estática
(HTML + CSS, sin dependencias ni build) que lista lo que hay desplegado en la
máquina. Está en vivo en la raíz → <http://212.227.41.107/>.

| Sitio | Estado | Descripción |
|---|---|---|
| Sistema Solar | en vivo | Simulación Three.js (órbitas reales, texturas procedurales, exportador OBJ). Repo propio: `solar-system-threejs`. |
| Vía Láctea | en vivo | Cielo nocturno real: 119.625 estrellas del catálogo HYG, constelaciones 3D y disco galáctico. Repo propio: `milky-way-threejs`. |
| Tierra en tiempo real | en vivo | Terminador solar por hora UTC, luces de ciudad, nubes y la órbita de la ISS desde su TLE. Repo propio: `earth-threejs`. |
| Receipt | en vivo | Juego LÖVE compilado a WebAssembly (love.js), se juega en el navegador. |
| Admin · bots | en vivo | Panel Nuxt/Express (`/admin`) de los bots: usuarios, respuestas, citas y configuración de los relays. |
| Receipt relay | interno | Bot de Telegram que despacha tareas a GitHub Actions. Sin interfaz web pública. |
| OpenCode relay | interno | Segundo bot con selector de proyectos; comparte máquina con el anterior. |
| Orca | interno | Servidor headless de Orca con emparejamiento, expuesto por Tailscale (no por el puerto público). |

El favicon (Saturno) es el mismo que usa el sitio del Sistema Solar y se
regenera con `python3 scripts/gen-favicons.py` (sin dependencias: puro
`zlib`+`struct`, mismo diseño que `favicon.svg`).

## Cómo se sirve

nginx (vhost `discord-jcd`) apunta la raíz a `/var/www/html/landing/` con
`location /` + `try_files`. Las rutas de cada proyecto se declaran
expresamente: `/solar-system/`, `/milky-way/` y `/earth/` con `alias`, y `/admin` (más
`/api`) con proxy al backend Nuxt/Express del `:3000`. Antes la raíz iba a ese
backend entero; la landing la ocupa ahora y el panel se mantiene bajo su
prefijo.

## Despliegue

Mismo patrón que `solar-system-threejs` y `opencode-runner`: la configuración
vive en **`.env`** (gitignored; plantilla versionada en `.env.example`) y las
credenciales nunca se copian al repo.

```bash
cp .env.example .env      # VPS_HOST, VPS_SSH_PORT, VPS_DEPLOY_PATH… (ver .env.example)
bash scripts/deploy.sh --dry-run   # qué viajaría, sin tocar nada
bash scripts/deploy.sh             # sube, intercambia y verifica la URL
```

- `VPS_DEPLOY_PATH=/var/www/html/landing` — el script solo acepta rutas
  profundas (rechaza `/`, `/root`, `/var`, `/var/www` y `/var/www/html`) y el
  despliegue es atómico (`…​.tmp` + intercambio), así que la landing nunca
  queda a medias.
- Al final verifica que `/`, `/style.css`, `/favicon.svg` y `/version.txt`
  responden 2xx/3xx y que la raíz es HTML con el texto del índice.
- En local el acceso es `VPS_SSH="bash ~/Desktop/vps.sh"` (helper del
  escritorio). En CI `VPS_SSH` va vacío: ssh con la clave `VPS_SSH_KEY` y el
  host key fijado en `.github/known_hosts`.
- **Recarga en vivo**: `deploy.sh` escribe `version.txt` en el servidor y
  `live.js` lo sondea cada 5 s; si cambió, la pestaña abierta se recarga sola,
  así que una tarjeta nueva aparece sin tocar F5 (lo mismo hacen los proyectos
  Three.js con su `js/live.js`).

### Despliegue automático (GitHub Actions)

`.github/workflows/deploy.yml` despliega en cada push a `main` que toque el
contenido del sitio (o a mano con `workflow_dispatch`). Usa los secrets
`VPS_HOST`, `VPS_USER`, `VPS_SSH_PORT`, `VPS_DEPLOY_PATH`, `SITE_URL` y
`VPS_SSH_KEY`; genera el `.env` al vuelo y ejecuta el mismo
`scripts/deploy.sh`. Los despliegues concurrentes se encolan, nunca se
cancelan a medias.

## Estructura

```
index.html               índice de proyectos (tarjetas + iconos SVG inline)
style.css                tema oscuro con estrellas, responsive, sin desbordes
live.js                  recarga la pestaña cuando el VPS publica una versión nueva
favicon.svg/.png/.ico    Saturno (SVG a mano; PNG/ICO generados)
scripts/gen-favicons.py  regenera PNG y ICO a partir del diseño del SVG
scripts/deploy.sh        despliegue atómico con verificación de la URL
.env.example             plantilla de configuración (el .env real está gitignored)
.github/workflows/deploy.yml
.github/known_hosts      host key del VPS fijada (si cambia, la CI falla)
```

## Notas

- El estado (`/admin/login` responde 200; `/`, `/solar-system/`, `/milky-way/`
  y `/earth/` responden 200) se comprueba con `curl` en cada despliegue.
- Si se cambia el host key del VPS, hay que actualizar
  `.github/known_hosts` (ambos bots comparten el mismo servidor).
