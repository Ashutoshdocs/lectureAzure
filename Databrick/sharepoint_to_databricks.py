# Databricks notebook source
# MAGIC %md
# MAGIC # SharePoint / OneDrive → Azure Databricks → Insights → back to SharePoint
# MAGIC
# MAGIC This notebook:
# MAGIC 1. Authenticates to **Microsoft Graph** with an Entra ID (Azure AD) App Registration (service principal).
# MAGIC 2. Downloads `sample_sales_data.xlsx` from a SharePoint document library (or a OneDrive for Business folder).
# MAGIC 3. Loads it into Spark and saves **Delta tables** (bronze layer).
# MAGIC 4. Runs analysis to **find problems and solutions**: revenue vs target, high return rates, top/bottom products.
# MAGIC 5. Writes an `sales_insights.xlsx` report **back to SharePoint**.
# MAGIC
# MAGIC Secrets are read from the Databricks secret scope `sharepoint` (see README).

# COMMAND ----------

# MAGIC %pip install msal==1.31.0 openpyxl==3.1.5 requests
# MAGIC

# COMMAND ----------

dbutils.library.restartPython()

# COMMAND ----------

# MAGIC %md ## 1. Configuration

# COMMAND ----------

# ---- Secrets (never hard-code these) ----
SECRET_SCOPE  = "sharepoint"
TENANT_ID     = dbutils.secrets.get(SECRET_SCOPE, "tenant-id")
CLIENT_ID     = dbutils.secrets.get(SECRET_SCOPE, "client-id")
CLIENT_SECRET = dbutils.secrets.get(SECRET_SCOPE, "client-secret")

# ---- Where the file lives ----
# SOURCE_TYPE = "sharepoint"  -> file is in a SharePoint site document library
# SOURCE_TYPE = "onedrive"    -> file is in a user's OneDrive for Business
dbutils.widgets.dropdown("source_type", "sharepoint", ["sharepoint", "onedrive"])
dbutils.widgets.text("sp_hostname", "yourcompany.sharepoint.com")       # SharePoint host
dbutils.widgets.text("sp_site_path", "/sites/DataTeam")                 # site path
dbutils.widgets.text("library_name", "Documents")                       # "Documents" == "Shared Documents"
dbutils.widgets.text("onedrive_user", "user@yourcompany.com")           # only for onedrive
dbutils.widgets.text("input_path", "Databricks/input/sample_sales_data.xlsx")   # path INSIDE the library
dbutils.widgets.text("output_path", "Databricks/output/sales_insights.xlsx")
dbutils.widgets.text("catalog_schema", "main.sharepoint_demo")          # Unity Catalog <catalog>.<schema>

SOURCE_TYPE   = dbutils.widgets.get("source_type")
SP_HOSTNAME   = dbutils.widgets.get("sp_hostname")
SP_SITE_PATH  = dbutils.widgets.get("sp_site_path")
LIBRARY_NAME  = dbutils.widgets.get("library_name")
ONEDRIVE_USER = dbutils.widgets.get("onedrive_user")
INPUT_PATH    = dbutils.widgets.get("input_path").strip("/")
OUTPUT_PATH   = dbutils.widgets.get("output_path").strip("/")
CATALOG_SCHEMA = dbutils.widgets.get("catalog_schema")

GRAPH = "https://graph.microsoft.com/v1.0"

# COMMAND ----------

# MAGIC %md ## 2. Microsoft Graph helper functions

# COMMAND ----------

import io
import time
import requests
import msal
from urllib.parse import quote

_app = msal.ConfidentialClientApplication(
    client_id=CLIENT_ID,
    client_credential=CLIENT_SECRET,
    authority=f"https://login.microsoftonline.com/{TENANT_ID}",
)

def get_token() -> str:
    """App-only token for Microsoft Graph (client-credentials flow). MSAL caches it."""
    result = _app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
    if "access_token" not in result:
        raise RuntimeError(f"Token error: {result.get('error')} - {result.get('error_description')}")
    return result["access_token"]

