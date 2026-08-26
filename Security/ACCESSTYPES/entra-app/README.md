# Secure Employee Portal — Microsoft Entra ID SSO Demo

A small but realistic enterprise web app that demonstrates **Microsoft Entra ID
(Azure AD) single sign-on** end to end. After a user signs in with their work
account, the portal:

- reads their **real profile** live from **Microsoft Graph** (`/me`),
- shows their **app-role assignments** (from the ID-token `roles` claim),
- exposes a **token-protected API** (`/api/me`, `/api/groups`) to demonstrate
  calling downstream services with the access token,
- displays the **verified ID-token claims** — handy when demoing or debugging SSO,
- supports **proper sign-out** (clears the session *and* the Entra browser session).

It runs behind **nginx (TLS) → gunicorn/Flask**, uses **server-side sessions**
(Entra tokens are too big for a browser cookie), and loads all secrets from a
`.env` file — nothing sensitive is hard-coded.

---

## Architecture

```
Browser ──HTTPS──▶ nginx (TLS termination, :443)
                     │  proxy_pass, X-Forwarded-Proto https, large buffers
                     ▼
                 Flask app (gunicorn or dev server, 127.0.0.1:5000)
                     │  MSAL confidential-client auth-code flow
                     │  server-side session store (./.flask_session)
                     ▼
              Microsoft Entra ID  +  Microsoft Graph
```

---

## What's in the box

```
entra-app/
├── app.py                 # Flask app: auth flow, Graph calls, roles, API, logout
├── config.py              # Reads all settings from environment variables
├── requirements.txt       # Python dependencies
├── .env.example           # Copy to .env and fill in
├── entra-app.service      # systemd unit (gunicorn) for production
├── nginx/
│   └── entra-app.conf     # Reverse proxy: HTTP→HTTPS, TLS, large proxy buffers
├── templates/             # login, dashboard, error pages
├── static/
│   └── style.css          # Portal styling
└── .flask_session/        # Server-side session store (created at runtime)
```

---

## Prerequisites

- An Azure VM (Ubuntu) with a **public IP** and inbound ports **80 + 443** open
  in the Network Security Group.
- Permission to create an **App registration** and **grant admin consent** in
  your Entra tenant.

Throughout, replace `VM_PUBLIC_IP` with your VM's actual public IP (this build was
verified against `20.193.133.137`).

---

## Part 1 — Register the app in Microsoft Entra ID

> **Important:** you need an **App registration**, *not* a service principal from
> `az ad sp create-for-rbac`. An RBAC service principal has no redirect URI and
> **cannot do interactive user sign-in** — using its client ID produces
> `AADSTS700016 (application not found)` or malformed-request errors. Create the
> app through the portal as below.

1. **Entra ID → App registrations → New registration**

   | Field | Value |
   |---|---|
   | Name | `vm-enterprise-app` |
   | Supported account types | *Single tenant* |
   | Redirect URI | **Web** → `https://VM_PUBLIC_IP/getAToken` |

   Click **Register**.

2. From **Overview**, copy the **Application (client) ID** and
   **Directory (tenant) ID** — these go in `.env`.

3. **Certificates & secrets → Client secrets → New client secret.**
   Copy the secret **Value** immediately (shown only once). This goes in `.env`.
   > The secret and the client ID must belong to the **same** app registration.
   > A secret from a different app causes `AADSTS7000215 / invalid_client`.

4. **API permissions** — confirm **Microsoft Graph → Delegated → `User.Read`**
   is listed, then click **Grant admin consent for <your directory>** so the
   **Status** column shows a green *"Granted."*
   > If consent is not granted (and your tenant disables user self-consent),
   > sign-in fails right at the account-picker with *"We couldn't sign you in"*
   > (`AADSTS65001`). Granting admin consent fixes it.

5. *(Optional)* **App roles → Create app role** to demo role-based access, e.g.
   value `Portal.Admin`. Assigned roles appear on the dashboard.

