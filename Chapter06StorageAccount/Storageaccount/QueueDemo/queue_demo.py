#!/usr/bin/env python3
"""
Azure Storage Queue demo tool.

One script, several roles:
  send    -> PRODUCER: puts order messages on the queue
  worker  -> CONSUMER: receives, processes and deletes messages
  peek    -> look at messages WITHOUT taking them
  stats   -> approximate message counts for main + poison queue
  clear   -> empty the queue

Auth (in this order):
  1. AZURE_STORAGE_CONNECTION_STRING if set
  2. Otherwise STORAGE_ACCOUNT + DefaultAzureCredential
       - on the VM   -> the VM's managed identity (no secrets anywhere)
       - on laptop   -> your `az login` session
"""
import argparse
import json
import os
import random
import socket
import sys
import time
import uuid
from datetime import datetime, timezone

from azure.core.exceptions import ResourceExistsError
from azure.storage.queue import QueueClient

HOST = socket.gethostname()
ITEMS = ["laptop", "monitor", "keyboard", "mouse", "headset", "webcam", "dock"]
_credential = None


def ts():
    return datetime.now(timezone.utc).strftime("%H:%M:%S")


def log(msg):
    print(f"[{ts()}] [{HOST}] {msg}", flush=True)


def get_queue(name):
    global _credential
    conn = os.getenv("AZURE_STORAGE_CONNECTION_STRING")
    if conn:
        return QueueClient.from_connection_string(conn, name)
    account = os.getenv("STORAGE_ACCOUNT")
    if not account:
        sys.exit("Set STORAGE_ACCOUNT (or AZURE_STORAGE_CONNECTION_STRING) first.")
    if _credential is None:
        from azure.identity import DefaultAzureCredential
        _credential = DefaultAzureCredential()
    return QueueClient(f"https://{account}.queue.core.windows.net", name, credential=_credential)


def ensure(q):
    try:
        q.create_queue()
    except ResourceExistsError:
        pass


def short(msg_id):
    return msg_id[:8]


# ---------------------------------------------------------------- producer
def cmd_send(args, q, _pq):
    for _ in range(args.count):
        order = {
            "orderId": uuid.uuid4().hex[:8],
            "item": random.choice(ITEMS),
            "qty": random.randint(1, 5),
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "producer": HOST,
        }
        q.send_message(json.dumps(order), visibility_timeout=args.delay or None, time_to_live=args.ttl)
        extra = f" (hidden for {args.delay}s - delayed delivery)" if args.delay else ""
        log(f"SENT   order {order['orderId']}  {order['qty']} x {order['item']}{extra}")
    if args.poison:
        q.send_message("this is not valid json {")
        log("SENT   poison message (malformed JSON - the worker will fail on it)")
    log(f"Done. {args.count + (1 if args.poison else 0)} message(s) sent to '{q.queue_name}'.")


# ---------------------------------------------------------------- consumer
def cmd_worker(args, q, pq):
    batch = 1 if args.crash else args.batch
    log(f"Worker started on '{q.queue_name}' | visibility_timeout={args.visibility}s "
        f"| work={args.work}s | max_dequeue={args.max_dequeue} | batch={batch}")
    processed = idle = 0
    try:
        while True:
            got_any = False
            for msg in q.receive_messages(max_messages=batch, visibility_timeout=args.visibility):
                got_any = True
                idle = 0
                mid = short(msg.id)
                log(f"RECV   id={mid} dequeue_count={msg.dequeue_count} "
                    f"-> invisible to other workers for {args.visibility}s")

                if args.crash:
                    log("CRASH  simulating a worker crash: exiting WITHOUT deleting the message.")
                    log(f"       It will reappear in ~{args.visibility}s with dequeue_count={msg.dequeue_count + 1}.")
                    sys.exit(1)

                if msg.dequeue_count > args.max_dequeue:
                    pq.send_message(msg.content)
                    q.delete_message(msg)
                    log(f"POISON id={mid} failed {msg.dequeue_count - 1} times -> moved to '{pq.queue_name}'")
                    continue

                try:
                    order = json.loads(msg.content)
                    log(f"WORK   order {order['orderId']}: {order['qty']} x {order['item']} "
                        f"(from {order.get('producer', '?')})")
                    time.sleep(args.work)
                    q.delete_message(msg)  # uses msg.id + msg.pop_receipt
                    processed += 1
                    log(f"DONE   order {order['orderId']} deleted from queue (processed={processed})")
                except Exception as e:  # noqa: BLE001
                    log(f"FAIL   id={mid} {type(e).__name__}: {e}")
                    log(f"       NOT deleted -> becomes visible again in {args.visibility}s for a retry")

            if not got_any:
                if args.once:
                    log(f"Queue empty. Exiting (processed={processed}).")
                    return
                wait = min(2 ** idle, 16)
                if idle == 0:
                    log("Queue empty - polling with backoff (1s, 2s, 4s ... 16s)")
                idle += 1
                time.sleep(wait)
    except KeyboardInterrupt:
        log(f"Stopped (processed={processed}).")


# ---------------------------------------------------------------- inspection
def cmd_peek(args, q, _pq):
    msgs = list(q.peek_messages(max_messages=min(args.max, 32)))
    if not msgs:
        log("PEEK   no visible messages")
    for m in msgs:
        log(f"PEEK   id={short(m.id)} dequeue_count={m.dequeue_count} content={m.content[:90]}")
    count = q.get_queue_properties().approximate_message_count
    log(f"Visible messages shown: {len(msgs)} | approximate total (visible + hidden): {count}")
    log("Peek does NOT remove or hide messages.")


def cmd_stats(_args, q, pq):
    for queue in (q, pq):
        count = queue.get_queue_properties().approximate_message_count
        log(f"STATS  {queue.queue_name:<20} approx messages: {count}")


def cmd_clear(_args, q, _pq):
    q.clear_messages()
    log(f"Cleared all messages from '{q.queue_name}'.")


def main():
    p = argparse.ArgumentParser(description="Azure Storage Queue demo")
    p.add_argument("--queue", default=os.getenv("QUEUE_NAME", "orders"))
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("send", help="producer: send order messages")
    s.add_argument("--count", type=int, default=5)
    s.add_argument("--poison", action="store_true", help="also send one malformed message")
    s.add_argument("--delay", type=int, default=0, help="seconds before message becomes visible")
    s.add_argument("--ttl", type=int, default=None, help="message time-to-live in seconds")
    s.set_defaults(func=cmd_send)

    w = sub.add_parser("worker", help="consumer: process messages")
    w.add_argument("--visibility", type=int, default=30, help="visibility timeout (s)")
    w.add_argument("--work", type=float, default=2.0, help="simulated processing time (s)")
    w.add_argument("--max-dequeue", type=int, default=3, help="attempts before poison queue")
    w.add_argument("--batch", type=int, default=5, help="messages per receive (max 32)")
    w.add_argument("--crash", action="store_true", help="receive 1 message then exit without deleting")
    w.add_argument("--once", action="store_true", help="exit when queue is empty")
    w.set_defaults(func=cmd_worker)

    pk = sub.add_parser("peek", help="view messages without dequeuing")
    pk.add_argument("--max", type=int, default=10)
    pk.set_defaults(func=cmd_peek)

    sub.add_parser("stats", help="message counts").set_defaults(func=cmd_stats)
    sub.add_parser("clear", help="delete all messages").set_defaults(func=cmd_clear)

    args = p.parse_args()
    q, pq = get_queue(args.queue), get_queue(f"{args.queue}-poison")
    ensure(q)
    ensure(pq)
    args.func(args, q, pq)


if __name__ == "__main__":
    main()
