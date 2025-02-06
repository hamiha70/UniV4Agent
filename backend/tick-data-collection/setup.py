import sqlite3

DB_FILE = "coinbase_ethusdt.db"

def create_database():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tick_data (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            trade_id INTEGER,
            price REAL,
            size REAL,
            side TEXT,
            time TEXT
        )
    ''')

    conn.commit()
    conn.close()

if __name__ == "__main__":
    print('start')
    create_database()
    print("Database initialized successfully.")