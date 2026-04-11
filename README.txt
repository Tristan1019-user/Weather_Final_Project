DE2-115 weather station real-driver project

What this is
- A Quartus project for the DE2-115 using real SHT45, BMP280, and SPS30 driver blocks.
- It keeps the existing VGA dashboard and HEX displays.
- It now also includes a dedicated host UART so the FPGA can send sensor data to a laptop/server,
  receive a returned classification, and display that result on VGA.

What this is not
- This is not the older demo/stub-only branch.
- This is not a finished ML backend.
- The host UART path is the transport layer that lets your laptop and server own the AI side.

Current sensor/header use
- EX_IO[0] / EX_IO[1] = SHT45 I2C
- GPIO[2] / GPIO[3]   = SPS30 UART
- GPIO[4] / GPIO[5]   = BMP280 I2C
- GPIO[6] / GPIO[7]   = new host UART for the USB-TTL adapter
- GPIO[0]             = optional debug UART TX only

USB-TTL adapter wiring for the host path
- Set the adapter to 3.3V TTL mode
- GPIO[6] FPGA TX -> adapter RXD
- GPIO[7] FPGA RX <- adapter TXD
- adapter GND -> board ground
- leave adapter VCC disconnected
- do not put 5V logic into FPGA pins

Runtime behavior
- Sensors run as before.
- Once per second, the FPGA emits a compact telemetry line over the host UART.
- The laptop/server can return a compact classification line.
- VGA uses the remote classification while it is fresh.
- If the remote result goes stale, the design automatically falls back to the local status classifier.

Protocol summary
- FPGA -> laptop:
  - D,ss,ttt,hhhh,pppp,mmmm,lll,v,0
- laptop/server -> FPGA:
  - C,t,h,p,m
- status digits:
  - 0 -> "00"
  - 1 -> "01"
  - 2 -> "10"

Files most relevant to this path
- src/weather_station_top.vhd
- src/vga_dashboard.vhd
- src/host_uart_link.vhd
- src/uart_tx.vhd
- src/uart_rx.vhd
- README_real_drivers.txt

Recommended next step
- Compile this project, hook the adapter to GPIO[6]/GPIO[7], and test the host link before sensor validation.
