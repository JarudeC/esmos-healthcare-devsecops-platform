import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  vus: 500,
  duration: '10m',
  noConnectionReuse: true,
};

export default function () {
  const resOne = http.get('http://127.0.0.1:8888');
  const resTwo = http.get('http://127.0.0.1:8888/login/index.php');
  const resThree = http.get('http://127.0.0.1:8888/course/');

  check(resOne, { 'home 200': (r) => r.status === 200 });
  check(resTwo, { 'login 200': (r) => r.status === 200 });
  check(resThree, { 'course 200': (r) => r.status === 200 });
}