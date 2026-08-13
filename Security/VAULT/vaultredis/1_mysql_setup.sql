-- 1_mysql_setup.sql
CREATE USER 'dbadmin'@'localhost' IDENTIFIED BY 'Pass@12345';
CREATE DATABASE dbtest;
GRANT ALL PRIVILEGES ON dbtest.* TO 'dbadmin'@'localhost';
FLUSH PRIVILEGES;
USE dbtest;

CREATE TABLE employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    department VARCHAR(100),
    salary DECIMAL(10,2)
);
