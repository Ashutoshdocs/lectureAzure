"""Background worker: the consumer side of the queue.

Run one or more of these in separate terminals to demonstrate the
Competing Consumers pattern:

    python worker.py

Each worker receives a message, marks the order 'Processing', simulates work
for PROCESS_SECONDS, then marks it 'Completed'. With FAIL_MODE=1 it raises an
exception instead of completing, so Service Bus redelivers the message and,
after the max delivery count, moves it to the Dead-Letter Queue.
"""
import json
import os
import socket
import time

from azure.servicebus import ServiceBusClient

import config
import database as db

WORKER_ID = f"{socket.gethostname()}:{os.getpid()}"

# Small ANSI colour helpers for a readable worker screen.
C = dict(reset="\033[0m", dim="\033[2m", green="\033[92m", yellow="\033[93m",
         red="\033[91m", cyan="\033[96m", bold="\033[1m")


def log(msg, colour="reset"):
    print(f"{C.get(colour, '')}{msg}{C['reset']}", flush=True)


def _order_id(message) -> int:
    body = json.loads(str(message))
    return int(body["id"])


def process(order_id: int) -> None:
    db.set_status(order_id, "Processing")
    log(f"  → Processing order #{order_id} ...", "yellow")
    time.sleep(config.PROCESS_SECONDS)

    if config.FAIL_MODE:
        raise RuntimeError("Forced failure (FAIL_MODE=1)")

    db.set_status(order_id, "Completed", stamp_processed=True)
    log(f"  ✓ Saved to database. Order #{order_id} completed.", "green")


def main():
    db.init_db()
    log("=" * 52, "cyan")
    log(f" WORKER {WORKER_ID}", "bold")
    log(f" Queue: {config.QUEUE_NAME}   Delay: {config.PROCESS_SECONDS}s"
        f"   FailMode: {config.FAIL_MODE}", "dim")
    log("=" * 52, "cyan")
    log("Waiting for messages...  (Ctrl+C to stop)\n", "dim")

    with ServiceBusClient.from_connection_string(
        config.SERVICE_BUS_CONNECTION_STRING
    ) as client:
        with client.get_queue_receiver(
            config.QUEUE_NAME, max_wait_time=None
        ) as receiver:
            for message in receiver:
                try:
                    oid = _order_id(message)
                    log(f"Received order  ID {oid}  "
                        f"(delivery #{message.delivery_count + 1})", "cyan")
                    process(oid)
                    receiver.complete_message(message)
                    log("Waiting...\n", "dim")
                except Exception as exc:  # noqa: BLE001
                    log(f"  ✗ Error: {exc}  → abandoning (will retry / DLQ)", "red")
                    try:
                        oid = _order_id(message)
                        db.set_status(oid, "Failed")
                    except Exception:
                        pass
                    # Abandon so Service Bus redelivers; after max delivery
                    # count the broker dead-letters it automatically.
                    receiver.abandon_message(message)
                    log("Waiting...\n", "dim")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("\nWorker stopped.", "dim")
