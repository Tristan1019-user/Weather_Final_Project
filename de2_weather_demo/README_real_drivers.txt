DE2-115 Weather Station Project with real sensor drivers

Top-level entity:
  FPGA_Final_Project_Weather

Included real protocol modules:
  - src/sht45_stub.vhd        (real SHT45 I2C driver on JP4 EX_IO[0:1])
  - src/bmp280_stub.vhd       (real BMP280 I2C driver on JP5 GPIO[4:5])
  - src/sps30_uart_stub.vhd   (real SPS30 UART SHDLC driver on JP5 GPIO[2:3])
  - src/i2c_byte_master.vhd   (shared byte-level I2C engine)
  - src/uart_tx.vhd           (115200 8N1 transmitter)
  - src/uart_rx.vhd           (115200 8N1 receiver)
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

Board notes:
  - JP4 SHT45 bus is 3.3V.
  - JP5 BMP280 bus is 3.3V.
  - SPS30 must be powered from 5V, but UART logic lines still go to 3.3V FPGA I/O.
  - BMP280 CSB should be tied high for I2C and SDO should set the address.
    The driver probes both 0x76 and 0x77.

Runtime behavior:
  - SHT45 is polled once per second.
  - BMP280 reads calibration at startup, then runs one forced conversion per second.
  - SPS30 waits 1 second after power-up, sends Start Measurement, waits 2 seconds,
    then polls measured values once per second.
  - SW[17] = 1 keeps the VGA dashboard in demo mode.
  - SW[17] = 0 uses live sensor values.

Bring-up order:
  1. Confirm VGA still works.
  2. Set SW[17] = 0.
  3. Connect SHT45 and look for temperature/humidity changes.
  4. Connect BMP280 and confirm pressure updates.
  5. Connect SPS30 last.

If your existing Quartus project uses a different top-level name, either:
  - change the project top-level to FPGA_Final_Project_Weather, or
  - use the included de2_weather_demo.qsf where TOP_LEVEL_ENTITY is already set.
