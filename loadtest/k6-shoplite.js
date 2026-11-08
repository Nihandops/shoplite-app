// k6 load test: ~25 req/s for 15 minutes (90% browse, 10% orders).
//   k6 run -e BASE_URL=http://<ALB DNS> loadtest/k6-shoplite.js
// Shorter run:  k6 run -e DURATION=3m ...
import http from 'k6/http';
import { check } from 'k6';

const BASE = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '') + '/api';

export const options = {
  scenarios: {
    shoplite: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 25),
      timeUnit: '1s',
      duration: __ENV.DURATION || '15m',
      preAllocatedVUs: 50,
      maxVUs: 200,
    },
  },
  thresholds: { http_req_failed: ['rate<0.5'] },
};

export default function () {
  const r = Math.random();
  if (r < 0.10) {
    const res = http.post(`${BASE}/orders`,
      JSON.stringify({ product_id: 1 + Math.floor(Math.random() * 10), quantity: 1 + Math.floor(Math.random() * 3) }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'POST /orders' } });
    check(res, { 'order 201': (x) => x.status === 201 });
  } else if (r < 0.40) {
    check(http.get(`${BASE}/products`, { tags: { name: 'GET /products' } }), { '200': (x) => x.status === 200 });
  } else {
    const id = 1 + Math.floor(Math.random() * 10);
    check(http.get(`${BASE}/products/${id}`, { tags: { name: 'GET /products/{id}' } }), { '200': (x) => x.status === 200 });
  }
}
