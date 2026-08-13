import os
import csv
import io
import psycopg

from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    flash,
    Response
)

app = Flask(__name__)
app.secret_key = "AzureStudentPortal2026"

# -----------------------------------
# Database Configuration
# -----------------------------------

DB_HOST = os.getenv("DB_HOST")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_PORT = os.getenv("DB_PORT", "5432")

if not all([DB_HOST, DB_NAME, DB_USER, DB_PASSWORD]):
    raise RuntimeError(
        "Database environment variables are missing."
    )


# -----------------------------------
# Database Connection
# -----------------------------------

def get_connection():

    return psycopg.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        port=DB_PORT,
        sslmode="require"
    )


# -----------------------------------
# Create Table
# -----------------------------------

def create_table():

    conn = None

    try:

        conn = get_connection()

        with conn.cursor() as cur:

            cur.execute("""
                CREATE TABLE IF NOT EXISTS students
                (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(100) NOT NULL,
                    email VARCHAR(200) NOT NULL
                );
            """)

        conn.commit()

    finally:

        if conn:
            conn.close()


@app.before_request
def initialize():

    create_table()


# -----------------------------------
# Dashboard
# -----------------------------------

@app.route("/")
def dashboard():

    conn = get_connection()

    with conn.cursor() as cur:

        cur.execute("SELECT COUNT(*) FROM students")

        total_students = cur.fetchone()[0]

        cur.execute("""
            SELECT
                id,
                name,
                email
            FROM students
            ORDER BY id DESC
            LIMIT 5
        """)

        recent_students = cur.fetchall()

    conn.close()

    return render_template(
        "dashboard.html",
        total_students=total_students,
        recent_students=recent_students
    )


# -----------------------------------
# View Students
# -----------------------------------

@app.route("/students")
def students():

    search = request.args.get("search", "").strip()

    conn = get_connection()

    with conn.cursor() as cur:

        if search:

            cur.execute(
                """
                SELECT
                    id,
                    name,
                    email
                FROM students
                WHERE
                    LOWER(name) LIKE LOWER(%s)
                    OR LOWER(email) LIKE LOWER(%s)
                ORDER BY id DESC
                """,
                (f"%{search}%", f"%{search}%")
            )

        else:

            cur.execute("""
                SELECT
                    id,
                    name,
                    email
                FROM students
                ORDER BY id DESC
            """)

        rows = cur.fetchall()

    conn.close()

    return render_template(
        "students.html",
        students=rows,
        search=search
    )


# -----------------------------------
# Add Student
# -----------------------------------

@app.route("/add")
def add_student():

    return render_template("add_student.html")


# -----------------------------------
# Save Student
# -----------------------------------

@app.route("/save", methods=["POST"])
def save():

    name = request.form.get("name", "").strip()
    email = request.form.get("email", "").strip()

    if not name or not email:

        flash("Name and Email are required.")

        return redirect(url_for("add_student"))

    conn = get_connection()

    with conn.cursor() as cur:

        cur.execute(
            """
            SELECT COUNT(*)
            FROM students
            WHERE email=%s
            """,
            (email,)
        )

        if cur.fetchone()[0] > 0:

            conn.close()

            flash("Email already exists.")

            return redirect(url_for("add_student"))

        cur.execute(
            """
            INSERT INTO students
            (
                name,
                email
            )
            VALUES
            (
                %s,
                %s
            )
            """,
            (name, email)
        )

    conn.commit()

    conn.close()

    flash("Student added successfully.")

    return redirect(url_for("students"))
# -----------------------------------
# Edit Student
# -----------------------------------

@app.route("/edit/<int:id>")
def edit(id):

    conn = get_connection()

    with conn.cursor() as cur:

        cur.execute(
            """
            SELECT
                id,
                name,
                email
            FROM students
            WHERE id=%s
            """,
            (id,)
        )

        student = cur.fetchone()

    conn.close()

    if student is None:

        flash("Student not found.")

        return redirect(url_for("students"))

    return render_template(
        "edit_student.html",
        student=student
    )


# -----------------------------------
# Update Student
# -----------------------------------

@app.route("/update/<int:id>", methods=["POST"])
def update(id):

    name = request.form.get("name", "").strip()
    email = request.form.get("email", "").strip()

    if not name or not email:

        flash("Name and Email are required.")

        return redirect(url_for("edit", id=id))

    conn = get_connection()

    with conn.cursor() as cur:

        cur.execute(
            """
            SELECT COUNT(*)
            FROM students
            WHERE email=%s
            AND id<>%s
            """,
            (email, id)
        )

        if cur.fetchone()[0] > 0:

            conn.close()

            flash("Email already exists.")

            return redirect(url_for("edit", id=id))

        cur.execute(
            """
            UPDATE students
            SET
                name=%s,
                email=%s
            WHERE id=%s
            """,
            (name, email, id)
        )

    conn.commit()

    conn.close()

    flash("Student updated successfully.")

    return redirect(url_for("students"))


# -----------------------------------
# Delete Student
# -----------------------------------

@app.route("/delete/<int:id>")
def delete(id):

    conn = get_connection()

    with conn.cursor() as cur:

        cur.execute(
            "DELETE FROM students WHERE id=%s",
            (id,)
        )

    conn.commit()

    conn.close()

    flash("Student deleted successfully.")

    return redirect(url_for("students"))


# -----------------------------------
# Export CSV
# -----------------------------------

@app.route("/export")
def export():

    conn = get_connection()

    with conn.cursor() as cur:

        cur.execute(
            """
            SELECT
                id,
                name,
                email
            FROM students
            ORDER BY id
            """
        )

        rows = cur.fetchall()

    conn.close()

    output = io.StringIO()

    writer = csv.writer(output)

    writer.writerow([
        "ID",
        "Student Name",
        "Email"
    ])

    writer.writerows(rows)

    output.seek(0)

    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={
            "Content-Disposition":
            "attachment; filename=students.csv"
        }
    )


# -----------------------------------
# Health Check
# -----------------------------------

@app.route("/health")
def health():

    try:

        conn = get_connection()

        conn.close()

        db_status = "Connected"

    except Exception:

        db_status = "Disconnected"

    return {
        "status": "Healthy",
        "application": "Azure Student Portal",
        "database": db_status
    }


# -----------------------------------
# Global Error Handler
# -----------------------------------

@app.errorhandler(Exception)
def handle_exception(e):

    app.logger.exception(e)

    return render_template(
        "error.html",
        message=str(e)
    ), 500


# -----------------------------------
# Main
# -----------------------------------

if __name__ == "__main__":

    create_table()

    app.run(
        host="0.0.0.0",
        port=8000,
        debug=True
    )