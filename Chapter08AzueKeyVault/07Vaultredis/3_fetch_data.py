# 3_fetch_data.py

import redis
import mysql.connector
import time
import zlib
import pickle
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# Key Vault Configuration
KEYVAULT_NAME = "MyDemoVault"
KV_URI = f"https://{KEYVAULT_NAME}.vault.azure.net/"

# Authenticate
credential = DefaultAzureCredential()
client = SecretClient(vault_url=KV_URI, credential=credential)

# Fetch secrets
mysql_user = client.get_secret("mysql-username").value
mysql_pass = client.get_secret("mysql-password").value
redis_pass = client.get_secret("redis-password").value

MYSQL_CONFIG = {
    'host': 'localhost',
    'user': mysql_user,
    'password': mysql_pass,
    'database': 'dbtest'
}

REDIS_CONFIG = {
    'host': 'myblaze.redis.cache.windows.net',
    'port': 6380,
    'password': redis_pass,
    'ssl': True
}

CACHE_KEY = "sample_data_cache"

def connect_redis():
    try:
        r = redis.Redis(**REDIS_CONFIG)
        r.ping()
        print("✅ Connected to Redis successfully")
        return r
    except Exception as e:
        print(f"❌ Redis connection failed: {e}")
        exit(1)

def connect_mysql():
    try:
        conn = mysql.connector.connect(**MYSQL_CONFIG)
        print("✅ Connected to MySQL successfully")
        return conn
    except Exception as e:
        print(f"❌ MySQL connection failed: {e}")
        exit(1)

def fetch_data():
    r = connect_redis()
    conn = connect_mysql()

    start_time = time.time()
    cached_data = r.get(CACHE_KEY)

    if cached_data:
        print("✅ Cache HIT — fetched from Redis")
        data = pickle.loads(zlib.decompress(cached_data))
    else:
        print("❌ Cache MISS — fetching from MySQL...")
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM employees;")
        data = cursor.fetchall()
        cursor.close()

        compressed = zlib.compress(pickle.dumps(data))
        try:
            r.set(CACHE_KEY, compressed)
            print(f"💾 Compressed data cached in Redis ({len(compressed)} bytes)")
        except Exception as e:
            print(f"⚠️ Redis write failed: {e}")

    print(f"📊 Records fetched: {len(data)}")
    print(f"⏱️ Time taken: {time.time() - start_time:.2f} seconds")

fetch_data()
