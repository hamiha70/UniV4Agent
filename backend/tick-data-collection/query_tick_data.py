import sqlite3
import pandas as pd
from datetime import datetime, timedelta
import matplotlib.pyplot as plt
import seaborn as sns
import traceback

DB_FILE = "backend/tick-data-collection/coinbase_ethusdt.db"

def get_connection():
    """Create and return a database connection"""
    try:
        conn = sqlite3.connect(DB_FILE)
        print(f"Successfully connected to database at {DB_FILE}")
        return conn
    except Exception as e:
        print(f"Error connecting to database: {e}")
        raise

def get_recent_trades(limit=10):
    """Get the most recent trades"""
    try:
        conn = get_connection()
        query = """
        SELECT trade_id, price, size, side, time as trade_time
        FROM tick_data
        ORDER BY time DESC
        LIMIT ?
        """
        print(f"Executing query: {query}")
        df = pd.read_sql_query(query, conn, params=(limit,))
        print(f"Retrieved {len(df)} recent trades")
        conn.close()
        return df
    except Exception as e:
        print(f"Error in get_recent_trades: {e}")
        traceback.print_exc()
        raise

def get_price_stats(time_window_minutes=60):
    """Get price statistics for a given time window"""
    try:
        conn = get_connection()
        current_time = datetime.utcnow()
        start_time = (current_time - timedelta(minutes=time_window_minutes)).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        print(f"Calculated start time: {start_time}")
        
        query = """
        SELECT 
            MIN(price) as min_price,
            MAX(price) as max_price,
            AVG(price) as avg_price,
            COUNT(*) as trade_count,
            SUM(CASE WHEN side = 'buy' THEN size ELSE 0 END) as total_buy_volume,
            SUM(CASE WHEN side = 'sell' THEN size ELSE 0 END) as total_sell_volume
        FROM tick_data
        WHERE time >= ?
        """
        print(f"Executing query: {query}")
        df = pd.read_sql_query(query, conn, params=(start_time,))
        print(f"Retrieved price stats: {df.to_dict()}")
        conn.close()
        return df
    except Exception as e:
        print(f"Error in get_price_stats: {e}")
        traceback.print_exc()
        raise

def get_price_chart(time_window_minutes=60):
    """Generate a price chart for the given time window"""
    try:
        conn = get_connection()
        current_time = datetime.utcnow()
        start_time = (current_time - timedelta(minutes=time_window_minutes)).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        print(f"Calculated start time for chart: {start_time}")
        
        query = """
        SELECT 
            time as trade_time,
            price,
            side
        FROM tick_data
        WHERE time >= ?
        ORDER BY time ASC
        """
        print(f"Executing query: {query}")
        df = pd.read_sql_query(query, conn, params=(start_time,))
        print(f"Retrieved {len(df)} data points for chart")
        
        # Convert ISO format string to datetime
        df['trade_time'] = pd.to_datetime(df['trade_time'])
        
        plt.figure(figsize=(12, 6))
        sns.lineplot(data=df, x='trade_time', y='price', hue='side')
        plt.title(f'ETH/USDT Price - Last {time_window_minutes} minutes')
        plt.xlabel('Time')
        plt.ylabel('Price')
        plt.xticks(rotation=45)
        plt.tight_layout()
        plt.savefig('price_chart.png')
        plt.close()
        
        conn.close()
        return df
    except Exception as e:
        print(f"Error in get_price_chart: {e}")
        traceback.print_exc()
        raise

def get_volume_analysis(time_window_minutes=60):
    """Analyze trading volume for the given time window"""
    try:
        conn = get_connection()
        current_time = datetime.utcnow()
        start_time = (current_time - timedelta(minutes=time_window_minutes)).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        print(f"Calculated start time for volume analysis: {start_time}")
        
        query = """
        SELECT 
            side,
            SUM(size) as total_volume,
            COUNT(*) as trade_count,
            AVG(size) as avg_trade_size
        FROM tick_data
        WHERE time >= ?
        GROUP BY side
        """
        print(f"Executing query: {query}")
        df = pd.read_sql_query(query, conn, params=(start_time,))
        print(f"Retrieved volume analysis: {df.to_dict()}")
        conn.close()
        return df
    except Exception as e:
        print(f"Error in get_volume_analysis: {e}")
        traceback.print_exc()
        raise

def main():
    try:
        print("\n=== Recent Trades ===")
        print(get_recent_trades(5))
        
        print("\n=== Price Statistics (Last Hour) ===")
        print(get_price_stats())
        
        print("\n=== Volume Analysis (Last Hour) ===")
        print(get_volume_analysis())
        
        print("\nGenerating price chart...")
        get_price_chart()
        print("Price chart saved as 'price_chart.png'")
    except Exception as e:
        print(f"Error in main: {e}")
        traceback.print_exc()

if __name__ == "__main__":
    main() 