# Handover: Frescore Gourmet en Cloudflare

Documento para continuar desde **Claude Code**. Abre una sesión en la carpeta del repo y escribe:

> Lee `docs/HANDOVER-CLOUDFLARE.md` y ejecuta la configuración paso a paso. Pídeme confirmación antes de cada cambio en Cloudflare.

---

## 1. Estado actual (16-oct-2026)

| Elemento | Estado |
|---|---|
| Diseño | Aprobado por Yamil (propuesta C, versión con auditoría aplicada) |
| Repo | `github.com/yamiltejedal/frescore-gourmet`, rama `main` |
| Hosting actual | GitHub Pages: `https://yamiltejedal.github.io/frescore-gourmet/` (temporal) |
| Hosting destino | **Cloudflare Pages**, conectado a GitHub (cada push a `main` publica solo) |
| DNS | Cloudflare (cuenta administrada por Yamil) |
| Dominio | **Pendiente**: lo compra el cliente, a su nombre (es el dueño legal) |
| Analítica | Cloudflare Web Analytics (sin cookies, sin banner) |
| Lighthouse (local, con compresión) | Móvil 99 · Escritorio 100 · SEO 100 · Accesibilidad 96 |

### Estructura del sitio (estático, sin build)

```
index.html          Página única: HTML + CSS + JS en línea
assets/img/         Fotos WebP (versión 1600 px y -800 px para celular), logo SVG, íconos, og-frescore.jpg
assets/video/       frescore-salon.mp4 (sin audio, recortado para no mostrar nombres de stand)
assets/js/          GSAP 3.12.5, ScrollTrigger, Lenis 1.1.13 (copias locales, sin CDN)
_headers            Cabeceras de seguridad y caché (solo aplica en Cloudflare Pages)
robots.txt, sitemap.xml, favicon.ico
scripts/set-domain.sh   Cambia la URL de GitHub Pages por el dominio final
```

### Datos del cliente que el sitio ya usa

- Teléfono / WhatsApp: **829-546-6858** (`wa.me/18295466858`)
- Correo: **frescoregourmet@gmail.com**
- El formulario no tiene backend: arma el mensaje y abre WhatsApp. Tiene campo trampa contra bots (honeypot). No hay claves ni API keys en el código.

---

## 2. Lo que Yamil debe hacer a mano (Claude Code no puede)

1. **Comprar el dominio a nombre del cliente.** Si es `.com.do` / `.do` se registra en NIC.DO. No confirmé que Cloudflare Registrar venda `.do`; verifícalo en https://www.cloudflare.com/tld-policies/. Si es `.com`, Cloudflare Registrar lo vende a precio de costo.
2. **Crear el proyecto de Pages conectado a GitHub** (dashboard → Workers & Pages → Create → Pages → *Connect to Git*):
   - Repo: `yamiltejedal/frescore-gourmet`
   - Nombre del proyecto: `frescore-gourmet`
   - Rama de producción: `main`
   - Framework: *None* · Build command: *(vacío)* · Output directory: `/`
   - ⚠️ **No uses `wrangler pages project create` ni "Direct Upload"**: un proyecto de subida directa no se puede pasar a Git después, y habría que borrarlo y crearlo de nuevo.
3. **Crear un API Token** para Claude Code (My Profile → API Tokens → Create Custom Token), limitado a la cuenta y a la zona del dominio:
   - Account → Cloudflare Pages → Edit
   - Zone → Zone → Read
   - Zone → DNS → Edit
   - Zone → Zone Settings → Edit
   - Zone → Single Redirect / Dynamic Redirect (o "Zone WAF" si no aparece) → Edit

   Guárdalo **solo** en variables de entorno de la terminal, nunca en el repo:
   ```bash
   export CLOUDFLARE_API_TOKEN="..."      # el token
   export CLOUDFLARE_ACCOUNT_ID="..."     # dashboard → panel derecho de cualquier zona
   export FRESCORE_DOMAIN="dominio.com"   # el dominio final, sin https
   ```
4. **Cambiar los nameservers** en el registrador (NIC.DO u otro) por los dos que Cloudflare asigne en el paso 3.2.
5. **Activar Web Analytics** en el proyecto: Workers & Pages → frescore-gourmet → Metrics → Web Analytics → *Enable*. Cloudflare inyecta el script solo, así que en el código `FRESCORE_CF_TOKEN` se queda vacío para no contar doble.

---

## 3. Lo que Claude Code ejecuta (con confirmación)

Todas las llamadas usan `https://api.cloudflare.com/client/v4` con `Authorization: Bearer $CLOUDFLARE_API_TOKEN`. Verifica primero el token:

```bash
curl -s https://api.cloudflare.com/client/v4/user/tokens/verify -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
```

### 3.1 Comprobar que el proyecto de Pages existe y publica

```bash
curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/frescore-gourmet" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
```
Debe mostrar `source.type = github` y un `subdomain` tipo `frescore-gourmet.pages.dev`. Abre esa URL y confirma que carga.

### 3.2 Agregar el dominio como zona

