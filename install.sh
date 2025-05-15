#!/bin/bash
set -e

### 🔧 1. Mise à jour système
sudo apt update && sudo apt upgrade -y

### 📦 2. Dépendances système + libcamera
sudo apt install -y python3-picamera2 python3-libcamera libatlas-base-dev \
libjpeg-dev libopenjp2-7-dev libtiff-dev libavcodec-dev libavformat-dev libswscale-dev \
python3-opencv python3-venv ffmpeg curl git libcap-dev apt-transport-https software-properties-common wget gpg jq \
python3-libcamera

### 🧹 3. Nettoyage des dépôts et clés
sudo rm -f /etc/apt/sources.list.d/influxdb.list /etc/apt/keyrings/influxdata-archive-keyring.gpg
sudo mkdir -p /etc/apt/keyrings
curl -s https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/keyrings/influxdata-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/influxdata-archive-keyring.gpg] https://repos.influxdata.com/debian stable main" | sudo tee /etc/apt/sources.list.d/influxdb.list

sudo rm -f /etc/apt/sources.list.d/grafana.list
wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null <<EOF
deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main
EOF

### 🔁 4. Mise à jour et installation des services
sudo apt update
sudo apt install -y influxdb2 influxdb2-cli grafana

### ▶️ 5. Activer InfluxDB et Grafana
sudo systemctl enable --now influxdb
sudo systemctl enable --now grafana-server
sleep 5

### 🧠 6. Initialisation InfluxDB v2
influx setup --username admin --password adminadmin --org admin --bucket admin --token admin --force

### 🐍 7. Environnement Python virtuel
python3 -m venv $HOME/opencv-env
echo "import site; site.addsitedir('/usr/lib/python3/dist-packages')" >> $HOME/opencv-env/lib/python3.11/site-packages/_venvfix.pth
source $HOME/opencv-env/bin/activate
pip install --upgrade pip wheel
pip install ultralytics influxdb-client opencv-python picamera2

### 📄 8. Télécharger YOLOv8s si besoin
if [ ! -f yolov8s.pt ]; then
  curl -L -o yolov8s.pt https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8s.pt
fi

### 🧠 9. Script Python
cat << 'EOF' > $HOME/count_people.py
from picamera2 import Picamera2
import cv2
import time
from ultralytics import YOLO
import numpy as np
from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS

url = "http://localhost:8086"
token = "admin"
org = "admin"
bucket = "admin"

client = InfluxDBClient(url=url, token=token, org=org)
write_api = client.write_api(write_options=SYNCHRONOUS)

model = YOLO('yolov8s.pt')
model.fuse()

picam2 = Picamera2()
config = picam2.create_video_configuration(main={"format": 'XRGB8888', "size": (640, 480)})
picam2.configure(config)
picam2.start()

frame_interval = 0.5
last_frame_time = time.time()

batch_data = []
batch_interval = 10
last_batch_time = time.time()

last_sent_value = None
force_zero = False
force_save_time = 600
last_force_save = time.time()

last_detection_time = time.time()
zero_timeout = 5

try:
    while True:
        current_time = time.time()

        if current_time - last_frame_time < frame_interval:
            continue
        last_frame_time = current_time

        frame = picam2.capture_array()
        frame = cv2.resize(frame, (640, 384))
        frame = cv2.cvtColor(frame, cv2.COLOR_RGBA2RGB)

        results = model(frame, conf=0.5, verbose=False)[0]
        person_count = sum(1 for c in results.boxes.cls if int(c.item()) == 0)

        if person_count > 0:
            last_detection_time = current_time

        if person_count == 0 and (current_time - last_detection_time >= zero_timeout):
            print("⚠️ Forçage de l'envoi du 0 à InfluxDB (aucune détection depuis 5s)")
            force_zero = True
        else:
            force_zero = False

        if person_count != last_sent_value or force_zero or (current_time - last_force_save >= force_save_time):
            batch_data.append(Point("person_counter").field("count", person_count).time(time.time_ns(), WritePrecision.NS))
            last_sent_value = person_count
            last_force_save = current_time

        if current_time - last_batch_time >= batch_interval and batch_data:
            write_api.write(bucket=bucket, org=org, record=batch_data)
            print(f"🟢 Envoi à InfluxDB ({len(batch_data)} points)")
            batch_data = []
            last_batch_time = current_time

except KeyboardInterrupt:
    print("Arrêt par l'utilisateur.")
finally:
    picam2.stop()
    client.close()
EOF

### 🔁 10. Service systemd
cat << EOF | sudo tee /etc/systemd/system/count_people.service > /dev/null
[Unit]
Description=Count People YOLOv8 Service
After=network.target

[Service]
ExecStart=$HOME/opencv-env/bin/python $HOME/count_people.py
WorkingDirectory=$HOME
StandardOutput=inherit
StandardError=inherit
Restart=always
User=$(whoami)
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

### ✅ 11. Activer le service
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable count_people.service
sudo systemctl start count_people.service

### ✅ 12. Datasource Grafana auto
echo "🕒 Attente de Grafana..."
sleep 15
curl -s -X POST http://localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic admin:adminadmin" \
  -d '{
    "name": "InfluxDB",
    "type": "influxdb",
    "access": "proxy",
    "url": "http://localhost:8086",
    "basicAuth": false,
    "jsonData": {
      "version": "Flux",
      "organization": "admin",
      "defaultBucket": "admin"
    },
    "secureJsonData": {
      "token": "admin"
    }
  }' && echo "✅ Datasource Grafana créée automatiquement."

### ✅ Fin
echo ""
echo "🎉 INSTALLATION TERMINÉE"
echo "➡️ Grafana : http://$(hostname -I | awk '{print $1}'):3000  (admin / adminadmin)"
echo "➡️ InfluxDB : http://$(hostname -I | awk '{print $1}'):8086  (admin / adminadmin)"
echo "➡️ Logs script : journalctl -fu count_people.service"