def graph(method: str, url: str, retries: int = 4, **kwargs) -> requests.Response:
    """Call Graph with auth header and simple retry on throttling (429/503)."""
    if not url.startswith("http"):
        url = GRAPH + url
    extra_headers = kwargs.pop("headers", {})
    for attempt in range(retries):
        headers = {**extra_headers, "Authorization": f"Bearer {get_token()}"}
        resp = requests.request(method, url, headers=headers, timeout=120, **kwargs)
        if resp.status_code in (429, 503):
            wait = int(resp.headers.get("Retry-After", 2 ** attempt))
            print(f"Throttled, retrying in {wait}s ...")
            time.sleep(wait)
            continue
        if resp.status_code >= 400:
            raise RuntimeError(f"Graph {method} {url} failed [{resp.status_code}]: {resp.text[:500]}")
        return resp
    raise RuntimeError(f"Graph {method} {url} failed after {retries} retries")

def get_drive_id() -> str:
    """Return the drive (document library / OneDrive) ID to read from and write to."""
    if SOURCE_TYPE == "onedrive":
        return graph("GET", f"/users/{ONEDRIVE_USER}/drive").json()["id"]

    site = graph("GET", f"/sites/{SP_HOSTNAME}:{SP_SITE_PATH}").json()
    drives = graph("GET", f"/sites/{site['id']}/drives").json()["value"]
    for d in drives:
        if d["name"].lower() == LIBRARY_NAME.lower():
            print(f"Site: {site['webUrl']}  |  Library: {d['name']}")
            return d["id"]
    raise ValueError(f"Library '{LIBRARY_NAME}' not found. Available: {[d['name'] for d in drives]}")

def download_file(drive_id: str, path: str) -> bytes:
    resp = graph("GET", f"/drives/{drive_id}/root:/{quote(path)}:/content")
    print(f"Downloaded {path} ({len(resp.content):,} bytes)")
    return resp.content

def upload_file(drive_id: str, path: str, data: bytes) -> str:
    """Simple upload (files < 250 MB). Overwrites if the file exists."""
    resp = graph("PUT", f"/drives/{drive_id}/root:/{quote(path)}:/content",
                 data=data, headers={"Content-Type": "application/octet-stream"})
    url = resp.json().get("webUrl")
    print(f"Uploaded {path} -> {url}")
    return url

def list_folder(drive_id: str, folder: str = ""):
    url = f"/drives/{drive_id}/root/children" if not folder else f"/drives/{drive_id}/root:/{quote(folder)}:/children"
    return [(i["name"], "folder" if "folder" in i else "file") for i in graph("GET", url).json()["value"]]

# COMMAND ----------

# MAGIC %md ## 3. Connect and download the file

# COMMAND ----------

DRIVE_ID = get_drive_id()
print("Files in input folder:", list_folder(DRIVE_ID, INPUT_PATH.rsplit("/", 1)[0] if "/" in INPUT_PATH else ""))

file_bytes = download_file(DRIVE_ID, INPUT_PATH)

# COMMAND ----------

# MAGIC %md ## 4. Load into Spark and save as Delta (bronze)

# COMMAND ----------

import pandas as pd

sales_pdf   = pd.read_excel(io.BytesIO(file_bytes), sheet_name="Sales")
targets_pdf = pd.read_excel(io.BytesIO(file_bytes), sheet_name="Targets")
sales_pdf["OrderDate"] = pd.to_datetime(sales_pdf["OrderDate"])

sales_df   = spark.createDataFrame(sales_pdf)
targets_df = spark.createDataFrame(targets_pdf)

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG_SCHEMA}")
sales_df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"{CATALOG_SCHEMA}.sales_raw")
targets_df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"{CATALOG_SCHEMA}.targets_raw")

display(sales_df.limit(10))

# COMMAND ----------

# MAGIC %md ## 5. Clean + enrich (silver)

# COMMAND ----------

from pyspark.sql import functions as F

silver = (
    spark.table(f"{CATALOG_SCHEMA}.sales_raw")
    .dropDuplicates(["OrderID"])
    .filter(F.col("Quantity") > 0)
    .withColumn("GrossRevenue", F.col("Quantity") * F.col("UnitPrice"))
    .withColumn("NetRevenue",
                F.when(F.col("Returned") == "Yes", F.lit(0.0))
                 .otherwise(F.col("Quantity") * F.col("UnitPrice") * (1 - F.col("Discount"))))
    .withColumn("Month", F.date_format("OrderDate", "yyyy-MM"))
)
silver.write.mode("overwrite").saveAsTable(f"{CATALOG_SCHEMA}.sales_clean")

# COMMAND ----------

# MAGIC %md ## 6. Analysis – find the problems and suggest solutions (gold)

# COMMAND ----------

