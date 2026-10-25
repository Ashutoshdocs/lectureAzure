# Azure Student Portal

A Flask + PostgreSQL web application for managing student records, containerized with Docker and deployed to **Azure App Service** via **Azure Container Registry (ACR)**, with **Azure Database for PostgreSQL** as the backend and a custom domain secured with an App Service Managed Certificate.

---

## Features

| Feature | Route | Method | Description |
|---|---|---|---|
| Dashboard | `/` | GET | Total student count and the 5 most recently added students |
| View Students | `/students` | GET | Lists all students (newest first) |
| Search | `/students?search=<text>` | GET | Case-insensitive search on name or email |
| Add Student | `/add` | GET | Shows the add-student form |
| Save Student | `/save` | POST | Validates input, rejects duplicate emails, inserts the record |
| Edit Student | `/edit/<id>` | GET | Shows the edit form for a student |
| Update Student | `/update/<id>` | POST | Validates input, rejects duplicate emails, updates the record |
| Delete Student | `/delete/<id>` | GET | Deletes a student |
| Export CSV | `/export` | GET | Downloads all students as `students.csv` |
| Health Check | `/health` | GET | Returns JSON with app and database status |

Other behaviour:

- The `students` table is created automatically if it does not exist.
- All database connections use SSL (`sslmode=require`), as required by Azure PostgreSQL.
- Flash messages report success and validation errors.
- A global error handler logs exceptions and renders `error.html`.

---

## Tech Stack

- **Python** 3.14 (Docker base image `python:3.14-slim`)
- **Flask** 3.1.2
- **Gunicorn** 23.0.0 (production WSGI server)
- **psycopg** 3.2.10 (PostgreSQL driver)
- **python-dotenv** 1.1.1
- **Azure**: App Service (Linux, container), Container Registry, Database for PostgreSQL

---

## Project Structure

```
.
├── app.py                      # Flask application
├── requirements.txt            # Python dependencies
├── startup.sh                  # Gunicorn launch script
├── Dockerfile                  # Container image definition
├── dockerfilecommands          # Docker build command reference
├── script for db password.ps1  # Sets Azure Web App settings and restarts the app
└── templates/
    ├── dashboard.html
    ├── students.html
    ├── add_student.html
    ├── edit_student.html
    └── error.html
```

---

## Database Schema

```sql
CREATE TABLE IF NOT EXISTS students (
    id    SERIAL PRIMARY KEY,
    name  VARCHAR(100) NOT NULL,
    email VARCHAR(200) NOT NULL
);
```

Email uniqueness is enforced in the application (on save and update).

---

## Environment Variables

The app will not start unless the first four are set.

| Variable | Required | Default | Example |
|---|---|---|---|
| `DB_HOST` | Yes | — | `blazeserver.postgres.database.azure.com` |
| `DB_NAME` | Yes | — | `studentdb` |
| `DB_USER` | Yes | — | `myazureuser` |
| `DB_PASSWORD` | Yes | — | `<your-password>` |
| `DB_PORT` | No | `5432` | `5432` |
| `PORT` | No | `8000` | Port Gunicorn binds to |
| `WEBSITES_PORT` | Azure only | — | `8000` — tells App Service which container port to route to |

> **Username format:** Azure PostgreSQL *Single Server* uses `user@servername`. *Flexible Server* uses just `user`. Use the format that matches your server type.

---

## Run Locally

1. Create and activate a virtual environment:

   ```bash
   python -m venv venv
   source venv/bin/activate        # Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. Set the environment variables (PowerShell example):

   ```powershell
   $env:DB_HOST="blazeserver.postgres.database.azure.com"
   $env:DB_NAME="studentdb"
   $env:DB_USER="myazureuser"
   $env:DB_PASSWORD="<your-password>"
   ```

   Make sure your local IP is allowed in the PostgreSQL server's **Networking → Firewall rules**.

3. Start the app:

   ```bash
   python app.py
   ```

   Open http://localhost:8000

---

## Run with Docker

Build the image:

```bash
docker build --no-cache -t myacrblaze.azurecr.io/webapp:v1 .
```

Run it locally:

```bash
docker run -p 8000:8000 \
  -e DB_HOST=blazeserver.postgres.database.azure.com \
  -e DB_NAME=studentdb \
  -e DB_USER=myazureuser \
  -e DB_PASSWORD='<your-password>' \
  myacrblaze.azurecr.io/webapp:v1
