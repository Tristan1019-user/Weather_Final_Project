# Weather Final Project

Current DE2-115 Quartus build synced to the active working project.

This repo now matches the live `FPGA_Final` file set instead of the older raw-sensor baseline.

## Current build status
- Quartus revision: `FPGA_Final`
- Top-level entity: `FPGA_Final_Project_Weather`
- Board: DE2-115 / Cyclone IV E
- Clock constraint: `CLOCK_50` at 50 MHz

## Included project files
- `FPGA_Final.qpf`
- `FPGA_Final.qsf`
- `FPGA_Final.sdc`
- `DE2_115_pin_assignments (1).csv`
- `src/FPGA_Final_Project_Weather.vhd`
- `src/weather_station_top.vhd`
- `src/esp_uart_sensor_bridge.vhd`
- `src/vga_dashboard.vhd`
- `src/weather_icons_pkg.vhd`
- `src/uart_rx.vhd`
- `src/uart_tx.vhd`
- `src/status_logic.vhd`
- `src/hex7seg.vhd`
- `src/debug_uart_telemetry.vhd`
- `src/vga_timing_640x480.vhd`

## Active design
- Sensor data comes in over UART from the external ESP32-side bridge.
- `src/weather_station_top.vhd` is the current top implementation synced from the latest `weather_station_top_vga_icons_compatible.vhd` working file.
- `src/esp_uart_sensor_bridge.vhd` is the current parser synced from `esp_uart_sensor_bridge_daynight.vhd`.
- VGA uses the icon-enabled dashboard build.
- HEX displays show temperature, humidity, and pressure digits.
- LEDs indicate sensor validity/activity, host link activity, and parser activity.

## UART input path
- FPGA UART input uses `GPIO[7]`.
- The bridge parser expects lines in this form:
  - `WS,sht,bmp,sps,temp,humid,press,pm25,daynight`
- Example shape:
  - `WS,1,1,1,235,520,1013,085,1`

## Notes on repo normalization
The live Quartus working folder referenced several files as `../...` from outside the project directory. In this repo they have been normalized into tracked repo paths:
- `weather_station_top_vga_icons_compatible.vhd` → `src/weather_station_top.vhd`
- `esp_uart_sensor_bridge_daynight.vhd` → `src/esp_uart_sensor_bridge.vhd`
- `vga_dashboard.vhd` → `src/vga_dashboard.vhd`
- `weather_icons_pkg.vhd` → `src/weather_icons_pkg.vhd`
- `DE2_115_pin_assignments (1).csv` is tracked at repo root

## Removed from the old baseline
These older files were dropped because they are not part of the active Quartus build anymore:
- `src/bmp280_stub.vhd`
- `src/i2c_byte_master.vhd`
- `src/sensor_hub.vhd`
- `src/sht45_stub.vhd`
- `src/sps30_uart_stub.vhd`
- `src/weather_station_top_esp_uart.vhd`
- `src/patch_time.py`
