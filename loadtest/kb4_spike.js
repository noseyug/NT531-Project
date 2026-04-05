import http from 'k6/http';
import { sleep, check } from 'k6';

const TARGET_URL = 'http://54.179.226.99/productpage';

export const options = {
  stages: [
    //Warm-up
    { duration: '30s', target: 50 },
    { duration: '1m',  target: 100 }, //Baseline: 100 users

    //SPIKE 1
    { duration: '10s', target: 400}, //Extreme ramp-up
    { duration: '30s', target: 400 }, // Hold the spike

    //Recovery phase
    { duration: '20s', target: 100 }, //Scale down
    { duration: '1m',  target: 100 }, //System recovers

    //SPIKE 2
    { duration: '10s', target: 400 }, //Ramp-up
    { duration: '30s', target: 400 }, //Hold pressure

    // 5. Cool-down phase
    { duration: '20s', target: 100 }, //Scale down
    { duration: '30s', target: 0 },
  ],
};

export default function () {
  const res = http.get(TARGET_URL, { timeout: '5s' });
  check(res, { 'status is 200': (r) => r.status === 200 })
  sleep(Math.random() * 1 + 1); 
}
