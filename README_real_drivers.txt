DE2-115 Weather Station Project with real sensor drivers and host-AI return path

Top-level entity:
  FPGA_Final_Project_Weather

Included real protocol modules:
  - src/sht45_stub.vhd        (real SHT45 I2C driver on JP4 EX_IO[0:1])
  - src/bmp280_stub.vhd       (real BMP280 I2C driver on JP5 GPIO[4:5])
  - src/sps30_uart_stub.vhd   (real SPS30 UART SHDLC driver on JP5 GPIO[2:3])
  - src/i2c_byte_master.vhd   (shared byte-level I2C engine)
  - src/uart_tx.vhd           (115200 8N1 transmitter)
  - src/uart_rx.vhd           (115200 8N1 receiver)
  - src/host_uart_link.vhd    (bidirectional laptop/server link for remote classification)
  - src/debug_uart_telemetry.vhd (optional one-way debug telemetry on GPIO[0])
  - src/FPGA_Final_Project_Weather.vhd (wrapper top-level)

Header mapping:
  JP4 / EX_IO:
    EX_IO[0] = SHT45 SDA
    EX_IO[1] = SHT45 SCL

  JP5 / GPIO:
    GPIO[2] = FPGA TX -> SPS30 RX
    GPIO[3] = FPGA RX <- SPS30 TX
    GPIO[4] = BMP280 SDA
    GPIO[5] = BMP280 SCL
    GPIO[6] = FPGA host UART TX -> USB-TTL adapter RXD
    GPIO[7] = FPGA host UART RX <- USB-TTL adapter TXD

Board notes:
  - JP4 SHT45 bus is 3.3V.
  - JP5 BMP280 bus is 3.3V.
  - SPS30 must be powered from 5V, but UART logic lines still go to 3.3V FPGA I/O.
  - BMP280 CSB should be tied high for I2C and SDO should set the address.
    The driver probes both 0x76 and 0x77.
  - The USB-TTL adapter must be in 3.3V TTL mode before you connect it to GPIO[6:7].
  - Use a common ground, cross TX/RX, and do not drive 5V logic into the FPGA pins.
  - Leave adapter VCC disconnected unless you explicitly know you need it.

Runtime behavior:
  - The live sensor path is always active.
  - SHT45 is polled once per second.
  - SHT45 hardware keeps CRC checking, but temperature/humidity conversion is a timing-safe upper-byte approximation.
  - BMP280 reads calibration at startup, then runs one forced conversion per second.
  - BMP280 pressure is currently a timing-safe raw-code estimate in hardware, not the full Bosch compensation chain.
  - SPS30 waits 1 second after power-up, sends Start Measurement, waits 2 seconds,
    then polls measured values once per second.
  - SPS30 response validation in hardware is timing-safe and lightweight
    (header/length based, not full frame checksum).
  - SPS30 PM2.5 decoding is currently a timing-safe float approximation in hardware,
    not a full IEEE-754 conversion pipeline.
  - For maximum timing margin and on-board reliability, the active build currently uses only the local FPGA classifier.
  - The host UART / remote-classifier path remains in the source tree, but is disabled in the top-level build.
  - The older optional debug-only UART stream on GPIO[0] has been removed to keep timing and hardware behavior simpler.
  - When a fresh remote classification is present, VGA uses it.
  - If the remote result stops arriving for a few seconds, VGA automatically falls
    back to the local threshold classifier in status_logic.vhd.

Host UART protocol on GPIO[6:7]:
  Outbound from FPGA:
    D,ss,ttt,hhhh,pppp,mmmm,lll,v,0

  Example:
    D,07,235,0520,1013,0085,050,1,0

  Fields:
    ss   = sequence number 00..99
    ttt  = temperature x10
    hhhh = humidity x10
    pppp = pressure in hPa
    mmmm = PM2.5 x10
    lll  = light percentage
    v    = combined sensor_valid flag
    final 0 = reserved field kept for host compatibility

  Inbound back to FPGA:
    C,t,h,p,m

  Example:
    C,0,1,0,2

  Digit mapping:
    0 -> VHDL status code "00"
    1 -> VHDL status code "01"
    2 -> VHDL status code "10"

VGA behavior:
  - Purple top banner = fresh remote/server classification is active
  - Green top banner  = local threshold fallback is active with valid sensors
  - Red top banner    = sensors are not yet valid
  - Cyan square near upper-right = remote classification freshness
  - White/gray square near upper-right = 1 Hz heartbeat

LEDG mapping:
  - LEDG[0] = SHT45 valid
  - LEDG[1] = BMP280 valid
  - LEDG[2] = SPS30 valid
  - LEDG[3] = all sensors valid
  - LEDG[4] = SHT45 activity toggle
  - LEDG[5] = BMP280 activity toggle
  - LEDG[6] = SPS30 activity toggle
  - LEDG[7] = host UART link active
  - LEDG[8] = remote classification fresh

Optional debug UART:
  - GPIO[0] still outputs the old one-way telemetry stream.
  - That is now optional and separate from the real host-AI link on GPIO[6:7].
  - If you only have one USB-TTL adapter, use GPIO[6:7], not GPIO[0].

Bring-up order:
  1. Confirm VGA still works.
  2. Confirm the real sensor drivers still compile and route.
  3. Connect the USB-TTL adapter to GPIO[6:7] and test the host link first.
  4. Run the included mock host classifier or your laptop bridge.
  5. Verify the VGA top banner turns purple and LEDG[8] goes high.
  6. Then reconnect and validate SHT45, BMP280, and SPS30 one at a time.

Project files you must keep in Quartus:
  - src/host_uart_link.vhd
  - src/uart_tx.vhd
  - src/uart_rx.vhd
  - src/weather_station_top.vhd
  - src/vga_dashboard.vhd

If your existing Quartus project uses a different top-level name, either:
  - change the project top-level to FPGA_Final_Project_Weather, or
  - use the included QSF where TOP_LEVEL_ENTITY is already set.
