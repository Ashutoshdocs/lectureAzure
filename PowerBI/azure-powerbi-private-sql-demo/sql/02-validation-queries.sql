-- Run after loading the seed data.
SELECT COUNT(*) AS RowCount, SUM(TotalAmount) AS TotalSales
FROM dbo.Sales;

SELECT Region, SUM(TotalAmount) AS SalesAmount
FROM dbo.Sales
GROUP BY Region
ORDER BY SalesAmount DESC;

SELECT Category, SUM(Quantity) AS Units, SUM(TotalAmount) AS SalesAmount
FROM dbo.Sales
GROUP BY Category
ORDER BY SalesAmount DESC;

SELECT *
FROM dbo.vw_SalesReport
ORDER BY OrderDate, OrderID;
