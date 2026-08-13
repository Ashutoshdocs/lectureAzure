#!/bin/bash

sudo apt update -y
sudo apt install mysql-server -y

sudo systemctl start mysql
sudo systemctl enable mysql

mysql -u root <<EOF
CREATE DATABASE companydb;
USE companydb;

CREATE TABLE employees (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50),
  role VARCHAR(50)
);

INSERT INTO employees (name, role) VALUES
('User1','Dev'),('User2','QA'),('User3','HR'),
('User4','DevOps'),('User5','Support'),
('User6','Dev'),('User7','QA'),
('User8','HR'),('User9','DevOps'),
('User10','Support'),('User11','Dev'),
('User12','QA'),('User13','HR'),
('User14','DevOps'),('User15','Support'),
('User16','Dev'),('User17','QA'),
('User18','HR'),('User19','DevOps'),
('User20','Support');
EOF
