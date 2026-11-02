/* =====================================================================
   dataset.sql  —  SalesDemo dataset, Entra ID permissions, RLS, analysis views
   Run against database [SalesDemo] as the Entra ID admin of the SQL server
   (from the gateway VM via Bastion, using SSMS / Azure Data Studio /
    sqlcmd -G  — public access is disabled, so it must run inside the VNet).
   ===================================================================== */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   1. SCHEMA
   --------------------------------------------------------------------- */
IF SCHEMA_ID('sales') IS NULL EXEC('CREATE SCHEMA sales');
GO
IF SCHEMA_ID('rpt')   IS NULL EXEC('CREATE SCHEMA rpt');     -- reporting views for Power BI
GO
IF SCHEMA_ID('sec')   IS NULL EXEC('CREATE SCHEMA sec');     -- row-level security
GO

DROP TABLE IF EXISTS sales.FactSales;
DROP TABLE IF EXISTS sales.DimCustomer;
DROP TABLE IF EXISTS sales.DimProduct;
DROP TABLE IF EXISTS sales.DimDate;
DROP TABLE IF EXISTS sales.DimRegion;
GO

CREATE TABLE sales.DimRegion (
    RegionKey   INT          NOT NULL PRIMARY KEY,
    RegionName  NVARCHAR(50) NOT NULL,
    Country     NVARCHAR(50) NOT NULL,
    ManagerUPN  NVARCHAR(256) NULL          -- Entra ID UPN used by row-level security
);

CREATE TABLE sales.DimProduct (
    ProductKey   INT           NOT NULL PRIMARY KEY,
    ProductName  NVARCHAR(100) NOT NULL,
    Category     NVARCHAR(50)  NOT NULL,
    UnitCost     DECIMAL(10,2) NOT NULL,
    UnitPrice    DECIMAL(10,2) NOT NULL
);

CREATE TABLE sales.DimCustomer (
    CustomerKey   INT           NOT NULL PRIMARY KEY,
    CustomerName  NVARCHAR(100) NOT NULL,
    Segment       NVARCHAR(30)  NOT NULL,   -- Consumer / SMB / Enterprise
    RegionKey     INT           NOT NULL REFERENCES sales.DimRegion(RegionKey)
);

CREATE TABLE sales.DimDate (
    DateKey      INT      NOT NULL PRIMARY KEY,   -- yyyymmdd
    [Date]       DATE     NOT NULL,
    [Year]       SMALLINT NOT NULL,
    [Quarter]    TINYINT  NOT NULL,
    [Month]      TINYINT  NOT NULL,
    MonthName    NVARCHAR(10) NOT NULL,
    YearMonth    CHAR(7)  NOT NULL                -- 2025-01
);

CREATE TABLE sales.FactSales (
    SalesKey     BIGINT IDENTITY(1,1) PRIMARY KEY,
    DateKey      INT NOT NULL REFERENCES sales.DimDate(DateKey),
    CustomerKey  INT NOT NULL REFERENCES sales.DimCustomer(CustomerKey),
    ProductKey   INT NOT NULL REFERENCES sales.DimProduct(ProductKey),
    RegionKey    INT NOT NULL REFERENCES sales.DimRegion(RegionKey),
    Quantity     INT NOT NULL,
    UnitPrice    DECIMAL(10,2) NOT NULL,
    Discount     DECIMAL(4,2)  NOT NULL,     -- 0.00 – 0.20
    SalesAmount  AS (CAST(Quantity * UnitPrice * (1 - Discount) AS DECIMAL(12,2))) PERSISTED,
    CostAmount   DECIMAL(12,2) NOT NULL
);
GO

/* ---------------------------------------------------------------------
   2. SAMPLE DATA  (~50,000 sales rows, Jan 2024 – Dec 2025)
   Replace the UPNs below with real users in your tenant to test RLS.
   --------------------------------------------------------------------- */
INSERT sales.DimRegion VALUES
 (1, N'North', N'India',          N'north.manager@contoso.onmicrosoft.com'),
 (2, N'South', N'India',          N'south.manager@contoso.onmicrosoft.com'),
 (3, N'West',  N'India',          N'west.manager@contoso.onmicrosoft.com'),
 (4, N'East',  N'India',          N'east.manager@contoso.onmicrosoft.com'),
 (5, N'EMEA',  N'United Kingdom', NULL),
 (6, N'US',    N'United States',  NULL);

INSERT sales.DimProduct VALUES
 (1, N'Surface Laptop',      N'Devices',     700, 1100),
 (2, N'Surface Pro',         N'Devices',     650,  999),
 (3, N'Xbox Series X',       N'Gaming',      380,  499),
 (4, N'Xbox Controller',     N'Gaming',       25,   59),
 (5, N'Office 365 E3 (1yr)', N'Software',     90,  276),
 (6, N'Azure Credits $500',  N'Cloud',       400,  500),
 (7, N'Wireless Mouse',      N'Accessories',   8,   29),
 (8, N'USB-C Dock',          N'Accessories',  60,  149),
 (9, N'Teams Room Kit',      N'Devices',    1800, 2999),
 (10,N'Power BI Pro (1yr)',  N'Software',     60,  168);

