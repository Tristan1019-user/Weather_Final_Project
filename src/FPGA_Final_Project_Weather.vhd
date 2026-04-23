library ieee;
use ieee.std_logic_1164.all;

entity FPGA_Final_Project_Weather is
    port (
        CLOCK_50    : in  std_logic;
        KEY         : in  std_logic_vector(3 downto 0);
        SW          : in  std_logic_vector(17 downto 0);
        LEDG        : out std_logic_vector(8 downto 0);
        HEX0        : out std_logic_vector(6 downto 0);
        HEX1        : out std_logic_vector(6 downto 0);
        HEX2        : out std_logic_vector(6 downto 0);
        HEX3        : out std_logic_vector(6 downto 0);
        HEX4        : out std_logic_vector(6 downto 0);
        HEX5        : out std_logic_vector(6 downto 0);
        HEX6        : out std_logic_vector(6 downto 0);
        HEX7        : out std_logic_vector(6 downto 0);
        VGA_R       : out std_logic_vector(7 downto 0);
        VGA_G       : out std_logic_vector(7 downto 0);
        VGA_B       : out std_logic_vector(7 downto 0);
        VGA_HS      : out std_logic;
        VGA_VS      : out std_logic;
        VGA_CLK     : out std_logic;
        VGA_BLANK_N : out std_logic;
        VGA_SYNC_N  : out std_logic;
        EX_IO       : inout std_logic_vector(6 downto 0);
        GPIO        : inout std_logic_vector(35 downto 0)
    );
end entity;

architecture rtl of FPGA_Final_Project_Weather is
begin
    u_top : entity work.weather_station_top
        port map (
            CLOCK_50    => CLOCK_50,
            KEY         => KEY,
            SW          => SW,
            LEDG        => LEDG,
            HEX0        => HEX0,
            HEX1        => HEX1,
            HEX2        => HEX2,
            HEX3        => HEX3,
            HEX4        => HEX4,
            HEX5        => HEX5,
            HEX6        => HEX6,
            HEX7        => HEX7,
            VGA_R       => VGA_R,
            VGA_G       => VGA_G,
            VGA_B       => VGA_B,
            VGA_HS      => VGA_HS,
            VGA_VS      => VGA_VS,
            VGA_CLK     => VGA_CLK,
            VGA_BLANK_N => VGA_BLANK_N,
            VGA_SYNC_N  => VGA_SYNC_N,
            EX_IO       => EX_IO,
            GPIO        => GPIO
        );
end architecture;

