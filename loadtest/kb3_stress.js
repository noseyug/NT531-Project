import http from 'k6/http';
import { sleep, check } from 'k6';

const TARGET_URL = 'http://54.179.226.99/productpage';

export const options = {
    //Define failure thresholds
    thresholds: {
        http_req_failed: ['rate<0.05'],     //Error rate must be < 5%
        http_req_duration: ['p(95)<2000'],  //95% of requests must be < 2s
    },
    //Step-load stages to find the exact breaking point
    stages: [
        { duration: '1m', target: 100 }, //Warm-up: 100 users
        { duration: '1m', target: 200 }, //Light load: 200 users
        { duration: '1m', target: 300 }, //Normal load: 300 users
        { duration: '1m', target: 400 }, //Heavy load: 400 users
        { duration: '1m', target: 500 }, //Stress phase: 500 users
        { duration: '1m', target: 600 }, //Extreme stress: 600 users
        { duration: '1m', target: 800 }, //Breaking point: 800 users
        { duration: '30s', target: 0  }, //Cool-down to 0
    ],
};

export default function () {
    const res = http.get(TARGET_URL, { timeout: '5s' });
    
    //Check if the response is successful
    check(res, { 'status is 200': (r) => r.status === 200 });
    
    //Simulate user think time: Random between 1s and 2s
    sleep(Math.random() * 1 + 1); 
}
