To run the collector in the background using systemd on Linux:

## Create a systemd Service
**Run**
sudo nano /etc/systemd/system/coinbase_collector.service

**Paste the following**:**
"""
[Unit]
Description=Coinbase ETH/USD Tick Data Collector
After=network.target

[Service]
ExecStart=/usr/bin/python3 /path/to/coinbase_collector.py
WorkingDirectory=/path/to/
Restart=always
User=yourusername

[Install]
WantedBy=multi-user.target
"""

**Start and Enable the Service**
sudo systemctl daemon-reload
sudo systemctl start coinbase_collector
sudo systemctl enable coinbase_collector

**Check Status**
sudo systemctl status coinbase_collector

**Restart Service**
sudo systemctl restart coinbase_collector

**Stop Service**
sudo systemctl stop coinbase_collector