6. *(Optional)* For the **`/api/groups`** endpoint, also add delegated
   `GroupMember.Read.All`, grant admin consent, and add it to `SCOPE` in `.env`.

---

## Part 2 — Restrict access to assigned users (the "enterprise" part)

1. **Entra ID → Enterprise applications → `vm-enterprise-app` → Properties**
   - **Assignment required?** → **Yes** → Save.
   > Note: *Enterprise applications* is a different blade than *App registrations*
   > — same app, two views. Assignment lives on the Enterprise applications side.
2. **Users and groups → Add user/group** → assign the users (and a role if you
   created app roles). Unassigned users are blocked at sign-in (`AADSTS50105`).
3. Make sure the account you test with is a **Member of this same directory**
   (User type = Member, Account status = Enabled). A user from another tenant
   fails with `AADSTS50020` unless invited as a guest.

---

## Part 3 — Set up the VM

```bash
sudo apt update
sudo apt install -y python3-pip python3-venv nginx openssl

# Put the project on the VM (clone/scp/copy) into ~/entra-app, then:
cd ~/entra-app

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt      # includes Flask-Session
```

### Create the configuration

```bash
cp .env.example .env
python -c "import secrets; print('FLASK_SECRET_KEY=' + secrets.token_hex(32))"
```

Edit `.env` and fill in `CLIENT_ID`, `TENANT_ID`, `CLIENT_SECRET`, and the
`FLASK_SECRET_KEY` you just generated. Keep `REDIRECT_PATH=/getAToken`.

```bash
chmod 600 .env
```

**`.env` format notes (these bit us during setup):**
- No quotes needed; use plain values. `CLIENT_ID=<guid>`, not `CLIENT_ID="i"`.
- No trailing spaces and no inline comments on a value line (`source` chokes).
- `CLIENT_ID` must be the real GUID from **this** app registration.

### Create a self-signed TLS certificate

```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key \
  -out /etc/nginx/ssl/nginx.crt
# For "Common Name (CN)", enter your VM_PUBLIC_IP
```

