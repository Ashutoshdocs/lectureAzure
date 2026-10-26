#!/usr/bin/env python3
"""
Tiny dependency-free load generator.
Usage: python3 load.py <url> <seconds> <concurrency>
Hits <url>/work?ms=500 and reports which instances/replicas answered.
"""
import json
import sys
import threading
import time
import urllib.request
from collections import Counter

url, duration, workers = sys.argv[1].rstrip("/"), int(sys.argv[2]), int(sys.argv[3])
target = f"{url}/work?ms=500"
stop = time.time() + duration
instances, errors, latencies = Counter(), Counter(), []
lock = threading.Lock()


def worker():
    while time.time() < stop:
        t0 = time.time()
        try:
            with urllib.request.urlopen(target, timeout=30) as r:
                body = json.loads(r.read())
            with lock:
                instances[body["instance"]] += 1
                latencies.append(time.time() - t0)
        except Exception as e:  # noqa: BLE001
            with lock:
                errors[type(e).__name__] += 1


def reporter():
    while time.time() < stop:
        time.sleep(10)
        with lock:
            print(f"  t+{int(duration - (stop - time.time()))}s  distinct instances so far: {len(instances)}", flush=True)


threads = [threading.Thread(target=worker, daemon=True) for _ in range(workers)]
threading.Thread(target=reporter, daemon=True).start()
for t in threads:
    t.start()
for t in threads:
    t.join()

total = sum(instances.values())
latencies.sort()
print(f"\nTarget: {url}")
print(f"Successful requests: {total}   errors: {dict(errors) or 0}")
if latencies:
    print(f"Throughput: {total / duration:.1f} req/s   "
          f"p50: {latencies[len(latencies)//2]*1000:.0f} ms   "
          f"p95: {latencies[int(len(latencies)*0.95)]*1000:.0f} ms")
print(f"Distinct instances that served traffic: {len(instances)}")
for name, n in instances.most_common():
    print(f"  {name:<45} {n} requests")
