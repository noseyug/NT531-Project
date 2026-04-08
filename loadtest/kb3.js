import http from 'k6/http';
import { sleep, check } from 'k6';

const TARGET_URL = __ENV.URL || 'http://localhost:30080';

export const options = {
  stages: [
    { duration: '1m',  target: 10  },
    { duration: '10s', target: 500 },
    { duration: '3m',  target: 500 },
    { duration: '2m',  target: 10  },
    { duration: '1m',  target: 0   },
  ],
};

export default function () {
  const res = http.get(`${TARGET_URL}`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.5);
}