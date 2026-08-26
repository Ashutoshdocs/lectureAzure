# Secure Employee Portal — Microsoft Entra ID SSO Demo

A small but realistic enterprise web app that demonstrates **Microsoft Entra ID
(Azure AD) single sign-on** end to end. After a user signs in with their work
account, the portal:

- reads their **real profile** live from **Microsoft Graph** (`/me`),
- shows their **app-role assignments** (from the ID-token `roles` claim),
- exposes a **token-protected API** (`/api/me`, `/api/groups`) to demonstrate
  calling downstream services with the access token,
- displays the **raw verified ID-token claims** — handy when demoing or
  debugging SSO,
- supports **proper sign-out** (clears the session *and* the Entra browser
  session).

It runs behind **nginx (TLS) → gunicorn → Flask**, with all secrets loaded from
a `.env` file (nothing sensitive is hard-coded).

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
│   └── entra-app.conf     # Hardened reverse-proxy + HTTP→HTTPS redirect
├── templates/             # login, dashboard, error pages
└── static/
    └── style.css          # Portal styling
```

---

## Prerequisites

- An Azure VM (Ubuntu) with a **public IP** and ports **80 + 443** open in the
  Network Security Group.
- Permission to create an **App registration** in your Entra tenant.

Throughout, replace `VM_PUBLIC_IP` with your VM's actual public IP (or DNS name).

---

## Part 1 — Register the app in Microsoft Entra ID

1. **Entra ID → App registrations → New registration**

   | Field | Value |
   |---|---|
   | Name | `vm-enterprise-app` |
   | Supported account types | *Single tenant* |
   | Redirect URI | **Web** → `https://VM_PUBLIC_IP/getAToken` |

   Click **Register**.

2. From the **Overview** page, copy the **Application (client) ID** and
   **Directory (tenant) ID** — you'll need them for `.env`.

3. **Certificates & secrets → Client secrets → New client secret.**
   Copy the secret **Value** immediately (it's shown only once).

4. *(Optional but recommended for the demo)* **App roles → Create app role** to
   show role-based access:

   | Field | Example |
   |---|---|
   | Display name | `Portal Admin` |
   | Allowed member types | Users/Groups |
   | Value | `Portal.Admin` |
   | Description | `Full access to the portal` |

   Repeat for a second role such as `Reports.Reader` if you like.

5. *(Optional)* To make the **`/api/groups`** endpoint work:
   **API permissions → Add a permission → Microsoft Graph → Delegated →
   `GroupMember.Read.All`**, then **Grant admin consent**. Also add
   `GroupMember.Read.All` to `SCOPE` in your `.env`.

---

## Part 2 — Restrict access to assigned users

This is what makes it an **enterprise** app — only assigned users get in.

1. **Entra ID → Enterprise applications → `vm-enterprise-app` → Properties**
   - **Assignment required?** → **Yes** → Save.
2. **Users and groups → Add user/group** → assign the users (and, if you created
   app roles, pick the role to assign). Unassigned users will be blocked at
   sign-in.

---

## Part 3 — Set up the VM

```bash
sudo apt update
sudo apt install -y python3-pip python3-venv nginx openssl

# Put the project on the VM (clone, scp, or copy the files) into ~/entra-app
cd ~/entra-app

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Create the configuration

```bash
cp .env.example .env
# Generate a strong Flask session key:
python -c "import secrets; print('FLASK_SECRET_KEY=' + secrets.token_hex(32))"
```

Edit `.env` and fill in `CLIENT_ID`, `TENANT_ID`, `CLIENT_SECRET`, and the
`FLASK_SECRET_KEY` you just generated. Make sure `REDIRECT_PATH=/getAToken`
matches the redirect URI you registered.

```bash
chmod 600 .env    # keep secrets readable only by you
```

### Create a self-signed TLS certificate

```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key \
  -out /etc/nginx/ssl/nginx.crt
# When prompted for "Common Name (CN)", enter your VM_PUBLIC_IP
```

> Self-signed certs cause a browser warning — fine for a demo. For production use
> a real certificate (e.g. Let's Encrypt with a DNS name).

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

---

## Part 5 — Run the app

### Quick test (development)

```bash
source venv/bin/activate
set -a && source .env && set +a      # load env vars into the shell
python app.py                        # serves on 127.0.0.1:5000 behind nginx
```

Browse to `https://VM_PUBLIC_IP/`, accept the cert warning, and sign in.

### Production (gunicorn + systemd)

1. Edit `entra-app.service` — set `User`, `WorkingDirectory`, and the paths to
   match your VM (defaults assume user `azureuser` and `/home/azureuser/entra-app`).
2. Install and start it:

   ```bash
   sudo cp entra-app.service /etc/systemd/system/entra-app.service
   sudo systemctl daemon-reload
   sudo systemctl enable --now entra-app
   sudo systemctl status entra-app     # verify it's running
   ```

nginx proxies `https://VM_PUBLIC_IP/` → gunicorn on `127.0.0.1:5000`.

---

## How the sign-in flow works

1. User hits `/` → not signed in → **login page**.
2. `/login` builds the Entra authorization URL (with an anti-CSRF `state`) and
   redirects the browser to Microsoft.
3. User authenticates; Entra checks **assignment required** and redirects back to
   `/getAToken?code=…&state=…`.
4. The app verifies `state`, exchanges the `code` for tokens (MSAL), stores the
   ID-token claims and a token cache in the session, and redirects to
   `/dashboard`.
5. The dashboard calls **Microsoft Graph** with the access token to show the live
   profile; roles come from the ID token.
6. `/logout` clears the session and signs the user out at Entra.

---

## Endpoints

| Route | Purpose |
|---|---|
| `/` | Landing / login gate |
| `/login` | Start the Entra sign-in |
| `/getAToken` | OAuth redirect handler (`REDIRECT_PATH`) |
| `/dashboard` | Authenticated portal view |
| `/api/me` | Protected JSON — the user's Graph profile |
| `/api/groups` | Protected JSON — the user's group memberships |
| `/logout` | Sign out (session + Entra) |
| `/healthz` | Liveness probe for monitoring |

---

## Troubleshooting

- **`AADSTS50011: redirect URI mismatch`** — the redirect URI in the app
  registration must exactly equal `https://VM_PUBLIC_IP/getAToken` (scheme, host,
  path), and `REDIRECT_PATH` in `.env` must be `/getAToken`.
- **Redirected to `http://` / State mismatch** — nginx must send
  `X-Forwarded-Proto https` (it does in the provided config); `ProxyFix` in
  `app.py` relies on it to build `https` URLs.
- **`AADSTS50105: not assigned to a role`** — expected when *Assignment
  required* is on and the user (or their group) hasn't been assigned.
- **"Graph unavailable" on the dashboard** — the VM couldn't reach
  `graph.microsoft.com`, or the token lacks the scope. Check outbound network and
  the `SCOPE` value.
- **`/api/groups` returns 403** — add and admin-consent
  `GroupMember.Read.All`, and include it in `SCOPE`.
- **Logs** — `sudo journalctl -u entra-app -f` for the app,
  `sudo tail -f /var/log/nginx/error.log` for nginx.

---

## Security notes

- Secrets live in `.env` (chmod 600), never in source. Rotate the client secret
  before it expires.
- Cookies are `Secure`, `HttpOnly`, `SameSite=Lax`; TLS is enforced end to end.
- For production, replace the self-signed cert with a CA-issued one and consider
  storing the client secret in Azure Key Vault or using a managed identity /
  certificate credential instead of a client secret.
