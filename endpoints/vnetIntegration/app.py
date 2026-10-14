import os
import logging
from flask import Flask, jsonify
import pyodbc

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

def get_connection():
    required = ["SQL_SERVER", "SQL_DATABASE", "SQL_USER", "SQL_PASSWORD"]
    missing = [name for name in required if not os.getenv(name)]
    if missing:
        raise RuntimeError("Missing required SQL application settings: " + ", ".join(missing))

    driver = os.getenv("SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    connection_string = (
        f"DRIVER={{{driver}}};"
        f"SERVER=tcp:{os.environ['SQL_SERVER']},1433;"
        f"DATABASE={os.environ['SQL_DATABASE']};"
        f"UID={os.environ['SQL_USER']};"
        f"PWD={os.environ['SQL_PASSWORD']};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=8;"
    )
    return pyodbc.connect(connection_string)

@app.get("/")
def home():
    return """
    <h1>Azure App Service VNet Integration Demo</h1>
    <p>This Web App Service is not VNet-injected.</p>
    <p>Try <a href="/health/db">/health/db</a> to test Azure SQL private connectivity.</p>
    """

@app.get("/health/db")
def database_health():
    try:
        with get_connection() as connection:
            cursor = connection.cursor()
            cursor.execute("SELECT Message FROM dbo.DemoStatus WHERE Id = ?", 1)
            row = cursor.fetchone()

        if row:
            return jsonify(
                status="connected",
                message=row[0],
                path="App Service -> VNet Integration -> Azure SQL Private Endpoint"
            ), 200

        return jsonify(status="connected", message="SQL connection succeeded; demo row not found"), 200

    except Exception:
        # Keep connection details and credentials out of public responses.
        app.logger.exception("Azure SQL health query failed")
        return jsonify(status="error", message="Database check failed; inspect application logs"), 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))