# 6a. Revenue vs target by region & month
vs_target = (
    silver.groupBy("Region", "Month").agg(F.round(F.sum("NetRevenue"), 2).alias("ActualRevenue"))
    .join(spark.table(f"{CATALOG_SCHEMA}.targets_raw"), ["Region", "Month"], "left")
    .withColumn("Achievement_pct", F.round(F.col("ActualRevenue") / F.col("RevenueTarget") * 100, 1))
    .withColumn("Status", F.when(F.col("Achievement_pct") >= 100, "On target")
                           .when(F.col("Achievement_pct") >= 80, "At risk")
                           .otherwise("Missed"))
    .orderBy("Region", "Month")
)

# 6b. Return rate by region & category (returns destroy revenue)
returns = (
    silver.groupBy("Region", "Category")
    .agg(F.count("*").alias("Orders"),
         F.sum(F.when(F.col("Returned") == "Yes", 1).otherwise(0)).alias("Returns"),
         F.round(F.sum(F.when(F.col("Returned") == "Yes", F.col("GrossRevenue")).otherwise(0)), 2).alias("RevenueLost"))
    .withColumn("ReturnRate_pct", F.round(F.col("Returns") / F.col("Orders") * 100, 1))
    .orderBy(F.desc("ReturnRate_pct"))
)

# 6c. Product performance
products = (
    silver.groupBy("Product", "Category")
    .agg(F.sum("Quantity").alias("UnitsSold"),
         F.round(F.sum("NetRevenue"), 2).alias("NetRevenue"),
         F.round(F.avg("Discount") * 100, 1).alias("AvgDiscount_pct"))
    .orderBy(F.desc("NetRevenue"))
)

# 6d. Sales rep leaderboard
reps = (
    silver.groupBy("Region", "SalesRep")
    .agg(F.round(F.sum("NetRevenue"), 2).alias("NetRevenue"), F.count("*").alias("Orders"))
    .orderBy(F.desc("NetRevenue"))
)

display(vs_target); display(returns); display(products)

# COMMAND ----------

# 6e. Rule-based recommendations ("the solution")
recs = []

region_summary = (vs_target.groupBy("Region")
                  .agg(F.sum(F.when(F.col("Status") == "Missed", 1).otherwise(0)).alias("MissedMonths"),
                       F.round(F.avg("Achievement_pct"), 1).alias("AvgAchievement"))
                  .collect())
for r in region_summary:
    if r.MissedMonths >= 3:
        recs.append(("Revenue", r.Region,
                     f"{r.Region} missed target in {r.MissedMonths} months (avg {r.AvgAchievement}% of target).",
                     "Review pipeline with regional manager; reallocate leads from top reps; run a targeted promotion."))

for row in returns.filter("ReturnRate_pct >= 10 AND Orders >= 20").collect():
    recs.append(("Returns", row.Region,
                 f"{row.Category} in {row.Region} has {row.ReturnRate_pct}% returns (lost {row.RevenueLost:,.0f}).",
                 "Check product quality/shipping damage for this region; add pre-delivery inspection; review the carrier."))

for row in products.filter("AvgDiscount_pct >= 7").collect():
    recs.append(("Pricing", "All",
                 f"{row.Product} sells at an average {row.AvgDiscount_pct}% discount.",
                 "Tighten discount approval rules; test a bundle offer instead of a flat discount."))

if not recs:
    recs.append(("Info", "All", "No issues found against the current rules.", "-"))

recs_df = spark.createDataFrame(recs, "Area string, Region string, Finding string, Recommendation string")
display(recs_df)

for name, df in {"gold_vs_target": vs_target, "gold_returns": returns, "gold_products": products,
                 "gold_reps": reps, "gold_recommendations": recs_df}.items():
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"{CATALOG_SCHEMA}.{name}")

# COMMAND ----------

# MAGIC %md ## 7. Write the insights report back to SharePoint

# COMMAND ----------

buf = io.BytesIO()
with pd.ExcelWriter(buf, engine="openpyxl") as xw:
    recs_df.toPandas().to_excel(xw, sheet_name="Recommendations", index=False)
    vs_target.toPandas().to_excel(xw, sheet_name="Revenue vs Target", index=False)
    returns.toPandas().to_excel(xw, sheet_name="Returns", index=False)
    products.toPandas().to_excel(xw, sheet_name="Products", index=False)
    reps.toPandas().to_excel(xw, sheet_name="Sales Reps", index=False)

report_url = upload_file(DRIVE_ID, OUTPUT_PATH, buf.getvalue())
dbutils.notebook.exit(report_url)
