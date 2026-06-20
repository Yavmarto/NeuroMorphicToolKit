# Webtop LAN cert + HTTP→HTTPS redirect — 2026-06-11

## Problem
`make webtop` starts the webtop container and the user opens a browser. The
container's HTTPS listener (port 3001) is the only thing mapped to the host
(3030 → 3001). When the request arrives as plain HTTP — either typed as
`http://<host>:3030`, or downgraded by a network/proxy/extension in a LAN
environment — nginx returns:

    HTTP/1.1 400 Bad Request
    The plain HTTP request was sent to HTTPS port

The self-signed cert at `/config/ssl/cert.pem` (CN=*) is not trusted by
browsers on a LAN origin, so even `https://<lan-ip>:3030` shows a
click-through cert warning.

## Goal
End user opens `http://<lan-ip>:3030` (or `https://`, or `localhost`) and
lands in the NMTK desktop with no browser warnings, after one fully
automatic first-run setup.

## Approach
- Install `mkcert` in the webtop image; at container start, generate a cert
  signed by a local CA for `<lan-ip> <hostname> localhost 127.0.0.1` and
  reload nginx. Cert + CA persist in a named volume across rebuilds.
- Add an HTTP→HTTPS redirect listener on container :3000 so plain-HTTP
  requests get a 301 instead of a 400.
- Expose both container ports on the host: 3030 (HTTP, redirects) and 3031
  (HTTPS, direct).
- On the host, extract the CA from the container on first `make webtop` and
  install it to the system trust store + Firefox NSS, no prompts.
- `make webtop-up` prints `http://<lan-ip>:3030` first as the easy URL.

## Files

| File | Action | Purpose |
|---|---|---|
| `Dockerfile.webtop` | Edit | Download mkcert static binary; COPY mkcert init script and http-redirect site into the image. |
| `scripts/webtop-mkcert-startup.sh` | New | Idempotent cert generator. Detects LAN IPs + hostname, regenerates cert+CA only if missing or SANs mismatch, reloads nginx. |
| `scripts/webtop-http-redirect.conf` | New | Tiny nginx server block: 301 from `*:3000` to `https://$host:3001$request_uri`. |
| `scripts/webtop-trust-ca.sh` | New | Extract CA from container via `docker cp`; install to system trust store (Debian/Ubuntu, Fedora/RHEL, macOS) and Firefox NSS via `certutil`. Idempotent. |
| `docker-compose.webtop.yml` | Edit | `ports:` → `${WEBTOP_PORT:-3030}:3000` and `${WEBTOP_HTTPS_PORT:-3031}:3001`. Add `CAROOT=/config/mkcert` env. Add second named volume `nmtk_webtop_certs` for `/config/mkcert` persistence. |
| `Makefile` | Edit | `WEBTOP_HTTPS_PORT ?= 3031`. New target `webtop-trust` calling the script. `webtop-up` auto-calls `webtop-trust` on first run; print block lists `http://<lan-ip>:3030` first then `https://<lan-ip>:3031` and localhost variants. |
| `docs/webtop-browser-desktop.md` | Edit | Document two-port mapping, `webtop-trust` step, SAN coverage, LAN cert behavior. |

Cert SAN coverage: `<lan-ip> <hostname> localhost 127.0.0.1`.

## Untouched
- `scripts/webtop-kiosk-startup.sh`, Flutter build, NMTK app code, selkies
  config, other compose files, suite control plane.

## Restart impact
- User runs `make webtop-down && make webtop` once to rebuild the image
  and trigger first-run cert generation + auto CA trust install.
- Browser tabs on the old URL need to be reloaded.

## Verification
1. `make webtop` builds, starts, generates cert, extracts CA, installs to
   system trust store, reloads nginx.
2. `curl -I http://<lan-ip>:3030/` → `301 Location: https://<lan-ip>:3031/`.
3. `curl -I https://<lan-ip>:3031/` → `200` (no `-k`).
4. `openssl s_client -connect <lan-ip>:3031 -servername <lan-ip> </dev/null
   2>/dev/null | openssl x509 -noout -ext subjectAltName` lists all four
   SANs.
5. Browser: `http://<lan-ip>:3030` → NMTK desktop, no cert warning.

## Fix: nginx SSL block was being deleted (2026-06-11, later same day)

Symptom surfaced in testing: HTTP→HTTPS redirect worked, but the browser
landed on "site can't be reached" after the 301 to `https://<lan-ip>:3031/`.

Root cause: the first version of `scripts/webtop-mkcert-startup.sh` used
`cat > /etc/nginx/sites-enabled/default` to write the redirector block,
which **replaced the entire file**. The upstream `linuxserver/webtop`
default site contains TWO server blocks — HTTP (port 3000, plain, serves
the Selkies frontend + websocket proxy) and SSL (port 3001, serves the
same frontend over TLS). A full-file overwrite kept only the redirector
and deleted the SSL block, so nothing was listening on 3001 inside the
container; docker-proxy then RST'd the browser's HTTPS connection.

Secondary symptom: the script was placed in `/custom-services.d/`, which
s6 treats as a `longrun` (respawned on exit). The script exited after
its work, s6 restarted it within seconds, and it re-issued the cert on
every iteration. The log showed `issuing cert…` repeating every ~30s.
The cert content was fine but the loop was wasteful and made the SAN
idempotency check moot.

Fix:
- `scripts/webtop-mkcert-startup.sh` now splices the redirector into the
  upstream default site in place (awk-based: find the first `server { }`
  block whose `listen` line is `3000 default_server`, replace it; leave
  the SSL block and anything else untouched). Idempotent — re-running
  the splice on already-patched output is a no-op.
- The script ends with `exec sleep infinity` so s6 keeps the longrun
  alive in the foreground and does not respawn it in a tight loop.
- Added a self-check: `curl -ks https://127.0.0.1:3001/` with a WARN log
  if the response is not 2xx, so a future regression in the SSL block
  surfaces immediately in `docker logs`.

Verification (post-fix): `make webtop-down && make webtop` →
- `curl -I http://localhost:3030/` → `301 Location: https://localhost:3031/`
- `curl -k -I https://localhost:3031/` → `200`, body is the Selkies web
  frontend.
- `docker logs` shows a single `[webtop-mkcert] issuing cert…` line on
  the first run, then `[webtop-mkcert] cert already valid for current
  SANs; skipping` on subsequent restarts; no loop.
