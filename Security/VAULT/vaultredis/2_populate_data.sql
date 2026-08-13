-- 2_populate_data.sql
DELIMITER //
CREATE PROCEDURE populate_employees()
BEGIN
  DECLARE i INT DEFAULT 1;
  WHILE i <= 100000 DO
    INSERT INTO employees (name, department, salary)
    VALUES (CONCAT('Employee_', i), 'Engineering', ROUND(RAND()*100000,2));
    SET i = i + 1;
  END WHILE;
END //
DELIMITER ;

CALL populate_employees();
