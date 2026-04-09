library ieee;
use ieee.std_logic_1164.all;

entity bmp280_stub is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        poll_tick   : in  std_logic;
        i2c_sda_in  : in  std_logic;
        i2c_scl_in  : in  std_logic;
        i2c_sda_oen : out std_logic;
        i2c_scl_oen : out std_logic;
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
            i2c_sda_oen <= '1';
            i2c_scl_oen <= '1';
            press_hpa   <= 1012;
            valid       <= '0';
            active      <= '0';
        elsif rising_edge(clk) then
            i2c_sda_oen <= '1';
            i2c_scl_oen <= '1';
            active      <= '0';
            if poll_tick = '1' then
                -- TODO: replace with a real BMP280 I2C transaction on JP5 GPIO[4:5].
                press_hpa <= 1012;
                valid     <= '1';
                active    <= '1';
            end if;
        end if;
    end process;
end architecture;
