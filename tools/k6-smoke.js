import http from 'k6/http';
import { check, sleep } from 'k6';

// Read-only smoke/load test for the DropOff Worker.
//
//   k6 run tools/k6-smoke.js
//   k6 run -e BASE_URL=https://dropoff-api.godfreymoseskalambo.workers.dev \
//           -e API_KEY=dof_live_... -e VUS=25 -e DURATION=2m tools/k6-smoke.js
//
// It never creates jobs or payments, so it is safe against production.
const BASE = __ENV.BASE_URL || 'https://dropoff-api.godfreymoseskalambo.workers.dev';
const API_KEY = __ENV.API_KEY || '';
const VUS = Number(__ENV.VUS || 10);
const DURATION = __ENV.DURATION || '1m';

export const options = {
  scenarios: {
    reads: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '20s', target: VUS },
        { duration: DURATION, target: VUS },
        { duration: '10s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<800', 'p(99)<1500'],
  },
};

const headers = API_KEY ? { 'X-API-Key': API_KEY, 'Content-Type': 'application/json' } : {};

export default function () {
  const health = http.get(`${BASE}/health`, { tags: { name: 'health' } });
  check(health, { 'health 200': (r) => r.status === 200 });

  const couriers = http.get(`${BASE}/couriers`, { headers, tags: { name: 'couriers' } });
  check(couriers, {
    'couriers 200': (r) => r.status === 200,
    'couriers json': (r) => String(r.headers['Content-Type'] || '').includes('json'),
  });

  const cities = http.get(`${BASE}/cities`, { headers, tags: { name: 'cities' } });
  check(cities, { 'cities 200': (r) => r.status === 200 });

  const track = http.get(`${BASE}/track/not-a-real-token`, { tags: { name: 'track-404' } });
  check(track, { 'track missing 404': (r) => r.status === 404 });

  sleep(1);
}
