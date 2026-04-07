library ieee;
use ieee.std_logic_1164.all;

entity bmp280_stub is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        poll_tick   : in  std_logic;
        i2c_sda_in  : in  std_logic;
        i2c_scl_in  : in  std_logic;
        press_hpa   : out integer range 300 to 1200;
        valid       : out std_logic;
        active      : out std_logic
    );
end entity;

architecture rtl of bmp280_stub is
begin
    process (clk, reset_n)
    begin
        if reset_n = '0' then
            press_hpa <= 1012;
            valid     <= '0';
            active    <= '0';
        elsif rising_edge(clk) then
            active <= '0';
            if poll_tick = '1' then
                -- TODO: replace with a real BMP280 I2C transaction.
                -- Good first bring-up step: read chip ID register 0xD0.
                -- After that, configure the sensor and read compensated pressure.
                press_hpa <= 1012;
                valid     <= '1';
                active    <= '1';
            end if;
        end if;
    end process;
end architecture;
