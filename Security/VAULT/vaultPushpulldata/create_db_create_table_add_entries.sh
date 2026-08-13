#!/bin/bash

# ==============================
# VARIABLES
# ==============================
MYSQL_USER="demouser"
MYSQL_PASS="Pass@12345"
MYSQL_DB="dbtest"
MYSQL_TABLE="tabletest"

# ==============================
# MYSQL COMMAND EXECUTION
# ==============================
mysql -u"${MYSQL_USER}" -p"${MYSQL_PASS}" <<EOF

-- Create Database
CREATE DATABASE IF NOT EXISTS ${MYSQL_DB};

-- Use Database
USE ${MYSQL_DB};

-- Create Table
CREATE TABLE IF NOT EXISTS ${MYSQL_TABLE} (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50),
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

EOF

# ==============================
# INSERT 20 RECORDS USING LOOP
# ==============================
for i in {1..20}
do
mysql -u"${MYSQL_USER}" -p"${MYSQL_PASS}" ${MYSQL_DB} <<EOF
INSERT INTO ${MYSQL_TABLE} (name, email)
VALUES ('User$i', 'user$i@example.com');
EOF
done

echo "✅ Database '${MYSQL_DB}', table '${MYSQL_TABLE}' created and 20 records inserted successfully."