```

The container runs `startup.sh`, which starts Gunicorn on `0.0.0.0:${PORT:-8000}`.

---

## Deploy to Azure

### 1. Push the image to Azure Container Registry

```bash
az acr login --name myacrblaze
docker push myacrblaze.azurecr.io/webapp:v1
```

### 2. Create / configure the Web App

In the Azure Portal (or CLI), create a **Linux Web App** using a **Container** that pulls `myacrblaze.azurecr.io/webapp:v1` from ACR. Enable the ACR admin user or assign the Web App's managed identity the `AcrPull` role.

### 3. Allow the Web App to reach PostgreSQL

In the PostgreSQL server under **Networking**, enable **Allow public access from any Azure service within Azure to this server** (or add the Web App's outbound IPs to the firewall).

### 4. Set application settings

Run the PowerShell script (after replacing the placeholder values with your own):

```powershell
./"script for db password.ps1"
```

It sets `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_PORT` and `WEBSITES_PORT=8000` on the Web App `webappblazetest` in resource group `main`, lists the current settings, and restarts the app.

### 5. Verify

```
https://webappblazetest.azurewebsites.net/health
```

Expected response:

```json
{
  "status": "Healthy",
  "application": "Azure Student Portal",
  "database": "Connected"
}
```

---

## Custom Domain & SSL

The app is served on the custom domain **akblazeacademy.store**.

1. In the Web App, go to **Custom domains → Add custom domain** and choose:
   - Domain provider: **All other domain services**
   - TLS/SSL certificate: **App Service Managed Certificate** (free)
   - TLS/SSL type: **SNI SSL**
   - Domain: `akblazeacademy.store`
   - Hostname record type: **A record**

2. At your domain registrar's DNS settings, add the two records Azure shows:

   | Type | Host | Value |
   |---|---|---|
   | A | `@` | The Web App's inbound IP address shown in the portal |
   | TXT | `asuid` | The domain verification ID shown in the portal |

3. Wait for DNS to propagate (minutes to a few hours), click **Validate**, and once both records show a green check, click **Add**.

4. Azure issues and binds the managed certificate. The site is then available at:

   ```
   https://akblazeacademy.store
   ```

5. Optional: under **Configuration → General settings**, set **HTTPS Only** to **On**.

> App Service Managed Certificates only support alphanumeric, dash and period characters in the domain name, and do not cover wildcard domains.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| App fails to start with `Database environment variables are missing.` | One of `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` is not set in App Settings. |
| `/health` shows `"database": "Disconnected"` | PostgreSQL firewall is blocking the Web App, wrong credentials, or wrong username format (see note above). |
| Site shows "Application Error" / container won't respond | `WEBSITES_PORT` is not `8000`. Check **Log stream** in the portal. |
| Image pull fails | Web App lacks ACR access — enable admin user or grant `AcrPull`. |
| Custom domain validation fails | DNS records not propagated yet, or the A/TXT values don't exactly match the portal. Check with `nslookup akblazeacademy.store`. |

---

## Security Notes (recommended improvements)

- **Don't commit secrets.** The PowerShell script and `app.py` contain a hardcoded DB password and Flask `secret_key`. Use placeholders in source control, load `SECRET_KEY` from an environment variable, and consider **Azure Key Vault references** in App Settings.
- **Rotate the database password** if it has ever been pushed to a repository.
- **Turn off debug mode** — `app.run(debug=True)` should not be used outside local development (Gunicorn in the container does not use it).
- **Make delete a POST request** — `/delete/<id>` is a GET, so a simple link or crawler can delete records. Add CSRF protection (e.g. Flask-WTF) to forms.
- **Add a UNIQUE constraint** on `students.email` so duplicates are prevented at the database level, not just in code.
- **Move table creation to startup** — `create_table()` currently runs before every request, adding a DB round trip each time.
- **Avoid showing raw exception messages** to users in `error.html`.

---

## License

For educational / demonstration use.
