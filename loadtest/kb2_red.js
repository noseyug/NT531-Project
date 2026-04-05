import http from 'k6/http';
import { sleep, check } from 'k6';

const TARGET_URL = 'http://54.179.226.99/productpage';

export const options = {
  stages: [
    { duration: '10s', target: 10 }, { duration: '30s', target: 10 },
    { duration: '30s', target: 50 }, { duration: '30s', target: 50 },
    { duration: '45s', target: 100 }, { duration: '3m', target: 100 },
    { duration: '10s', target: 20 },  //Reduce users count to a low amount
    { duration: '1m', target: 20 },
    { duration: '10s', target: 0 },
    ],
  thresholds: {
    http_req_failed: ['rate<0.01'], //Expected error rate < 1%
  },
};

export default function () {
  const res = http.get(TARGET_URL);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(2); //Simulate each user will check the site for 2s
}
