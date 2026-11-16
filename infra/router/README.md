# Self-host the router (bring your own — no demo servers, no keys)

DropOff routing must be open-source and ours. The app talks to
`https://dropoff-api.godfreymoseskalambo.workers.dev/maps/route` (already
deployed), which proxies to an upstream you host. No app changes, no keys in
the binary, works behind plain HTTPS.

Everything below is stock open-source and costs about **US$5–7 / month** for
all of Zambia (graph ~500 MB in RAM). One-time setup ~10 minutes.

---

## Option A — Fly.io (cheapest, one command)

Create a Fly account (card required), `flyctl auth login`, then:

```bash
cd infra/router
fly launch --name dropoff-router --region jnb --no-deploy
fly deploy
curl "https://dropoff-router.fly.dev/route/v1/driving/28.3228,-15.3875;28.2833,-15.4167?overview=false"
```

Then set the DropOff Worker to use it:

```bash
cd workers
npx wrangler secret put ORS_API_KEY    # leave UNSET — enforces self-hosted path
# and edit wrangler.toml [vars]:
#   ROUTER_UPSTREAM = "https://dropoff-router.fly.dev"
# (the Worker uses it automatically once set — see index.ts /maps/route)
npx wrangler deploy
```

The included `fly.toml` runs on shared-cpu-1x / 2 GB with a 60-day volume for
the prebuilt Zambia graph (~450 MB). The container builds the graph once on
first deploy (osrm-extract → osrm-partition → osrm-customize) — allow ~10
minutes cold the first time.

---

## Option B — any VPS with Docker (Hetzner / Contabo / Oracle

```bash
wget https://download.geofabrik.de/africa/zambia-latest.osm.pbf
docker run --rm -v $(pwd):/data osrm/osrm-backend osrm-extract -p /opt/car.lua /data/zambia-latest.osm.pbf
docker run --rm -v $(pwd):/data osrm/osrm-backend osrm-partition /data/zambia-latest.osrm
docker run --rm -v $(pwd):/data osrm/osrm-backend osrm-customize /data/zambia-latest.osrm
docker run -t -i -p 8080:5000 -v $(pwd):/data osrm/osrm-backend osrm-routed --algorithm mld /data/zambia-latest.osrm
```

Put Caddy/nginx in front for HTTPS on `router.dropoff.example.com` — then
point `ROUTER_UPSTREAM` at it as in Option A. Verify:

```bash
curl "https://router.dropoff.example.com/route/v1/driving/28.3228,-15.3875;28.2833,-15.4167?geometries=geojson&steps=true" | jq '.routes[0].geometry.coordinates | length'
```

---

## After enabling

- App → Worker proxy → your router. Turn-by-turn steps, drive distance/duration, road-following line.
- Cache API dedups identical coordinate pairs for 15 min.
- The Worker still answers 502/fallback if your box is down — the app then draws an honest straight line.
- To move off Zambia extract to the 4-country region, mirror `region-zm-zw-mw-mz.osm.pbf` from Geofabrik (1.5 GB) instead; expect ~4 GB RAM.

## Why not Cloudflare Containers / Gemma on Workers?

OSRM is C++; Workers run V8 — it does not fit. Workers Containers needs a
pre-registered account with billing and a locally-built image (no Docker on
this machine). When/if you enable it, this same Dockerfile deploys there
unchanged (`wrangler` + `containers` doc in Cloudflare docs).
