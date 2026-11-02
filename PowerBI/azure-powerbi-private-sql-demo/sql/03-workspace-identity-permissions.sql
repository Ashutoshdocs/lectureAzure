/*
  OPTIONAL: SQL-side permission example for a Fabric workspace identity.

  This is NOT a supported credential path for the VNet data gateway in this lab.
  Workspace identity authentication is currently not supported for gateway
  connections. Azure SQL connector Service Principal auth is also unsupported
  with a VNet data gateway.

  Use only for a supported direct cloud connection scenario, after you have
  created a workspace identity and confirmed the connector supports it.
  Replace the placeholder with the exact Entra workspace identity display name.
*/

-- Run as Microsoft Entra administrator for the Azure SQL logical server.
CREATE USER [<FABRIC_WORKSPACE_IDENTITY_DISPLAY_NAME>] FROM EXTERNAL PROVIDER;
GO

GRANT SELECT ON OBJECT::dbo.vw_SalesReport
TO [<FABRIC_WORKSPACE_IDENTITY_DISPLAY_NAME>];
GO

-- Optional if the identity must read the base table too:
-- GRANT SELECT ON OBJECT::dbo.Sales
-- TO [<FABRIC_WORKSPACE_IDENTITY_DISPLAY_NAME>];

-- Verify:
SELECT dp.name, dp.type_desc
FROM sys.database_principals AS dp
WHERE dp.name = N'<FABRIC_WORKSPACE_IDENTITY_DISPLAY_NAME>';
GO