-- Dates
;WITH d AS (
    SELECT CAST('2024-01-01' AS DATE) AS dt
    UNION ALL SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2025-12-31'
)
INSERT sales.DimDate
SELECT CONVERT(INT, FORMAT(dt,'yyyyMMdd')), dt, YEAR(dt), DATEPART(QUARTER,dt), MONTH(dt),
       LEFT(DATENAME(MONTH,dt),3), FORMAT(dt,'yyyy-MM')
FROM d OPTION (MAXRECURSION 1000);

-- Customers (500)
;WITH n AS (SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
            FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT sales.DimCustomer
SELECT i,
       CONCAT(N'Customer ', RIGHT('0000' + CAST(i AS VARCHAR(4)), 4)),
       CASE WHEN i % 10 < 5 THEN N'Consumer' WHEN i % 10 < 8 THEN N'SMB' ELSE N'Enterprise' END,
       (i % 6) + 1
FROM n;

-- Fact (50,000 rows, with seasonality: Q4 heavier, 2025 grows vs 2024)
;WITH n AS (SELECT TOP (50000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
            FROM sys.all_objects a CROSS JOIN sys.all_objects b),
r AS (
    SELECT i,
           ABS(CHECKSUM(NEWID())) % 500 + 1 AS CustomerKey,
           ABS(CHECKSUM(NEWID())) % 10  + 1 AS ProductKey,
           -- skew dates towards later months & 2025
           DATEADD(DAY,
                   CAST(730 * SQRT(RAND(CHECKSUM(NEWID()))) AS INT),
                   CAST('2024-01-01' AS DATE)) AS dt,
           ABS(CHECKSUM(NEWID())) % 5 + 1 AS Qty,
           CAST((ABS(CHECKSUM(NEWID())) % 5) * 0.05 AS DECIMAL(4,2)) AS Disc
    FROM n
)
INSERT sales.FactSales (DateKey, CustomerKey, ProductKey, RegionKey, Quantity, UnitPrice, Discount, CostAmount)
SELECT CONVERT(INT, FORMAT(CASE WHEN r.dt > '2025-12-31' THEN '2025-12-31' ELSE r.dt END,'yyyyMMdd')),
       r.CustomerKey, r.ProductKey, c.RegionKey,
       r.Qty + CASE WHEN MONTH(r.dt) IN (10,11,12) THEN 2 ELSE 0 END,
       p.UnitPrice, r.Disc,
       (r.Qty + CASE WHEN MONTH(r.dt) IN (10,11,12) THEN 2 ELSE 0 END) * p.UnitCost
FROM r
JOIN sales.DimCustomer c ON c.CustomerKey = r.CustomerKey
JOIN sales.DimProduct  p ON p.ProductKey  = r.ProductKey;
GO

CREATE NONCLUSTERED INDEX IX_FactSales_Date    ON sales.FactSales(DateKey)    INCLUDE (SalesAmount, CostAmount, Quantity);
CREATE NONCLUSTERED INDEX IX_FactSales_Region  ON sales.FactSales(RegionKey)  INCLUDE (SalesAmount, CostAmount);
GO

/* ---------------------------------------------------------------------
   3. REPORTING VIEWS (what Power BI connects to)
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW rpt.vSales AS
SELECT f.SalesKey, d.[Date], d.[Year], d.[Quarter], d.[Month], d.MonthName, d.YearMonth,
       c.CustomerName, c.Segment, r.RegionName, r.Country,
       p.ProductName, p.Category,
       f.Quantity, f.UnitPrice, f.Discount, f.SalesAmount, f.CostAmount,
       f.SalesAmount - f.CostAmount AS Profit
FROM sales.FactSales f
JOIN sales.DimDate     d ON d.DateKey     = f.DateKey
JOIN sales.DimCustomer c ON c.CustomerKey = f.CustomerKey
JOIN sales.DimProduct  p ON p.ProductKey  = f.ProductKey
JOIN sales.DimRegion   r ON r.RegionKey   = f.RegionKey;
GO

CREATE OR ALTER VIEW rpt.vMonthlyKpi AS
SELECT d.YearMonth, d.[Year], d.[Month],
       SUM(f.SalesAmount)                                   AS Revenue,
       SUM(f.SalesAmount - f.CostAmount)                    AS Profit,
       CAST(SUM(f.SalesAmount - f.CostAmount) * 100.0
            / NULLIF(SUM(f.SalesAmount),0) AS DECIMAL(5,2)) AS MarginPct,
       COUNT(*)                                             AS Orders,
       COUNT(DISTINCT f.CustomerKey)                        AS ActiveCustomers
FROM sales.FactSales f
JOIN sales.DimDate d ON d.DateKey = f.DateKey
GROUP BY d.YearMonth, d.[Year], d.[Month];
GO

CREATE OR ALTER VIEW rpt.vTopCustomers AS
SELECT TOP (20) c.CustomerName, c.Segment, r.RegionName,
       SUM(f.SalesAmount) AS Revenue,
       RANK() OVER (ORDER BY SUM(f.SalesAmount) DESC) AS RevenueRank
FROM sales.FactSales f
JOIN sales.DimCustomer c ON c.CustomerKey = f.CustomerKey
JOIN sales.DimRegion   r ON r.RegionKey   = f.RegionKey
GROUP BY c.CustomerName, c.Segment, r.RegionName
ORDER BY Revenue DESC;
GO

/* ---------------------------------------------------------------------
   4. ENTRA ID PERMISSIONS  (contained database users — no SQL logins)
   Create these Entra groups first (see README §3):
     - sg-pbi-sql-readers   : report authors / viewers using SSO
     - sp-powerbi-sqlreader : (optional) service principal / app registration
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'sg-pbi-sql-readers')
    CREATE USER [sg-pbi-sql-readers] FROM EXTERNAL PROVIDER;
GO
-- Least privilege: read only the reporting schema
GRANT SELECT ON SCHEMA::rpt TO [sg-pbi-sql-readers];
GO

-- Optional: service principal used by a Power BI cloud/gateway connection
-- IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'sp-powerbi-sqlreader')
--     CREATE USER [sp-powerbi-sqlreader] FROM EXTERNAL PROVIDER;
-- GRANT SELECT ON SCHEMA::rpt TO [sp-powerbi-sqlreader];
GO

/* ---------------------------------------------------------------------
   5. ROW-LEVEL SECURITY (works end-to-end with DirectQuery + Entra SSO,
      because SQL sees the real signed-in user's UPN)
   --------------------------------------------------------------------- */
DROP SECURITY POLICY IF EXISTS sec.RegionPolicy;
GO
CREATE OR ALTER FUNCTION sec.fn_RegionFilter(@RegionKey INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN
    SELECT 1 AS allowed
    FROM sales.DimRegion r
    WHERE r.RegionKey = @RegionKey
      AND (
            r.ManagerUPN = SUSER_SNAME()              -- Entra user (UPN) sees own region
         OR IS_ROLEMEMBER('db_owner') = 1             -- admins / Entra admin see all
      );
GO
-- Policy is created DISABLED so the demo works immediately; enable in README §9
CREATE SECURITY POLICY sec.RegionPolicy
    ADD FILTER PREDICATE sec.fn_RegionFilter(RegionKey) ON sales.FactSales
    WITH (STATE = OFF);
GO

/* ---------------------------------------------------------------------
   6. ANALYSIS QUERIES (run these to explore the data / validate the report)
   --------------------------------------------------------------------- */
-- 6a. Revenue, profit, margin by year
SELECT [Year], SUM(SalesAmount) Revenue, SUM(Profit) Profit,
       CAST(SUM(Profit)*100.0/SUM(SalesAmount) AS DECIMAL(5,2)) MarginPct
FROM rpt.vSales GROUP BY [Year] ORDER BY [Year];

-- 6b. Year-over-year growth by region
WITH y AS (SELECT RegionName, [Year], SUM(SalesAmount) Rev FROM rpt.vSales GROUP BY RegionName, [Year])
SELECT a.RegionName, a.Rev AS Rev2025, b.Rev AS Rev2024,
       CAST((a.Rev - b.Rev) * 100.0 / b.Rev AS DECIMAL(6,2)) AS YoYPct
FROM y a JOIN y b ON a.RegionName = b.RegionName AND a.[Year] = 2025 AND b.[Year] = 2024
ORDER BY YoYPct DESC;

-- 6c. Category mix and margin
SELECT Category, SUM(SalesAmount) Revenue,
       CAST(SUM(SalesAmount)*100.0/SUM(SUM(SalesAmount)) OVER() AS DECIMAL(5,2)) SharePct,
       CAST(SUM(Profit)*100.0/SUM(SalesAmount) AS DECIMAL(5,2)) MarginPct
FROM rpt.vSales GROUP BY Category ORDER BY Revenue DESC;

-- 6d. Discount impact on margin
SELECT Discount, COUNT(*) Orders,
       CAST(SUM(Profit)*100.0/SUM(SalesAmount) AS DECIMAL(5,2)) MarginPct
FROM rpt.vSales GROUP BY Discount ORDER BY Discount;

-- 6e. Seasonality: Q4 vs rest of year
SELECT CASE WHEN [Quarter] = 4 THEN 'Q4' ELSE 'Q1-Q3 (avg/qtr)' END AS Period,
       CASE WHEN [Quarter] = 4 THEN SUM(SalesAmount) ELSE SUM(SalesAmount)/3 END AS RevenuePerQuarter
FROM rpt.vSales WHERE [Year] = 2025
GROUP BY CASE WHEN [Quarter] = 4 THEN 'Q4' ELSE 'Q1-Q3 (avg/qtr)' END;

-- 6f. Who am I? (use this from Power BI DirectQuery to prove SSO identity)
SELECT USER_NAME() AS DbUser, SUSER_SNAME() AS LoginName, ORIGINAL_LOGIN() AS OriginalLogin;
GO
