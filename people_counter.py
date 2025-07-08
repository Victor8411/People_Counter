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
