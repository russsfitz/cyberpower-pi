#!/bin/bash

echo "Starting PeaNUT..."
docker compose up -d

echo "Fixing config directory permissions..."
sudo chown -R 1000:1000 /opt/peanut/config

echo "Done! PeaNUT is running at http://$(hostname -I | awk '{print $1}'):8080"
