import sqlite3
import pandas as pd
from datetime import datetime, timedelta
import matplotlib.pyplot as plt

DB_FILE = "backend/tick-data-collection/coinbase_ethusdt.db"

def get_time_period():
    """Get the start and end time of the dataset"""
    conn = sqlite3.connect(DB_FILE)
    query = """
    SELECT 
        MIN(time) as start_time,
        MAX(time) as end_time,
        COUNT(*) as total_trades
    FROM tick_data
    """
    df = pd.read_sql_query(query, conn)
    conn.close()
    return df

def get_trades_per_day():
    """Get the number of trades per day"""
    conn = sqlite3.connect(DB_FILE)
    query = """
    SELECT 
        date(time) as trade_date,
        COUNT(*) as trade_count
    FROM tick_data
    GROUP BY date(time)
    ORDER BY trade_date
    """
    df = pd.read_sql_query(query, conn)
    conn.close()
    return df

def get_trading_hours_analysis():
    """Analyze trading activity by hour of day"""
    conn = sqlite3.connect(DB_FILE)
    query = """
    SELECT 
        strftime('%H', time) as hour,
        COUNT(*) as trade_count,
        AVG(price) as avg_price,
        SUM(CASE WHEN side = 'buy' THEN size ELSE 0 END) as buy_volume,
        SUM(CASE WHEN side = 'sell' THEN size ELSE 0 END) as sell_volume
    FROM tick_data
    GROUP BY strftime('%H', time)
    ORDER BY hour
    """
    df = pd.read_sql_query(query, conn)
    conn.close()
    return df

def plot_trades_per_day(df):
    """Plot the number of trades per day"""
    plt.figure(figsize=(15, 6))
    plt.bar(df['trade_date'], df['trade_count'])
    plt.title('Number of Trades Per Day')
    plt.xlabel('Date')
    plt.ylabel('Number of Trades')
    plt.xticks(rotation=45)
    plt.tight_layout()
    plt.savefig('trades_per_day.png')
    plt.close()

def plot_trading_hours(df):
    """Plot trading activity by hour"""
    plt.figure(figsize=(15, 6))
    plt.bar(df['hour'], df['trade_count'])
    plt.title('Trading Activity by Hour')
    plt.xlabel('Hour of Day (UTC)')
    plt.ylabel('Number of Trades')
    plt.tight_layout()
    plt.savefig('trading_hours.png')
    plt.close()

def main():
    # Get overall time period
    time_period = get_time_period()
    print("\n=== Dataset Time Period ===")
    print(f"Start Time: {time_period['start_time'][0]}")
    print(f"End Time: {time_period['end_time'][0]}")
    print(f"Total Trades: {time_period['total_trades'][0]}")
    
    # Calculate duration
    start_time = pd.to_datetime(time_period['start_time'][0])
    end_time = pd.to_datetime(time_period['end_time'][0])
    duration = end_time - start_time
    print(f"\nDuration: {duration}")
    
    # Get trades per day
    trades_per_day = get_trades_per_day()
    print("\n=== Trades Per Day ===")
    print(trades_per_day)
    
    # Get trading hours analysis
    trading_hours = get_trading_hours_analysis()
    print("\n=== Trading Hours Analysis ===")
    print(trading_hours)
    
    # Generate plots
    print("\nGenerating plots...")
    plot_trades_per_day(trades_per_day)
    plot_trading_hours(trading_hours)
    print("Plots saved as 'trades_per_day.png' and 'trading_hours.png'")

if __name__ == "__main__":
    main() 