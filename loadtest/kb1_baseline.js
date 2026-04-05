import http from 'k6/http';
import { sleep, check } from 'k6';

const TARGET_URL = 'http://54.179.226.99/productpage';

export const options = {
  vus: 10,           //10 Users
  duration: '2m',   //Idle for 3 mins
};

export default function () {
  const res = http.get(TARGET_URL);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(3); //Aim to not create ant stress for the services
}
