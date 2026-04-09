DE2-115 weather station starter project

What this is
- A compileable Quartus starter project for the DE2-115.
- It gives you a working VGA dashboard demo right away.
- It uses SW[17] to select demo mode.
- In demo mode, the values animate so you can prove the board, VGA, HEX displays, and top-level integration.
- It also exposes the sensor wiring pins and includes sensor stub files where you can drop in real I2C and UART transactions next.

What this is not
- This is not a fully tested production-ready sensor implementation.
- The SHT45, BMP280, and SPS30 files are stubs with TODO notes.
- I did this so you can compile now, demo now, and then replace one sensor at a time without rebuilding the whole project.

Board controls
- KEY[0]: active-low reset
- SW[17] = 1: demo mode with animated values
- SW[17] = 0: sensor-stub mode

Displayed values
- HEX1 HEX0: temperature in whole degrees C
- HEX3 HEX2: humidity in whole percent
- HEX7 HEX6 HEX5 HEX4: pressure in hPa

LEDs
- LEDG[0]: sensor_valid
- LEDG[1]: bus_active
- LEDG[2]: sensor_tick
- LEDG[3]: demo mode switch state
- LEDG[4:7]: status bits
- LEDG[8]: one-second heartbeat

Recommended sensor wiring
- GPIO[0] / PIN_AB22: I2C SDA for SHT45 and BMP280
- GPIO[1] / PIN_AC15: I2C SCL for SHT45 and BMP280
- GPIO[2] / PIN_AB21: FPGA UART TX to SPS30 RX
- GPIO[3] / PIN_Y17 : FPGA UART RX from SPS30 TX
- SHT45 power: 3.3V
- BMP280 power: 3.3V
- SPS30 power: 5V
- Common ground everywhere

Important note
- Keep the GPIO bank at 3.3V signaling.
- Do not drive 5V into FPGA GPIO pins.
- If you use a photoresistor later, you need an external ADC.

Suggested next steps
1. Create a new Quartus project and add all VHD files in src.
2. Set weather_station_top as the top-level entity.
3. Import or paste the assignments from de2_weather_demo.qsf.
4. Compile and test VGA with SW[17] set high.
5. Replace sht45_stub.vhd internals with a real SHT45 transaction.
6. Replace bmp280_stub.vhd internals with a real BMP280 transaction.
7. Replace sps30_uart_stub.vhd internals with a real SPS30 UART SHDLC transaction.

Sensor bring-up order
- SHT45 first
- BMP280 second on the same I2C bus
- SPS30 third on UART

If you want to keep the initial demo simple, leave SW[17] high during the first board demo.
