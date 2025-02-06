import websocket
import json
import sqlite3
import threading
import time

DB_FILE = "coinbase_ethusdt.db"

COINBASE_WS_URL = "wss://ws-feed.exchange.coinbase.com"

def save_to_database(trade_id, price, size, side, trade_time):
    """ Saves tick data to the SQLite database """
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO tick_data (trade_id, price, size, side, time)
        VALUES (?, ?, ?, ?, ?)
    ''', (trade_id, price, size, side, trade_time))
    
    conn.commit()
    conn.close()

def on_message(ws, message):
    """ Handles incoming messages from Coinbase WebSocket """
    data = json.loads(message)
    
    if 'type' in data and data['type'] == 'match':  # 'match' events indicate a trade execution
        trade_id = data.get("trade_id")
        price = float(data.get("price", 0))
        size = float(data.get("size", 0))
        side = data.get("side")
        trade_time = data.get("time")

        print(f"Trade ID: {trade_id}, Price: {price}, Size: {size}, Side: {side}, Time: {trade_time}")

        save_to_database(trade_id, price, size, side, trade_time)

def on_error(ws, error):
    print(f"WebSocket Error: {error}")

def on_close(ws, close_status_code, close_msg):
    print("WebSocket closed, reconnecting in 5 seconds...")
    time.sleep(5)
    start_websocket()

def on_open(ws):
    """ Subscribe to ETH/USDT trades on Coinbase WebSocket """
    subscribe_msg = json.dumps({
        "type": "subscribe",
        "channels": [{"name": "matches", "product_ids": ["ETH-USDT"]}]
    })
    ws.send(subscribe_msg)

def start_websocket():
    """ Starts the WebSocket connection in a loop """
    while True:
        try:
            ws = websocket.WebSocketApp(COINBASE_WS_URL,
                                        on_message=on_message,
                                        on_error=on_error,
                                        on_close=on_close)
            ws.on_open = on_open
            ws.run_forever()
        except Exception as e:
            print(f"Error in WebSocket connection: {e}")
            time.sleep(5)

if __name__ == "__main__":
    threading.Thread(target=start_websocket, daemon=True).start()
    while True:
        time.sleep(1)  # Keeps the script running