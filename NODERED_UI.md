# Node-RED Dashboard UI for Auto AIR MQTT Control

## Overview
This document describes the Node-RED dashboard structure for monitoring and controlling Auto AIR devices via MQTT.

## MQTT Topics Structure
Based on the MQTT topic format: `air/{SITE_NAME}/{type}`

### Subscribed Topics (Device → Dashboard)
- `air/{SITE_NAME}/data` - Sensor data (temperature, humidity, pressure, etc.)
- `air/{SITE_NAME}/status` - System status updates
- `air/{SITE_NAME}/error` - Error notifications

### Published Topics (Dashboard → Device)
- `air/{SITE_NAME}/command` - System commands
- `air/{SITE_NAME}/ota` - OTA firmware update commands
- `air/{SITE_NAME}/config` - Configuration commands

---

## Dashboard Layout

### 1. **Header Section**
**Components:**
- **Site Name Display** - Shows `CONFIG_SITE_NAME`
- **Connection Status Indicator** - Green/Red indicator for MQTT connection
- **Last Update Time** - Timestamp of last message received

---

### 2. **System Status Panel**

**Data Displays:**
- **Valve State** - Current valve state (text display)
  - Source: `status.valve_state`
- **Counter** - On/Off counter value
  - Source: `status.counter`
- **Uptime** - Device uptime in hours
  - Source: `status.uptime`
- **Free Heap** - Available memory (bytes)
  - Source: `status.free_heap`
- **Error Condition** - Boolean indicator (red/green)
  - Source: `status.error_condition`
- **IMSI** - SIM card identifier (if available)
  - Source: `status.imsi`
- **Timestamp** - Device timestamp
  - Source: `status.timestamp`

**Visual Elements:**
- Gauge for free heap memory
- LED indicator for error condition
- Text displays for other values

---

### 3. **Sensor Data Panel**

**Real-time Sensor Readings:**
- **Temperature** - °C (gauge + numeric)
  - Source: `data.temperature`
- **Pressure** - hPa (gauge + numeric)
  - Source: `data.pressure`
- **Water Temperature** - °C (gauge + numeric)
  - Source: `data.water_temp`

**Visual Elements:**
- Color-coded gauges (green = normal, yellow = warning, red = critical)
- Chart showing historical trends (last 24 hours)

---

### 4. **Command Control Panel**

**System Commands** (Buttons to publish to `air/{SITE_NAME}/command` topic):

1. **Data Request Button**
   - Command: `"data"`
   - Description: Request immediate sensor data transmission
   - Color: Blue

2. **Status Request Button**
   - Command: `"status"`
   - Description: Request comprehensive system status
   - Color: Green

**Button Commands** (based on button_control.h):

4. **Demo Button** (A Short)
   - Command: `"demo"`
   - Description: Run demo mode

6. **WiFi Button** (B Short)
   - Command: `"wifi"`
   - Description: WiFi related function

9. **Reboot Button** (D Short)
   - Command: `"reboot"`
   - Description: Reboot device
   - Color: Red
   - Confirmation dialog required

---

### 6. **Configuration Panel**

**Components:**

1. **Config Status Button**
   - Topic: `air/{SITE_NAME}/config`
   - Payload: `"status"`
   - Description: Request all configuration variables
   - Color: Blue

2. **Config Display Area**
   - JSON viewer showing current configuration
   - Editable fields for configuration updates

3. **Config Update**
   - Text input for JSON configuration
   - Submit button to publish to config topic
   - Example format: `{"key": "value"}`

---

### 7. **Error & Notification Panel**

**Components:**

1. **Error Log Display**
   - Scrolling list of error messages
   - Source: `air/{SITE_NAME}/error` topic
   - Color-coded by severity
   - Timestamp for each error

2. **Notification Display**
   - Recent system notifications
   - Command execution results
   - Connection status changes

3. **Clear Notifications Button**
   - Clears the notification display (local UI only)

---

## Node-RED Flow Structure

### Required Nodes

1. **MQTT Input Nodes** (3):
   - Subscribe to `air/{SITE_NAME}/data` topic
   - Subscribe to `air/{SITE_NAME}/status` topic
   - Subscribe to `air/{SITE_NAME}/error` topic

2. **MQTT Output Node** (1):
   - Publishes to command, ota, and config topics (route by msg.topic)

3. **Dashboard Nodes**:
   - `ui_text` - For text displays
   - `ui_gauge` - For sensor gauges
   - `ui_chart` - For historical trends
   - `ui_button` - For command buttons
   - `ui_led` - For status indicators
   - `ui_notification` - For alerts
   - `ui_template` - For custom HTML/CSS

4. **Function Nodes**:
   - Parse incoming JSON from MQTT topics
   - Format outgoing command payloads
   - Data validation and transformation

5. **Storage Nodes**:
   - Context storage for historical data
   - File storage for data export

---

## JSON Payload Examples

### Status Response
```json
{
  "type": "status",
  "timestamp": "2025-10-02 14:30:00",
  "uptime": "48h",
  "free_heap": 123456,
  "valve_state": "SPRAY",
  "counter": 42,
  "error_condition": false,
  "imsi": "123456789012345"
}
```

### Sensor Data
```json
{
  "timestamp": "2025-10-02 14:30:00",
  "temperature": 25.5,
  "humidity": 65.2,
  "wind": 3.2,
  "pressure": 1013.25,
  "water_temp": 18.3,
  "voltage": 12.4
}
```

### Command Response
```json
{
  "command": "demo",
  "status": "success",
  "message": "Demo mode activated",
  "timestamp": "2025-10-02 14:30:00"
}
```

### OTA Status
```json
{
  "status": "downloading",
  "message": "Download progress: 45%",
  "progress": 45
}
```

---

## UI Design Guidelines

### Color Scheme
- **Primary**: Blue (#0066cc) - Normal operations
- **Success**: Green (#00aa00) - Successful operations
- **Warning**: Orange (#ff8800) - Warnings
- **Error**: Red (#cc0000) - Errors
- **Info**: Gray (#666666) - Informational

### Layout
- Use grid layout with responsive design
- Group related controls in panels
- Prioritize most-used controls at top
- Use tabs for advanced features

### User Experience
- Confirmation dialogs for destructive actions (reboot, clear, calibrate)
- Visual feedback for button presses
- Toast notifications for command results
- Auto-refresh data displays
- Connection status always visible

---

## Security Considerations

1. **Authentication**
   - Enable Node-RED dashboard authentication
   - Use MQTT username/password (already configured: aoi:4201)

2. **Access Control**
   - Read-only view for monitoring
   - Admin role required for commands and OTA

3. **Audit Log**
   - Log all command executions
   - Track user actions with timestamps

---

## Implementation Notes

1. Install required Node-RED modules:
   - `node-red-dashboard`
   - `node-red-contrib-mqtt-broker` (if not using built-in)

2. MQTT Broker Configuration:
   - Host: `44.194.157.172`
   - Port: `1883`
   - Username: `aoi`
   - Password: `4201`

3. Topic wildcards for multi-site monitoring:
   - Subscribe: `air/+/data`, `air/+/status`, `air/+/error`
   - Site selector dropdown in UI

4. Data retention:
   - Store last 7 days of sensor data
   - Automatic cleanup of old data
