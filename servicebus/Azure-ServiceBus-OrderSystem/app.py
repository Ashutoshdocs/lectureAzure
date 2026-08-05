"""Flask web application: serves the UI and the JSON APIs.

Responsibilities:
  * Render the order form (index) and the live dashboard.
  * Accept new orders, persist them as 'Pending', and enqueue them to
    Azure Service Bus for a worker to process.
  * Expose stats, order list, and live queue metrics for the dashboard.
  * Admin helpers: bulk-generate, clear, retry-failed, and peek.
"""
import json
import random

from flask import Flask, jsonify, render_template, request

import config
import database as db

app = Flask(__name__)

PRODUCTS = ["Laptop", "Phone", "Headphones", "Monitor", "Keyboard",
            "Mouse", "Tablet", "Camera", "Speaker", "Smartwatch"]
CUSTOMERS = ["John", "Aisha", "Ravi", "Meera", "Chen", "Fatima",
             "Diego", "Priya", "Omar", "Sara"]
PRIORITIES = ["Low", "Normal", "High"]


# --- Service Bus helpers -----------------------------------------------------
def _send_to_queue(order: dict) -> None:
    """Push one order onto the Service Bus queue as a JSON message."""
    from azure.servicebus import ServiceBusClient, ServiceBusMessage

    with ServiceBusClient.from_connection_string(
        config.SERVICE_BUS_CONNECTION_STRING
    ) as client:
        with client.get_queue_sender(config.QUEUE_NAME) as sender:
            msg = ServiceBusMessage(
                json.dumps(order),
                subject="order-created",
                application_properties={"priority": order.get("priority", "Normal")},
            )
            sender.send_messages(msg)


def _queue_runtime() -> dict:
    """Live counts from Service Bus (active / dead-letter / scheduled)."""
    from azure.servicebus.management import ServiceBusAdministrationClient

    with ServiceBusAdministrationClient.from_connection_string(
        config.SERVICE_BUS_CONNECTION_STRING
    ) as admin:
        props = admin.get_queue_runtime_properties(config.QUEUE_NAME)
    return {
        "namespace": config.SERVICE_BUS_CONNECTION_STRING.split("//")[-1].split(".")[0]
        if "//" in config.SERVICE_BUS_CONNECTION_STRING else "n/a",
        "queue": config.QUEUE_NAME,
        "active": props.active_message_count,
        "dead_letter": props.dead_letter_message_count,
        "scheduled": props.scheduled_message_count,
    }


# --- Pages -------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html", configured=config.is_connection_configured())


@app.route("/dashboard")
def dashboard():
    return render_template("dashboard.html")


# --- APIs --------------------------------------------------------------------
@app.route("/api/send", methods=["POST"])
def api_send():
    data = request.get_json(force=True, silent=True) or {}
    try:
        customer = (data.get("customer") or "").strip()
        product = (data.get("product") or "").strip()
        quantity = int(data.get("quantity") or 1)
        price = float(data.get("price") or 0)
        priority = data.get("priority") or "Normal"
        if not customer or not product:
            return jsonify(ok=False, error="Customer and product are required."), 400
    except (TypeError, ValueError):
        return jsonify(ok=False, error="Quantity and price must be numbers."), 400

    if not config.is_connection_configured():
        return jsonify(ok=False, error="Service Bus connection string is not set "
                                       "in config.py."), 503

    order_id = db.create_order(customer, product, quantity, price, priority)
    order = {"id": order_id, "customer": customer, "product": product,
             "quantity": quantity, "price": price, "priority": priority}
    try:
        _send_to_queue(order)
    except Exception as exc:  # keep the DB row as Pending; surface the error
        return jsonify(ok=False, error=f"Queued failed: {exc}"), 502

    return jsonify(ok=True, order_id=order_id, message="Order sent to queue.")


@app.route("/api/orders")
def api_orders():
    return jsonify(orders=db.get_orders(limit=50))


@app.route("/api/stats")
def api_stats():
    return jsonify(db.get_stats())


@app.route("/api/queue")
def api_queue():
    if not config.is_connection_configured():
        return jsonify(ok=False, error="Service Bus not configured."), 503
    try:
        return jsonify(ok=True, **_queue_runtime())
    except Exception as exc:
        return jsonify(ok=False, error=str(exc)), 502


@app.route("/api/peek")
def api_peek():
    """Look at up to 10 messages without removing them from the queue."""
    if not config.is_connection_configured():
        return jsonify(ok=False, error="Service Bus not configured."), 503
    from azure.servicebus import ServiceBusClient
    try:
        out = []
        with ServiceBusClient.from_connection_string(
            config.SERVICE_BUS_CONNECTION_STRING
        ) as client:
            with client.get_queue_receiver(config.QUEUE_NAME) as receiver:
                for m in receiver.peek_messages(max_message_count=10):
                    body = str(m)
                    try:
                        body = json.loads(body)
                    except json.JSONDecodeError:
                        pass
                    out.append({"seq": m.sequence_number, "body": body})
        return jsonify(ok=True, messages=out)
    except Exception as exc:
        return jsonify(ok=False, error=str(exc)), 502


@app.route("/api/generate", methods=["POST"])
def api_generate():
    n = int((request.get_json(silent=True) or {}).get("count", 20))
    if not config.is_connection_configured():
        return jsonify(ok=False, error="Service Bus not configured."), 503
    created = 0
    for _ in range(n):
        oid = db.create_order(
            random.choice(CUSTOMERS), random.choice(PRODUCTS),
            random.randint(1, 5), round(random.uniform(10, 2000), 2),
            random.choice(PRIORITIES),
        )
        _send_to_queue({"id": oid})
        created += 1
    return jsonify(ok=True, created=created)


@app.route("/api/retry", methods=["POST"])
def api_retry():
    """Re-queue every Failed order and set it back to Pending."""
    if not config.is_connection_configured():
        return jsonify(ok=False, error="Service Bus not configured."), 503
    failed = db.get_failed_orders()
    for o in failed:
        db.set_status(o["id"], "Pending")
        _send_to_queue({"id": o["id"]})
    return jsonify(ok=True, retried=len(failed))


@app.route("/api/clear", methods=["POST"])
def api_clear():
    db.clear_orders()
    return jsonify(ok=True)


if __name__ == "__main__":
    db.init_db()
    app.run(host=config.FLASK_HOST, port=config.FLASK_PORT, debug=True)
