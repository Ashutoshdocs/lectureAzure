#!/usr/bin/env python3
"""
setup_powerbi.py — automates the Power BI side of the Embedded demo.

Phase "admin"  (runs as YOU, token from `az login`; you must be capacity admin
                and admin of the gateway connection created in the UI):
  1. Create workspace WS-SalesEmbedded
  2. Assign it to the Power BI Embedded capacity
  3. Add the service principal app-pbi-embed as workspace Admin
  4. Add app-pbi-embed as a user of the gateway connection (so it can bind)

Phase "sp"     (runs as the service principal app-pbi-embed, MSAL client credentials):
  5. Import SalesDemo.pbix into the workspace (SP becomes semantic model owner)
  6. Bind the semantic model to the gateway connection
  7. Trigger a refresh and wait for it
  8. Write app/.env for the web app

Usage:
  pip install msal requests
  python setup_powerbi.py all --pbix ../powerbi/SalesDemo.pbix
  python setup_powerbi.py admin          # only phase 1-4
  python setup_powerbi.py sp --pbix ...  # only phase 5-8
"""
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import msal
import requests

API = "https://api.powerbi.com/v1.0/myorg"
SCOPE = "https://analysis.windows.net/powerbi/api/.default"
ROOT = Path(__file__).resolve().parent.parent
WORKSPACE_NAME = os.getenv("PBI_WORKSPACE", "WS-SalesEmbedded")
DATASET_NAME = os.getenv("PBI_DATASET", "SalesDemo")
GATEWAY_NAME = os.getenv("PBI_GATEWAY", "gw-pbiemb")
CONNECTION_NAME = os.getenv("PBI_CONNECTION", "conn-sql-salesdemo")


def load_env(path: Path) -> dict:
    env = {}
    if path.exists():
        for line in path.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


CFG = {**load_env(ROOT / "infra/.identity.env"), **load_env(ROOT / "infra/.infra.env")}


# ---------------------------------------------------------------- tokens
def user_token() -> str:
    """Delegated token for the signed-in Azure CLI user."""
    out = subprocess.check_output(
        ["az", "account", "get-access-token",
         "--resource", "https://analysis.windows.net/powerbi/api",
         "--query", "accessToken", "-o", "tsv"], text=True)
    return out.strip()


def sp_token() -> str:
    """App-only token for app-pbi-embed (client credentials)."""
    app = msal.ConfidentialClientApplication(
        CFG["EMBED_APP_ID"],
        authority=f"https://login.microsoftonline.com/{CFG['TENANT_ID']}",
        client_credential=CFG["EMBED_SECRET"])
    res = app.acquire_token_for_client(scopes=[SCOPE])
    if "access_token" not in res:
        sys.exit(f"SP token failed: {res.get('error_description')}\n"
                 "Check the tenant setting 'Service principals can use Fabric APIs' "
                 "includes sg-pbi-embed-sps (README step 6).")
    return res["access_token"]


def call(method, path, token, **kw):
    r = requests.request(method, f"{API}{path}",
                         headers={"Authorization": f"Bearer {token}"}, timeout=120, **kw)
    if r.status_code >= 400:
        sys.exit(f"{method} {path} -> {r.status_code}\n{r.text}")
    return r.json() if r.content and "json" in r.headers.get("Content-Type", "") else {}


# ---------------------------------------------------------------- phase admin
def get_workspace(token):
    ws = call("GET", f"/groups?$filter=name eq '{WORKSPACE_NAME}'", token)["value"]
    return ws[0] if ws else None


def find_capacity_id(token):
    caps = call("GET", "/capacities", token)["value"]
    for c in caps:
        if c["displayName"].lower() == CFG["CAPACITY_NAME"].lower():
            return c["id"]
    sys.exit(f"Capacity {CFG['CAPACITY_NAME']} not visible. Is it running and are you a capacity admin?")


def find_gateway_connection(token):
    for gw in call("GET", "/gateways", token)["value"]:
        for ds in call("GET", f"/gateways/{gw['id']}/datasources", token)["value"]:
            if ds.get("datasourceName") == CONNECTION_NAME:
                return gw["id"], ds["id"]
    sys.exit(f"Gateway connection '{CONNECTION_NAME}' not found — create it in the UI first (README step 7).")


