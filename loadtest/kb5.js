import http from 'k6/http';
import { sleep } from 'k6';

// Lấy giá trị từ biến môi trường BASE_URL, nếu không có sẽ dùng localhost
const BASE_URL = __ENV.URL;

export const options = {
  vus: 10,
  duration: '5m'
};

export default function () {
  // 1. Truy cập trang chủ
  http.get(`${BASE_URL}/`);

  // 2. Xem danh sách sản phẩm
  http.get(`${BASE_URL}/api/products`);

  // 3. Thêm vào giỏ hàng
  const payload = JSON.stringify({
    item: { productId: 'OLJCESPC7Z', quantity: 1 }
  });

  const params = {
    headers: { 'Content-Type': 'application/json' },
  };

  http.post(`${BASE_URL}/api/cart`, payload, params);

  sleep(2);
}