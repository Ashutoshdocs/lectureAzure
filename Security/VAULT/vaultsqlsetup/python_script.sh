#!/bin/bash
set -e

echo "=============================="
echo " Azure Python + SQL Setup"
echo " Ubuntu 24.04"
echo "=============================="

APP_DIR="/home/azure/pythonapp"
VENV_DIR="$APP_DIR/venv"
APP_FILE="$APP_DIR/app.py"
KEYVAULT_NAME="kv-app-demo24"

echo "[1/7] Updating OS..."
sudo apt update -y

echo "[2/7] Installing base packages..."
sudo apt install -y \
  curl gnupg python3-pip python3-venv \
  unixodbc unixodbc-dev

echo "[3/7] Installing Microsoft ODBC Driver 18..."

curl https://packages.microsoft.com/keys/microsoft.asc \
| sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
https://packages.microsoft.com/ubuntu/24.04/prod noble main" \
| sudo tee /etc/apt/sources.list.d/microsoft-prod.list

sudo apt update -y
sudo ACCEPT_EULA=Y apt install -y msodbcsql18

echo "[4/7] Creating application directory..."
mkdir -p $APP_DIR
cd $APP_DIR

echo "[5/7] Creating Python virtual environment..."
python3 -m venv venv

source venv/bin/activate

echo "[6/7] Installing Python dependencies inside venv..."
pip install --upgrade pip
pip install flask pyodbc azure-identity azure-keyvault-secrets

echo "[7/7] Creating Flask application..."

cat <<EOF > $APP_FILE
from flask import Flask, request
import pyodbc
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

app = Flask(__name__)

KEY_VAULT_NAME = "${KEYVAULT_NAME}"
KV_URI = f"https://{KEY_VAULT_NAME}.vault.azure.net"

credential = DefaultAzureCredential()
client = SecretClient(vault_url=KV_URI, credential=credential)

conn_str = client.get_secret("sql-conn-string").value

def get_conn():
    return pyodbc.connect(conn_str)

PAGE_STYLE = """
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #0078d4 0%, #5b2a86 100%);
            padding: 20px;
        }
        .card {
            background: #ffffff;
            width: 100%;
            max-width: 420px;
            border-radius: 16px;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.25);
            padding: 40px 36px;
            animation: rise 0.5s ease;
        }
        @keyframes rise {
            from { opacity: 0; transform: translateY(16px); }
            to   { opacity: 1; transform: translateY(0); }
        }
        .brand {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 24px;
        }
        .brand-dot {
            width: 14px; height: 14px;
            border-radius: 50%;
            background: linear-gradient(135deg, #0078d4, #5b2a86);
        }
        .brand span {
            font-size: 13px;
            font-weight: 600;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            color: #5b2a86;
        }
        h2 {
            font-size: 24px;
            color: #1b1b2f;
            margin-bottom: 6px;
        }
        .subtitle {
            font-size: 14px;
            color: #6b7280;
            margin-bottom: 28px;
        }
        label {
            display: block;
            font-size: 13px;
            font-weight: 600;
            color: #374151;
            margin-bottom: 6px;
        }
        input[type="text"], input[type="email"] {
            width: 100%;
            padding: 12px 14px;
            font-size: 15px;
            border: 1.5px solid #e2e5ec;
            border-radius: 10px;
            margin-bottom: 20px;
            transition: border-color 0.2s, box-shadow 0.2s;
            outline: none;
        }
        input[type="text"]:focus, input[type="email"]:focus {
            border-color: #0078d4;
            box-shadow: 0 0 0 3px rgba(0, 120, 212, 0.15);
        }
        button {
            width: 100%;
            padding: 13px;
            font-size: 15px;
            font-weight: 600;
            color: #ffffff;
            background: linear-gradient(135deg, #0078d4, #5b2a86);
            border: none;
            border-radius: 10px;
            cursor: pointer;
            transition: transform 0.15s, box-shadow 0.15s, opacity 0.15s;
        }
        button:hover {
            transform: translateY(-1px);
            box-shadow: 0 8px 20px rgba(91, 42, 134, 0.35);
            opacity: 0.97;
        }
        button:active { transform: translateY(0); }
        .success {
            text-align: center;
        }
        .check {
            width: 64px; height: 64px;
            margin: 0 auto 20px;
            border-radius: 50%;
            background: #e7f6ec;
            color: #1a7f37;
            font-size: 34px;
            line-height: 64px;
        }
        .success h3 {
            font-size: 20px;
            color: #1b1b2f;
            margin-bottom: 10px;
        }
        .success p {
            font-size: 14px;
            color: #6b7280;
            margin-bottom: 24px;
        }
        .back {
            display: inline-block;
            padding: 11px 22px;
            font-size: 14px;
            font-weight: 600;
            color: #0078d4;
            text-decoration: none;
            border: 1.5px solid #0078d4;
            border-radius: 10px;
            transition: background 0.2s, color 0.2s;
        }
        .back:hover { background: #0078d4; color: #ffffff; }
    </style>
"""

@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        name = request.form.get("name")
        email = request.form.get("email")

        conn = get_conn()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO user_data (name, email) VALUES (?, ?)",
            (name, email)
        )
        conn.commit()
        conn.close()

        return PAGE_STYLE + """
        <div class="card">
            <div class="success">
                <div class="check">&#10003;</div>
                <h3>Data stored successfully</h3>
                <p>Your entry was saved to the Azure SQL Database.</p>
                <a class="back" href="/">Add another entry</a>
            </div>
        </div>
        """

    return PAGE_STYLE + """
    <div class="card">
        <div class="brand">
            <div class="brand-dot"></div>
            <span>Azure &bull; Python &bull; SQL</span>
        </div>
        <h2>User Entry Form</h2>
        <p class="subtitle">Fill in the details below to store a record.</p>
        <form method="post">
            <label for="name">Name</label>
            <input type="text" id="name" name="name" placeholder="Jane Doe" required>

            <label for="email">Email</label>
            <input type="email" id="email" name="email" placeholder="jane@example.com" required>

            <button type="submit">Submit</button>
        </form>
    </div>
    """

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=30080)
EOF

chmod +x $APP_FILE

echo "=============================="
echo " SETUP COMPLETED SUCCESSFULLY"
echo "=============================="
echo ""
echo "Next steps:"
echo "1) source $VENV_DIR/bin/activate"
echo "2) python app.py"
echo "3) Open browser: http://<VM_PUBLIC_IP>:30080"