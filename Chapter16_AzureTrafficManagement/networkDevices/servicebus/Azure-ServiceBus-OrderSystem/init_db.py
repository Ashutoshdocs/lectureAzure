"""Create the SQLite database and orders table. Run once before starting."""
from database import init_db
from config import DB_PATH

if __name__ == "__main__":
    init_db()
    print("=" * 50)
    print(" Database initialised successfully")
    print(f"  Location: {DB_PATH}")
    print(" Table    : orders")
    print("=" * 50)
