import http from 'k6/http';
import { sleep, check } from 'k6';

const TARGET_URL = __ENV.URL || 'http://localhost:30080';

export const options = {
  thresholds: {
    http_req_duration: ['p(99)<2000'],
    http_req_failed:   ['rate<0.05'],
  },
  stages: [
    { duration: '2m', target: 10  },
    { duration: '2m', target: 50  },
    { duration: '2m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '2m', target: 300 },
    { duration: '2m', target: 0   },
  ],
};

export default function () {
  const res = http.get(`${TARGET_URL}`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}