> Self-signed → browser warning (fine for a demo). For production use a
> CA-issued cert (e.g. Let's Encrypt with a real DNS name).

---

## Part 4 — Configure nginx

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo cp nginx/entra-app.conf /etc/nginx/sites-available/entra-app
sudo ln -s /etc/nginx/sites-available/entra-app /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```

The provided config **redirects HTTP→HTTPS**, sets `X-Forwarded-Proto https`
(required so Flask builds `https` redirect URIs), and **enlarges proxy buffers** —
Entra's auth-code callback headers are large and overflow nginx's defaults,
causing `502 upstream sent too big header` without them.

---

## Part 5 — Run the app

### Quick test (development server)

```bash
source venv/bin/activate
set -a && source .env && set +a      # load .env into the shell
python app.py                        # 127.0.0.1:5000, behind nginx
```

Browse to `https://VM_PUBLIC_IP/`, accept the cert warning, sign in.

> Restarting a `python app.py` in the foreground reloads `.env`; if you change
> `.env` (e.g. after rotating the secret), stop and restart it. Editing during an
> active sign-in can rotate `FLASK_SECRET_KEY` and invalidate the session.

### Production (gunicorn + systemd)

1. Edit `entra-app.service` — set `User`, `WorkingDirectory`, and paths for your
   VM (defaults assume user `azureuser` and `/home/azureuser/entra-app`).
2. Make the session store writable by that user:
   ```bash
   mkdir -p /home/azureuser/entra-app/.flask_session
   sudo chown -R azureuser:azureuser /home/azureuser/entra-app/.flask_session
   ```
3. Install and start:
   ```bash
   sudo cp entra-app.service /etc/systemd/system/entra-app.service
   sudo systemctl daemon-reload
   sudo systemctl enable --now entra-app
   sudo systemctl status entra-app --no-pager
   ```

nginx proxies `https://VM_PUBLIC_IP/` → gunicorn on `127.0.0.1:5000`.

---

## How the sign-in flow works

1. User hits `/` → not signed in → **login page**.
2. `/login` builds the Entra authorization URL (with an anti-CSRF `state`) and
   redirects to Microsoft.
3. User authenticates; Entra checks **assignment** + **consent** and redirects to
   `/getAToken?code=…&state=…`.
4. The app verifies `state`, exchanges `code` for tokens (MSAL), and stores the
   ID-token claims + MSAL token cache **server-side** (only a small session id
   goes in the cookie). Then redirects to `/dashboard`.
5. The dashboard calls **Microsoft Graph** with the access token for the live
   profile; roles come from the ID token.
6. `/logout` clears the session and signs the user out at Entra.

> **Why server-side sessions:** Entra ID tokens + MSAL cache are ~5–6 KB, over the
> browser's ~4 KB cookie limit. Storing them in the cookie makes the browser
> silently drop it → no session → `/dashboard → /login` **redirect loop**
> (`ERR_TOO_MANY_REDIRECTS`). `Flask-Session` with `SESSION_TYPE="filesystem"`
> keeps the payload on the server and fixes this.

---

## Endpoints

| Route | Purpose |
|---|---|
| `/` | Landing / login gate |
| `/login` | Start Entra sign-in |
| `/getAToken` | OAuth redirect handler (`REDIRECT_PATH`) |
| `/dashboard` | Authenticated portal view |
| `/api/me` | Protected JSON — the user's Graph profile |
| `/api/groups` | Protected JSON — the user's group memberships |
| `/logout` | Sign out (session + Entra) |
| `/healthz` | Liveness probe |

---

## Troubleshooting (all seen during this build)

| Symptom | Cause | Fix |
|---|---|---|
| `AADSTS700016 application not found` | Using an RBAC service-principal client ID, not an app registration | Create an App registration (Part 1); use its client ID |
| `AADSTS90014 required field 'request'` | Malformed/empty auth request, or stale login tab / back button | Fix `.env` values; start fresh from `https://VM_PUBLIC_IP/` |
| `502 upstream sent too big header` | Entra callback headers exceed nginx buffers | Add the `proxy_buffer*` lines (in provided nginx conf) |
| "We couldn't sign you in" at account picker | Admin consent not granted | API permissions → **Grant admin consent** for `User.Read` |
| "We couldn't sign you in" | User not assigned (Assignment required = Yes) | Enterprise applications → Users and groups → add the user |
| `AADSTS50011 redirect URI mismatch` | Redirect URI ≠ `https://VM_PUBLIC_IP/getAToken` | Match it exactly in App registration → Authentication |
| `AADSTS7000215 / invalid_client` | Wrong/expired client secret in `.env` | New secret on the correct app; update `.env`; restart |
| `ERR_TOO_MANY_REDIRECTS` (dashboard↔login) | Session too big for cookie / stale cookie | Server-side sessions (built in); clear site cookies / use Incognito |
| `502 connection refused` | App not running on :5000 | Start it; `sudo ss -ltnp | grep 5000` should show a listener |

**Useful commands**

```bash
sudo ss -ltnp | grep 5000                 # is the app listening?
sudo fuser -k 5000/tcp                     # kill whatever holds :5000 (stale process)
ls -la .flask_session/                     # server-side sessions being written?
sudo journalctl -u entra-app -f            # app logs (systemd)
sudo tail -f /var/log/nginx/error.log      # nginx logs
```

> Retry sign-in from a **fresh Incognito window** starting at
> `https://VM_PUBLIC_IP/`. Reusing a tab with a spent `?code=` or an old giant
> cookie reproduces earlier errors.

---

## Security notes

- Secrets live in `.env` (chmod 600), never in source. **Rotate the client
  secret** if it was ever exposed (pasted, logged, committed).
- Cookies are `Secure`, `HttpOnly`, `SameSite=Lax`; TLS is enforced end to end;
  session payload is stored server-side.
- nginx sends HSTS, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`.
- For production: replace the self-signed cert with a CA-issued one, and prefer a
  **certificate credential** or **managed identity** over a client secret. Keep
  *Assignment required = Yes* so only intended users get in.
