import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "30s", target: 60 }, // Ramp up to 20 users
    { duration: "1m", target: 60 }, // Stay at 20 users
    { duration: "30s", target: 120 }, // Ramp up to 40 users
    { duration: "1m", target: 120 }, // Stay at 40 users
    { duration: "30s", target: 180 }, // Ramp up to 60 users
    { duration: "1m", target: 180 }, // Stay at 60 users
    { duration: "30s", target: 240 }, // Ramp up to 80 users
    { duration: "1m", target: 240 }, // Stay at 80 users
    { duration: "30s", target: 0 }, // Ramp down to 0
  ],
};

export default function () {
  // Array of valid websites to generate QR codes for
  const validUrls = [
    "https://www.google.com",
    "https://www.github.com",
    "https://www.youtube.com",
    "https://www.wikipedia.org",
    "https://www.amazon.com",
  ];

  // Pick a random valid URL from the array
  const testUrl = validUrls[Math.floor(Math.random() * validUrls.length)];

  const params = {
    headers: {
      "Content-Type": "application/json",
    },
  };

  // Make sure this URL matches your port-forwarded service
  const baseUrl = "http://127.0.0.1:8000";

  // Send URL as a query parameter
  const res = http.post(
    `${baseUrl}/generate-qr/?url=${encodeURIComponent(testUrl)}`,
    null,
    params
  );

  // Add logging to help debug
  console.log(`Testing with URL: ${testUrl}`);
  console.log(`Response status: ${res.status}`);
  if (res.status !== 200) {
    console.log(`Response body: ${res.body}`);
  }

  // Verify the response
  check(res, {
    "status is 200": (r) => r.status === 200,
    "response has qr code": (r) => {
      try {
        const json = r.json();
        return (
          json.qr_code_url !== undefined &&
          json.qr_code_url.includes("s3.amazonaws.com")
        );
      } catch (e) {
        console.log(`Error parsing response: ${e.message}`);
        return false;
      }
    },
  });

  // Shorter sleep time to increase load
  sleep(Math.random() * 0.5); // Sleep between 0-0.5 seconds instead of 1-2 seconds
}
