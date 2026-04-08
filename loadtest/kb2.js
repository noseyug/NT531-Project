import http from 'k6/http';
import { sleep, check } from 'k6';

// k6 sẽ lấy biến từ lệnh 'export URL=...' trong terminal thông qua __ENV.URL
const TARGET_URL = __ENV.URL;

export const options = {
  vus: 20,
  duration: '10m',
};

export default function () {
  // Sử dụng Template Literal (dấu quặc chéo) để đưa biến vào chuỗi
  const res = http.get(`${TARGET_URL}`);

  check(res, {
    'status is 200': (r) => r.status === 200
  });

  sleep(1);
}