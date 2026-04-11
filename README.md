# Weather Final Project

Timing-clean DE2-115 weather station baseline.

This repo is intentionally trimmed to the current known-good Quartus project only.

## Current build status
- Quartus revision: `FPGA_Final`
- Top-level entity: `FPGA_Final_Project_Weather`
- Timing: clean at 50 MHz
- Worst slow-corner setup slack: `+9.162 ns`
- Hold and pulse width: passing

## What is included
- `FPGA_Final.qpf`
- `FPGA_Final.qsf`
- `FPGA_Final.sdc`
- `src/FPGA_Final_Project_Weather.vhd`
- `src/weather_station_top.vhd`
- `src/sensor_hub.vhd`
- `src/i2c_byte_master.vhd`
- `src/sht45_stub.vhd`
- `src/bmp280_stub.vhd`
- `src/sps30_uart_stub.vhd`
- `src/status_logic.vhd`
- `src/vga_dashboard.vhd`
- `src/vga_timing_640x480.vhd`
- `src/hex7seg.vhd`

## Active hardware paths in this baseline
- SHT45 over JP4 / `EX_IO[0:1]`
- BMP280 over JP5 / `GPIO[4:5]`
- SPS30 UART over JP5 / `GPIO[2:3]`
- VGA dashboard output
- HEX displays and board LEDs

## Intentionally excluded from this cleaned baseline
These were removed from the tracked project because they are not part of the current reliable build:
- old `de2_weather_demo/` layout
- Quartus `db/` outputs
- optional host UART / remote-ML return path
- optional debug UART telemetry path

## Bring-up order
1. Program the FPGA with the `FPGA_Final` revision.
2. Confirm VGA output is stable.
3. Confirm HEX and LEDs update.
4. Validate SHT45.
5. Validate BMP280.
6. Validate SPS30.

## Notes
- This repo is the hardware-validation baseline.
- If server-side ML is added back later, do it as a separate revision or branch from this clean baseline.
