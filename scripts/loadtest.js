import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  vus: 500,
  duration: '5m',
  noConnectionReuse: true,
};

export default function () {
  const resOne = http.get('http://127.0.0.1:8888');

  check(resOne, { 'home 200': (r) => r.status === 200 });
  sleep(0.5);
}