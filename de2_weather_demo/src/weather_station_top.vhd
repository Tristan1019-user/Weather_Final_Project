library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity weather_station_top is
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
        GPIO        : inout std_logic_vector(35 downto 0)
    );
end entity;

architecture rtl of weather_station_top is
    signal reset_n       : std_logic;
    signal clk25         : std_logic := '0';
    signal sec_tick      : std_logic := '0';
    signal div2          : std_logic := '0';
    signal sec_count     : unsigned(25 downto 0) := (others => '0');

    signal temp_x10      : integer range 0 to 999 := 235;
    signal humid_x10     : integer range 0 to 1000 := 520;
    signal press_hpa     : integer range 300 to 1200 := 1013;
    signal pm25_x10      : integer range 0 to 2000 := 85;
    signal light_pct     : integer range 0 to 100 := 50;
    signal sensor_valid  : std_logic := '0';
    signal sensor_tick   : std_logic := '0';
    signal bus_active    : std_logic := '0';

    signal i2c_sda_oen   : std_logic;
    signal i2c_scl_oen   : std_logic;
    signal i2c_sda_in    : std_logic;
    signal i2c_scl_in    : std_logic;
    signal uart_tx       : std_logic;
    signal uart_rx       : std_logic;

    signal temp_status   : std_logic_vector(1 downto 0);
    signal humid_status  : std_logic_vector(1 downto 0);
    signal press_status  : std_logic_vector(1 downto 0);
    signal pm_status     : std_logic_vector(1 downto 0);

    signal temp_tens     : integer range 0 to 9;
    signal temp_ones     : integer range 0 to 9;
    signal humid_tens    : integer range 0 to 9;
    signal humid_ones    : integer range 0 to 9;
    signal press_thou    : integer range 0 to 9;
    signal press_hund    : integer range 0 to 9;
    signal press_tens    : integer range 0 to 9;
    signal press_ones    : integer range 0 to 9;
begin
    reset_n <= KEY(0);

    process (CLOCK_50, reset_n)
    begin
        if reset_n = '0' then
            div2      <= '0';
            sec_count <= (others => '0');
            sec_tick  <= '0';
        elsif rising_edge(CLOCK_50) then
            div2 <= not div2;
            if sec_count = to_unsigned(49999999, sec_count'length) then
                sec_count <= (others => '0');
                sec_tick  <= '1';
            else
                sec_count <= sec_count + 1;
                sec_tick  <= '0';
            end if;
        end if;
    end process;

    clk25 <= div2;
    VGA_CLK <= clk25;

    GPIO(0) <= '0' when i2c_sda_oen = '0' else 'Z';
    GPIO(1) <= '0' when i2c_scl_oen = '0' else 'Z';
    i2c_sda_in <= GPIO(0);
    i2c_scl_in <= GPIO(1);

    GPIO(2) <= uart_tx;
    uart_rx <= GPIO(3);

    u_sensor_hub : entity work.sensor_hub
        port map (
            clk         => CLOCK_50,
            reset_n     => reset_n,
            demo_mode   => SW(17),
            sec_tick    => sec_tick,
            i2c_sda_in  => i2c_sda_in,
            i2c_scl_in  => i2c_scl_in,
            i2c_sda_oen => i2c_sda_oen,
            i2c_scl_oen => i2c_scl_oen,
            uart_rx     => uart_rx,
            uart_tx     => uart_tx,
            temp_x10    => temp_x10,
            humid_x10   => humid_x10,
            press_hpa   => press_hpa,
            pm25_x10    => pm25_x10,
            light_pct   => light_pct,
            sensor_valid=> sensor_valid,
            sensor_tick => sensor_tick,
            bus_active  => bus_active
        );

    u_status : entity work.status_logic
        port map (
            temp_x10     => temp_x10,
            humid_x10    => humid_x10,
            press_hpa    => press_hpa,
            pm25_x10     => pm25_x10,
            temp_status  => temp_status,
            humid_status => humid_status,
            press_status => press_status,
            pm_status    => pm_status
        );

    u_vga : entity work.vga_dashboard
        port map (
            clk25         => clk25,
            reset_n       => reset_n,
            temp_x10      => temp_x10,
            humid_x10     => humid_x10,
            press_hpa     => press_hpa,
            pm25_x10      => pm25_x10,
            light_pct     => light_pct,
            temp_status   => temp_status,
            humid_status  => humid_status,
            press_status  => press_status,
            pm_status     => pm_status,
            demo_mode     => SW(17),
            sensor_valid  => sensor_valid,
            sensor_tick   => sensor_tick,
            vga_r         => VGA_R,
            vga_g         => VGA_G,
            vga_b         => VGA_B,
            vga_hs        => VGA_HS,
            vga_vs        => VGA_VS,
            vga_blank_n   => VGA_BLANK_N,
            vga_sync_n    => VGA_SYNC_N
        );

    temp_tens  <= (temp_x10 / 100) mod 10;
    temp_ones  <= (temp_x10 / 10) mod 10;
    humid_tens <= (humid_x10 / 100) mod 10;
    humid_ones <= (humid_x10 / 10) mod 10;
    press_thou <= (press_hpa / 1000) mod 10;
    press_hund <= (press_hpa / 100) mod 10;
    press_tens <= (press_hpa / 10) mod 10;
    press_ones <= press_hpa mod 10;

    u_hex0 : entity work.hex7seg port map (value => temp_ones, seg => HEX0);
    u_hex1 : entity work.hex7seg port map (value => temp_tens, seg => HEX1);
    u_hex2 : entity work.hex7seg port map (value => humid_ones, seg => HEX2);
    u_hex3 : entity work.hex7seg port map (value => humid_tens, seg => HEX3);
    u_hex4 : entity work.hex7seg port map (value => press_ones, seg => HEX4);
    u_hex5 : entity work.hex7seg port map (value => press_tens, seg => HEX5);
    u_hex6 : entity work.hex7seg port map (value => press_hund, seg => HEX6);
    u_hex7 : entity work.hex7seg port map (value => press_thou, seg => HEX7);

    LEDG(0) <= sensor_valid;
    LEDG(1) <= bus_active;
    LEDG(2) <= sensor_tick;
    LEDG(3) <= SW(17);
    LEDG(4) <= temp_status(1);
    LEDG(5) <= humid_status(1);
    LEDG(6) <= press_status(1);
    LEDG(7) <= pm_status(1);
    LEDG(8) <= sec_tick;
end architecture;
