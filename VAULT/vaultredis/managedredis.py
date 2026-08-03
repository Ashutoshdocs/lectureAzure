import redis
from redis.cluster import RedisCluster
import mysql.connector
import time
import zlib
import pickle
import ssl
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

# =========================
# 🔐 Key Vault Configuration
# =========================
KEYVAULT_NAME = "myvaultblaze12345"
KV_URI = f"https://{KEYVAULT_NAME}.vault.azure.net/"

credential = DefaultAzureCredential()
client = SecretClient(vault_url=KV_URI, credential=credential)

# Fetch secrets
mysql_user = client.get_secret("mysql-username").value
mysql_pass = client.get_secret("mysql-password").value
redis_pass = client.get_secret("redis-password").value

# =========================
# 🛢️ MySQL Configuration
# =========================
MYSQL_CONFIG = {
    'host': 'localhost',
    'user': mysql_user,
    'password': mysql_pass,
    'database': 'dbtest'
}

# =========================
# ⚡ Redis Cluster Config
# =========================
REDIS_HOST = 'myredisblaze.centralus.redis.azure.net'
REDIS_PORT = 10000

CACHE_KEY = "sample_data_cache"

# =========================
# 🔌 Redis Connection
# =========================
def connect_redis():
    try:
        r = RedisCluster(
            host=REDIS_HOST,
            port=REDIS_PORT,
            password=redis_pass,
            ssl=True,
            ssl_cert_reqs=None,   # 🔥 FIX: avoid SSL IP mismatch issue
            decode_responses=False
        )
        r.ping()
        print("✅ Connected to Redis Cluster successfully")
        return r
    except Exception as e:
        print(f"❌ Redis connection failed: {e}")
        exit(1)

# =========================
# 🔌 MySQL Connection
# =========================
def connect_mysql():
    try:
        conn = mysql.connector.connect(**MYSQL_CONFIG)
        print("✅ Connected to MySQL successfully")
        return conn
    except Exception as e:
        print(f"❌ MySQL connection failed: {e}")
        exit(1)

# =========================
# 📦 Fetch Data Logic
# =========================
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

# =========================
# 🚀 Run
# =========================
if __name__ == "__main__":
    fetch_data()
