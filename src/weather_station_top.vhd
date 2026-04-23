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
        EX_IO       : inout std_logic_vector(6 downto 0);
        GPIO        : inout std_logic_vector(35 downto 0)
    );
end entity;

architecture rtl of weather_station_top is
    signal reset_n          : std_logic;
    signal div2             : std_logic := '0';
    signal sec_count        : unsigned(25 downto 0) := (others => '0');
    signal sec_tick         : std_logic := '0';

    signal temp_x10         : integer range 0 to 999 := 0;
    signal humid_x10        : integer range 0 to 1000 := 0;
    signal press_hpa        : integer range 300 to 1200 := 1013;
    signal pm25_x10         : integer range 0 to 2000 := 0;
    signal light_pct        : integer range 0 to 100 := 50;
    signal sensor_valid     : std_logic := '0';
    signal sensor_tick      : std_logic := '0';
    signal bus_active       : std_logic := '0';
    signal sht_valid        : std_logic := '0';
    signal bmp_valid        : std_logic := '0';
    signal sps_valid        : std_logic := '0';
    signal sht_active       : std_logic := '0';
    signal bmp_active       : std_logic := '0';
    signal sps_active       : std_logic := '0';
    signal host_link_active : std_logic := '0';
    signal host_uart_rx     : std_logic := '1';

    signal local_temp_status  : std_logic_vector(1 downto 0);
    signal local_humid_status : std_logic_vector(1 downto 0);
    signal local_press_status : std_logic_vector(1 downto 0);
    signal local_pm_status    : std_logic_vector(1 downto 0);
    signal hike_status        : std_logic_vector(1 downto 0) := "00";

    signal temp_tens        : integer range 0 to 9;
    signal temp_ones        : integer range 0 to 9;
    signal humid_tens       : integer range 0 to 9;
    signal humid_ones       : integer range 0 to 9;
    signal press_thou       : integer range 0 to 9;
    signal press_hund       : integer range 0 to 9;
    signal press_tens       : integer range 0 to 9;
    signal press_ones       : integer range 0 to 9;
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

    VGA_CLK <= div2;

    -- Keep unused legacy sensor pins high-impedance.
    EX_IO <= (others => 'Z');
    GPIO  <= (others => 'Z');

    -- ESP32 UART -> DE2-115 GPIO(7) / PIN_AE16
    host_uart_rx <= GPIO(7);

    u_bridge : entity work.esp_uart_sensor_bridge
        port map (
            clk          => CLOCK_50,
            reset_n      => reset_n,
            sec_tick     => sec_tick,
            uart_rx      => host_uart_rx,
            temp_x10     => temp_x10,
            humid_x10    => humid_x10,
            press_hpa    => press_hpa,
            pm25_x10     => pm25_x10,
            light_pct    => light_pct,
            sht_valid_o  => sht_valid,
            bmp_valid_o  => bmp_valid,
            sps_valid_o  => sps_valid,
            sht_active_o => sht_active,
            bmp_active_o => bmp_active,
            sps_active_o => sps_active,
            sensor_valid => sensor_valid,
            sensor_tick  => sensor_tick,
            bus_active   => bus_active,
            link_active  => host_link_active
        );

    u_status_local : entity work.status_logic
        port map (
            temp_x10     => temp_x10,
            humid_x10    => humid_x10,
            press_hpa    => press_hpa,
            pm25_x10     => pm25_x10,
            temp_status  => local_temp_status,
            humid_status => local_humid_status,
            press_status => local_press_status,
            pm_status    => local_pm_status
        );

    process(local_temp_status, local_humid_status, local_press_status, local_pm_status)
        variable red_count    : integer range 0 to 4;
        variable orange_count : integer range 0 to 4;
    begin
        red_count    := 0;
        orange_count := 0;

        if local_temp_status = "10" then
            red_count := red_count + 1;
        elsif local_temp_status = "01" then
            orange_count := orange_count + 1;
        end if;

        if local_humid_status = "10" then
            red_count := red_count + 1;
        elsif local_humid_status = "01" then
            orange_count := orange_count + 1;
        end if;

        if local_press_status = "10" then
            red_count := red_count + 1;
        elsif local_press_status = "01" then
            orange_count := orange_count + 1;
        end if;

        if local_pm_status = "10" then
            red_count := red_count + 1;
        elsif local_pm_status = "01" then
            orange_count := orange_count + 1;
        end if;

        if red_count >= 2 then
            hike_status <= "10";      -- NO
        elsif (red_count = 1) or (orange_count >= 2) then
            hike_status <= "01";      -- MAYBE
        else
            hike_status <= "00";      -- YES
        end if;
    end process;

    u_vga : entity work.vga_dashboard
        port map (
            clk25        => div2,
            reset_n      => reset_n,
            temp_x10     => temp_x10,
            humid_x10    => humid_x10,
            press_hpa    => press_hpa,
            pm25_x10     => pm25_x10,
            light_pct    => light_pct,
            temp_status  => local_temp_status,
            humid_status => local_humid_status,
            press_status => local_press_status,
            pm_status    => local_pm_status,
            hike_status  => hike_status,
            demo_mode    => SW(5),
            sensor_valid => sensor_valid,
            sensor_tick  => sensor_tick,
            sw           => SW(5 downto 0),
            vga_r        => VGA_R,
            vga_g        => VGA_G,
            vga_b        => VGA_B,
            vga_hs       => VGA_HS,
            vga_vs       => VGA_VS,
            vga_blank_n  => VGA_BLANK_N,
            vga_sync_n   => VGA_SYNC_N
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

    LEDG(0) <= sht_valid;
    LEDG(1) <= bmp_valid;
    LEDG(2) <= sps_valid;
    LEDG(3) <= sensor_valid;
    LEDG(4) <= sht_active;
    LEDG(5) <= bmp_active;
    LEDG(6) <= sps_active;
    LEDG(7) <= host_link_active;
    LEDG(8) <= bus_active;
end architecture;

