import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "30s", target: 60 },
    { duration: "1m", target: 120 },
    { duration: "30s", target: 180 },
  ],
};

export default function () {
  // Test frontend webpage load
  const frontendRes = http.get("http://127.0.0.1:51144");
  check(frontendRes, {
    "frontend loaded": (r) => r.status === 200,
  });

  sleep(Math.random() * 0.5);
}
