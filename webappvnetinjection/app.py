import os
import psycopg
 
from flask import Flask, render_template, request, redirect
 
app = Flask(__name__)
 
# ---------------------------------------------------
# Database Connection
# ---------------------------------------------------
 
def get_connection():
    return psycopg.connect(
        host=os.environ["DBHOST"],
        dbname=os.environ["DBNAME"],
        user=os.environ["DBUSER"],
        password=os.environ["DBPASSWORD"],
        sslmode=os.environ.get("SSLMODE", "require"),
        connect_timeout=10,
    )
 
# ---------------------------------------------------
# Create Table (lazy, once, guarded)
# ---------------------------------------------------
 
_table_ready = False
 
def ensure_table():
    """Create the table on first real request instead of at import time.
 
    Doing DB work at import time means gunicorn cannot even boot the worker
    if the database is briefly unreachable -> App Service returns 503.
    """
    global _table_ready
    if _table_ready:
        return
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS students(
            id SERIAL PRIMARY KEY,
            name VARCHAR(100),
            course VARCHAR(100),
            age INT
        )
        """
    )
    conn.commit()
    cur.close()
    conn.close()
    _table_ready = True
 
# ---------------------------------------------------
# Health check (no DB) so the platform sees the app as up
# ---------------------------------------------------
 
@app.route("/healthz")
def healthz():
    return "ok", 200
 
# ---------------------------------------------------
# Home
# ---------------------------------------------------
 
@app.route("/")
def index():
    ensure_table()
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        SELECT id, name, course, age
        FROM students
        ORDER BY id
        """
    )
    students = cur.fetchall()
    cur.close()
    conn.close()
    return render_template("index.html", students=students)
 
# ---------------------------------------------------
# Add Student
# ---------------------------------------------------
 
@app.route("/add", methods=["POST"])
def add():
    ensure_table()
    name = request.form["name"]
    course = request.form["course"]
    age = request.form["age"]
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO students(name, course, age)
        VALUES(%s, %s, %s)
        """,
        (name, course, age),
    )
    conn.commit()
    cur.close()
    conn.close()
    return redirect("/")
 
# ---------------------------------------------------
# Delete Student
# ---------------------------------------------------
 
@app.route("/delete/<int:id>")
def delete(id):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DELETE FROM students WHERE id=%s", (id,))
    conn.commit()
    cur.close()
    conn.close()
    return redirect("/")
 
# ---------------------------------------------------
 
if __name__ == "__main__":
    app.run()
