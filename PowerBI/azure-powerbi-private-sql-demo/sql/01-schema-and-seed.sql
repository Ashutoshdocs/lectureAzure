-- Run from a machine with private network reachability to the SQL private endpoint.
CREATE TABLE dbo.Sales
(
    OrderID       int            NOT NULL PRIMARY KEY,
    OrderDate     date           NOT NULL,
    Region        nvarchar(20)    NOT NULL,
    Product       nvarchar(60)    NOT NULL,
    Category      nvarchar(40)    NOT NULL,
    Quantity      int            NOT NULL,
    UnitPrice     decimal(12,2)  NOT NULL,
    CustomerType  nvarchar(20)    NOT NULL,
    TotalAmount AS (CONVERT(decimal(14,2), Quantity * UnitPrice)) PERSISTED
);
GO

INSERT dbo.Sales (OrderID, OrderDate, Region, Product, Category, Quantity, UnitPrice, CustomerType)
VALUES
(1001,'2026-01-05','West','Laptop','Electronics',2,65000,'Business'),
(1002,'2026-01-07','South','Monitor','Electronics',3,12000,'Consumer'),
(1003,'2026-01-09','North','Office Chair','Furniture',4,8500,'Business'),
(1004,'2026-01-12','East','Keyboard','Accessories',10,1200,'Consumer'),
(1005,'2026-01-15','West','Desk','Furniture',2,14500,'Business'),
(1006,'2026-02-02','South','Laptop','Electronics',1,68000,'Consumer'),
(1007,'2026-02-06','North','Mouse','Accessories',8,750,'Consumer'),
(1008,'2026-02-11','East','Monitor','Electronics',2,12500,'Business'),
(1009,'2026-02-18','West','Office Chair','Furniture',5,8200,'Consumer'),
(1010,'2026-02-22','South','Desk','Furniture',1,15000,'Business'),
(1011,'2026-03-03','North','Laptop','Electronics',2,67000,'Business'),
(1012,'2026-03-08','East','Keyboard','Accessories',6,1300,'Consumer'),
(1013,'2026-03-14','West','Monitor','Electronics',4,11800,'Consumer'),
(1014,'2026-03-20','South','Office Chair','Furniture',3,9000,'Business'),
(1015,'2026-03-26','North','Mouse','Accessories',12,700,'Consumer');
GO

CREATE VIEW dbo.vw_SalesReport AS
SELECT OrderID, OrderDate, Region, Product, Category, Quantity, UnitPrice,
       TotalAmount, CustomerType
FROM dbo.Sales;
GO