def phase_admin():
    tok = user_token()

    ws = get_workspace(tok)
    if not ws:
        ws = call("POST", "/groups?workspaceV2=True", tok, json={"name": WORKSPACE_NAME})
        print(f"[1] Created workspace {WORKSPACE_NAME} ({ws['id']})")
    else:
        print(f"[1] Workspace exists ({ws['id']})")

    cap_id = find_capacity_id(tok)
    call("POST", f"/groups/{ws['id']}/AssignToCapacity", tok, json={"capacityId": cap_id})
    print(f"[2] Assigned to capacity {CFG['CAPACITY_NAME']} ({cap_id})")

    users = call("GET", f"/groups/{ws['id']}/users", tok)["value"]
    if not any(u.get("identifier") == CFG["EMBED_SP_OID"] for u in users):
        call("POST", f"/groups/{ws['id']}/users", tok, json={
            "identifier": CFG["EMBED_SP_OID"], "principalType": "App",
            "groupUserAccessRight": "Admin"})
    print("[3] app-pbi-embed is workspace Admin")

    gw_id, ds_id = find_gateway_connection(tok)
    ds_users = call("GET", f"/gateways/{gw_id}/datasources/{ds_id}/users", tok)["value"]
    if not any(u.get("identifier") == CFG["EMBED_SP_OID"] for u in ds_users):
        call("POST", f"/gateways/{gw_id}/datasources/{ds_id}/users", tok, json={
            "identifier": CFG["EMBED_SP_OID"], "principalType": "App",
            "datasourceAccessRight": "Read"})
    print(f"[4] app-pbi-embed can use gateway connection {CONNECTION_NAME}")


# ---------------------------------------------------------------- phase sp
def phase_sp(pbix: Path):
    tok = sp_token()
    ws = get_workspace(tok)
    if not ws:
        sys.exit("SP cannot see the workspace — run the admin phase first.")
    ws_id = ws["id"]

    # 5. Import
    with pbix.open("rb") as f:
        imp = call("POST",
                   f"/groups/{ws_id}/imports?datasetDisplayName={DATASET_NAME}"
                   "&nameConflict=CreateOrOverwrite",
                   tok, files={"file": (pbix.name, f, "application/octet-stream")})
    print(f"[5] Import started ({imp['id']})", end="", flush=True)
    while True:
        st = call("GET", f"/groups/{ws_id}/imports/{imp['id']}", tok)
        if st["importState"] == "Succeeded":
            break
        if st["importState"] == "Failed":
            sys.exit(f"\nImport failed: {json.dumps(st, indent=2)}")
        print(".", end="", flush=True)
        time.sleep(3)
    dataset_id = st["datasets"][0]["id"]
    report_id = st["reports"][0]["id"]
    print(f"\n    dataset={dataset_id} report={report_id}")

    # make sure the SP owns the model (needed to bind and refresh)
    call("POST", f"/groups/{ws_id}/datasets/{dataset_id}/Default.TakeOver", tok)

    # 6. Bind to the gateway connection
    gws = call("GET", f"/groups/{ws_id}/datasets/{dataset_id}/Default.DiscoverGateways", tok)["value"]
    if not gws:
        sys.exit("No gateway matches the model's data source. The server/database in the .pbix "
                 "must exactly equal the gateway connection (README step 7), and the admin "
                 "phase must have added the SP as a connection user.")
    gw = gws[0]
    gw_ds = call("GET", f"/gateways/{gw['id']}/datasources", tok)["value"]
    ds_ids = [d["id"] for d in gw_ds if d.get("datasourceName") == CONNECTION_NAME] or [d["id"] for d in gw_ds]
    call("POST", f"/groups/{ws_id}/datasets/{dataset_id}/Default.BindToGateway", tok,
         json={"gatewayObjectId": gw["id"], "datasourceObjectIds": ds_ids})
    print(f"[6] Bound to gateway {gw['name']} connection {CONNECTION_NAME}")

    # 7. Refresh
    call("POST", f"/groups/{ws_id}/datasets/{dataset_id}/refreshes", tok, json={"notifyOption": "NoNotification"})
    print("[7] Refresh started", end="", flush=True)
    while True:
        r = call("GET", f"/groups/{ws_id}/datasets/{dataset_id}/refreshes?$top=1", tok)["value"][0]
        if r["status"] == "Completed":
            break
        if r["status"] == "Failed":
            sys.exit(f"\nRefresh failed: {r.get('serviceExceptionJson')}")
        print(".", end="", flush=True)
        time.sleep(10)
    print(" Completed")

    # 8. Write app/.env
    env = ROOT / "app/.env"
    env.write_text(
        f"TENANT_ID={CFG['TENANT_ID']}\n"
        f"CLIENT_ID={CFG['EMBED_APP_ID']}\n"
        f"CLIENT_SECRET={CFG['EMBED_SECRET']}\n"
        f"WORKSPACE_ID={ws_id}\n"
        f"REPORT_ID={report_id}\n"
        f"DATASET_ID={dataset_id}\n"
        f"RLS_ROLE_REGION=RegionManager\n"
        f"RLS_ROLE_ALL=AllRegions\n"
        f"PORT=3000\n")
    os.chmod(env, 0o600)
    print(f"[8] Wrote {env}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["admin", "sp", "all"])
    ap.add_argument("--pbix", type=Path, default=ROOT / "powerbi/SalesDemo.pbix")
    a = ap.parse_args()
    if a.phase in ("admin", "all"):
        phase_admin()
    if a.phase in ("sp", "all"):
        if not a.pbix.exists():
            sys.exit(f"{a.pbix} not found — build it in Power BI Desktop (README step 8).")
        phase_sp(a.pbix)
