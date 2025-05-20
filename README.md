# People Counter with YOLOv8, InfluxDB and Grafana on Raspberry Pi

## 🧠 Project Summary

This project turns a Raspberry Pi 5 and a High Quality Camera into a real-time people counter using YOLOv8. The detected data is sent to InfluxDB and visualized through Grafana dashboards. All installation and configuration steps are automated through a shell script for quick and reproducible deployments.

---

## 🔧 Hardware Requirements

* Raspberry Pi 5 (tested)
* Raspberry Pi High Quality Camera 
* MicroSD card with Raspberry Pi OS 64-bit (Bookworm recommended)
* Internet connection (Wi-Fi or Ethernet)

---

## 🧰 Software Stack

* **YOLOv8**: People detection (Ultralytics)
* **OpenCV**: Image processing
* **Picamera2**: Capture video frames from the camera
* **InfluxDB v2**: Time-series database to store the number of people detected
* **Grafana**: Visualization of real-time graphs and statistics

---

## ⚙️ Installation (automated)

### 📁 Step 1. Clone or download this repository

Clone it on your PC or download the zip and extract it.

### 📂 Step 2. Transfer the project to your Raspberry Pi

Via SCP or a USB key:

```bash
scp -r people-counter/ pi@<RPI_IP>:/home/pi/
```

### 🏁 Step 3. Run the installer

```bash
cd ~/people-counter
chmod +x install.sh
./install.sh
```

⏱️ Takes about 10–15 minutes.

### What the script does:

* Updates the Pi
* Installs all dependencies (Python, camera, OpenCV, etc.)
* Sets up InfluxDB v2 and Grafana
* Downloads and sets up YOLOv8
* Creates and enables a systemd service to launch people counting at boot
* Configures Grafana with the proper InfluxDB datasource (via API)

---

## 📡 Live Data Flow

1. Picamera2 captures live frames
2. YOLOv8 detects persons (class 0)
3. Every 2 seconds, the count is evaluated
4. Results are batched and sent every 10 seconds to InfluxDB
5. Grafana reads from InfluxDB and displays a live dashboard

---

## 📊 Manual Grafana Datasource Configuration (if auto-fail)


### 📍 In Grafana UI (http://IP:3000):

1. Go to **Configuration > Data sources > Add data source**
2. Select **InfluxDB**
3. Fill in the following:

#### 🔷 QUERY LANGUAGE

* **Query Language**: `Flux`

#### 🔷 HTTP

* **URL**: `http://localhost:8086`

#### 🔐 Auth (all unchecked)

* ❌ Basic Auth: OFF
* ❌ With Credentials: OFF
* ❌ TLS / CA Cert: OFF

#### 📊 InfluxDB Details

* **Organization**: `admin`
* **Token**: `admin`
* **Default Bucket**: `admin`
* **Query Language**: `Flux`
* **Min Time Interval**: `10s`

Click **Save & Test**. You should see "Data source is working".

---

## 🧪 Grafana Query to Display People Count

Go to dashboards for creating a new one.
Add new visualisation with the data source created.
Creating a new panel:

```flux
from(bucket: "admin")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r["_measurement"] == "person_counter")
  |> filter(fn: (r) => r["_field"] == "count")
  |> aggregateWindow(every: 1s, fn: last, createEmpty: false)
```
Then refresh.
This will display a graph of how many people were detected over time.
Save dashboard.
---

## 🔁 Service Management

To check that the detection is working:

```bash
journalctl -fu count_people.service
```

You should see logs like:

```
🟢 Envoi à InfluxDB (4 points)
⚠️ Forçage de l'envoi du 0 à InfluxDB (aucune détection depuis 5s)
```

---

## ✅ Default Credentials

* Grafana: http://IP:3000

  * Login: `admin`
  * Password: `admin`
* InfluxDB: http://IP:8086

  * Login: `admin`
  * Password: `adminadmin`
  * Bucket: `admin`
  * Org: `admin`
  * Token: `admin`

---

## 📎 Files

* `install.sh` → full automated installer

---

## 📌 To Do / Ideas

* [ ] Add predefined Grafana dashboard JSON
* [ ] Optional alerts if too many people
* [ ] REST API to pull latest count

---

## 📷 Example

![image](https://github.com/user-attachments/assets/c6b0040e-3e19-4f27-9933-00dbecbc20c5)

## 📬 Feedback

Feel free to fork, test, or submit issues to improve the deployment or detection accuracy.
