library ieee;
use ieee.std_logic_1164.all;

entity sht45_stub is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        poll_tick   : in  std_logic;
        i2c_sda_in  : in  std_logic;
        i2c_scl_in  : in  std_logic;
        i2c_sda_oen : out std_logic;
        i2c_scl_oen : out std_logic;
        temp_x10    : out integer range 0 to 999;
        humid_x10   : out integer range 0 to 1000;
        valid       : out std_logic;
        active      : out std_logic
    );
end entity;

architecture rtl of sht45_stub is
begin
    process (clk, reset_n)
    begin
        if reset_n = '0' then
            i2c_sda_oen <= '1';
            i2c_scl_oen <= '1';
            temp_x10    <= 241;
            humid_x10   <= 507;
            valid       <= '0';
            active      <= '0';
        elsif rising_edge(clk) then
            i2c_sda_oen <= '1';
            i2c_scl_oen <= '1';
            active      <= '0';
            if poll_tick = '1' then
                -- TODO: replace with a real SHT45 I2C transaction on JP4 EX_IO[0:1].
                temp_x10  <= 241;
                humid_x10 <= 507;
                valid     <= '1';
                active    <= '1';
            end if;
        end if;
    end process;
end architecture;
