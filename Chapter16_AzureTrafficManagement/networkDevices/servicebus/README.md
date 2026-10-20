# Azure Service Bus — Order Processing System

A production-style demo: a Flask web app puts orders onto an **Azure Service
Bus** queue, background **workers** consume and process them, results land in
**SQLite**, and a **live dashboard** (Chart.js) shows the whole flow in real
time. Built to run on an **Azure Linux VM**.

> **Full step-by-step commands are in [`RUN_COMMANDS.md`](RUN_COMMANDS.md)** —
> run that file top to bottom.

## What it demonstrates
- Asynchronous producer → queue → consumer messaging
- Competing Consumers (run several `worker.py`)
- Queue buffering under load (`PROCESS_SECONDS=8`)
- Retries and the Dead-Letter Queue (`FAIL_MODE=1`)
- Peek without consuming, live queue metrics, charts, and DB persistence

## Files
```
Azure-ServiceBus-OrderSystem/
├── RUN_COMMANDS.md      ← run these in order
├── app.py               ← Flask web app + JSON APIs
├── worker.py            ← queue consumer (run 1+)
├── config.py            ← connection string, queue, worker knobs
├── database.py          ← SQLite operations
├── init_db.py           ← create the database
├── requirements.txt
├── templates/
│   ├── index.html       ← hero + order form + live cards
│   └── dashboard.html   ← metrics, charts, live table, admin panel
├── static/
│   ├── style.css        ← blue→purple gradient theme
│   └── app.js           ← AJAX, count-up, polling, charts
└── database/            ← orders.db is created here
```

## Quick start (once Service Bus + VM exist)
```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
export SERVICE_BUS_CONNECTION_STRING="Endpoint=sb://...;SharedAccessKey=..."
python init_db.py
python app.py            # Terminal 1  → http://<VM_IP>:5000
python worker.py         # Terminal 2
```

## Configuration knobs (`config.py` or env vars)
| Variable | Purpose | Demo value |
|---|---|---|
| `SERVICE_BUS_CONNECTION_STRING` | queue connection | required |
| `QUEUE_NAME` | queue name | `orders` |
| `PROCESS_SECONDS` | fake work per order | `8` to show buffering |
| `FAIL_MODE` | force failures → DLQ | `1` for failure demo |
