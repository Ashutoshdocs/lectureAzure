import os
import psycopg

from flask import Flask, render_template, request, redirect

app = Flask(__name__)

#---------------------------------------------------
# Database Connection
#---------------------------------------------------

def get_connection():

    return psycopg.connect(

        host=os.environ["DBHOST"],
        dbname=os.environ["DBNAME"],
        user=os.environ["DBUSER"],
        password=os.environ["DBPASSWORD"],
        sslmode=os.environ["SSLMODE"]

    )

#---------------------------------------------------
# Create Table
#---------------------------------------------------

def create_table():

    conn = get_connection()

    cur = conn.cursor()

    cur.execute("""

    CREATE TABLE IF NOT EXISTS students(

        id SERIAL PRIMARY KEY,

        name VARCHAR(100),

        course VARCHAR(100),

        age INT

    )

    """)

    conn.commit()

    cur.close()

    conn.close()

create_table()

#---------------------------------------------------
# Home
#---------------------------------------------------

@app.route("/")

def index():

    conn = get_connection()

    cur = conn.cursor()

    cur.execute("""

        SELECT id,name,course,age

        FROM students

        ORDER BY id

    """)

    students = cur.fetchall()

    cur.close()

    conn.close()

    return render_template(

        "index.html",

        students=students

    )

#---------------------------------------------------
# Add Student
#---------------------------------------------------

@app.route("/add",methods=["POST"])

def add():

    name=request.form["name"]

    course=request.form["course"]

    age=request.form["age"]

    conn=get_connection()

    cur=conn.cursor()

    cur.execute(

        """

        INSERT INTO students(name,course,age)

        VALUES(%s,%s,%s)

        """,

        (name,course,age)

    )

    conn.commit()

    cur.close()

    conn.close()

    return redirect("/")

#---------------------------------------------------
# Delete Student
#---------------------------------------------------

@app.route("/delete/<int:id>")

def delete(id):

    conn=get_connection()

    cur=conn.cursor()

    cur.execute(

        "DELETE FROM students WHERE id=%s",

        (id,)

    )

    conn.commit()

    cur.close()

    conn.close()

    return redirect("/")

#---------------------------------------------------

if __name__=="__main__":

    app.run()