```bash
curl -s -X POST https://api.cloudflare.com/client/v4/zones \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
  --data "{\"name\":\"$FRESCORE_DOMAIN\",\"account\":{\"id\":\"$CLOUDFLARE_ACCOUNT_ID\"},\"type\":\"full\"}"
```
Muestra a Yamil los `name_servers` de la respuesta (paso manual 2.4). Guarda el `id` de la zona como `ZONE_ID`. La zona queda **pendiente** hasta que los nameservers propaguen (de minutos a 24 h). Revisa con `GET /zones/$ZONE_ID` hasta que `status = active`.

### 3.3 Conectar el dominio y el www al proyecto

```bash
for D in "$FRESCORE_DOMAIN" "www.$FRESCORE_DOMAIN"; do
  curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/frescore-gourmet/domains" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" --data "{\"name\":\"$D\"}"
done
```
Con la zona en Cloudflare, los CNAME se crean solos. No crees CNAME a mano antes de este paso (da error 522).

### 3.4 Redirigir www → dominio sin www (301)

Crear una Single Redirect en la fase `http_request_dynamic_redirect` de la zona:
- Si el host es `www.$FRESCORE_DOMAIN` → redirigir a `concat("https://$FRESCORE_DOMAIN", http.request.uri.path)`, código 301, conservando el query string.

Consulta la sintaxis actual en https://developers.cloudflare.com/rules/url-forwarding/single-redirects/ antes de enviarla.

### 3.5 SSL y seguridad de la zona

```bash
for S in "ssl:\"strict\"" "always_use_https:\"on\"" "min_tls_version:\"1.2\"" "automatic_https_rewrites:\"on\""; do
  K="${S%%:*}"; V="${S#*:}"
  curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/$K" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" --data "{\"value\":$V}"
done
```
(`ssl: strict` = "Full (strict)". Pages ya entrega su propio certificado.)

### 3.6 Cambiar las URLs al dominio final y publicar

```bash
scripts/set-domain.sh "$FRESCORE_DOMAIN"
git add -A && git commit -m "Dominio final: $FRESCORE_DOMAIN" && git push origin main
```
El push dispara la publicación en Pages. Revisa que `index.html`, `robots.txt` y `sitemap.xml` ya no mencionen `github.io`.

### 3.7 Correo con el dominio (opcional, gratis)

Email Routing: `contacto@$FRESCORE_DOMAIN` → `frescoregourmet@gmail.com`. Se activa en Email → Email Routing (crea los registros MX/TXT solo). Si el cliente lo quiere, cambia también el correo visible en `index.html`.

---

## 4. Verificación final (checklist)

- [ ] `https://$FRESCORE_DOMAIN` carga con candado; `http://` y `www.` redirigen al dominio sin www (301)
- [ ] `curl -sI https://$FRESCORE_DOMAIN/assets/js/gsap.min.js` muestra `cache-control: public, max-age=31536000, immutable`
- [ ] `curl -sI https://$FRESCORE_DOMAIN/` muestra las cabeceras de `_headers` (nosniff, HSTS, etc.)
- [ ] Vista previa al compartir: https://developers.facebook.com/tools/debug/ (botón *Scrape Again*) y prueba enviando el link por WhatsApp
- [ ] PageSpeed: https://pagespeed.web.dev con el dominio (meta: móvil ≥ 90)
- [ ] Formulario: completar los 3 pasos y confirmar que WhatsApp abre al **829-546-6858** con el resumen
- [ ] Web Analytics recibe visitas (Pages → Metrics)
- [ ] Google Search Console: agregar el dominio (verificación por DNS TXT en Cloudflare) y enviar `sitemap.xml`
- [ ] Apagar GitHub Pages (repo → Settings → Pages → *None*) para no tener el sitio duplicado

---

## 5. Reglas del proyecto para Claude Code

- **Menús**: deben ser exactamente los del material del cliente. No agregar productos que se vean en las imágenes.
- **Nombres de stands**: Sabores de Italia, Delicias Orientales, Bocados Artesanales, Pizza, Barbacoa, Cocina Mexicana, Hojas Frescas, Frutas Frescas, Delicia Tropical, Aroma y Cacao, Menú Gourmet, Dominicano Aquí. Las fotos muestran solo el logo de Frescore, sin nombres de stand.
- **Menú Gourmet**: sin menú por ahora ("Consúltanos…"). Se completa cuando el cliente lo envíe.
- **Sección "Eventos que hablan por nosotros"**: oculta (`hidden`) hasta tener cifras, logos y eventos reales. No inventar testimonios ni cifras.
- **Paleta**: fondo negro (`--night:#050505`), madera, dorado y luz ámbar. Tipografías: Cormorant Garamond (títulos), Jost (texto), Allura (acentos).
- Vanilla HTML/CSS/JS, sin build ni dependencias npm. Probar en móvil (320–412 px) antes de cada push.
- Commits firmados como Claude (`git config user.email noreply@anthropic.com`).

## 6. Pendientes del cliente

1. Dominio (a su nombre)
2. Menú del stand Menú Gourmet
3. Fotos y video **reales** de eventos (hoy todo es generado con IA)
4. Datos para la sección de confianza: cifras, logos de salones o empresas, 2–3 eventos
5. Instagram y Google Business Profile
6. Si quiere medir conversiones (clics a WhatsApp): crear GA4. El código ya envía los eventos `click_whatsapp` y `generate_lead` cuando `gtag` existe.
