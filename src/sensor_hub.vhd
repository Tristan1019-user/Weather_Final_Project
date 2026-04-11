library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sensor_hub is
    port (
        clk          : in  std_logic;
        reset_n      : in  std_logic;
        sec_tick     : in  std_logic;
        sht_sda_in   : in  std_logic;
        sht_scl_in   : in  std_logic;
        sht_sda_oen  : out std_logic;
        sht_scl_oen  : out std_logic;
        bmp_sda_in   : in  std_logic;
        bmp_scl_in   : in  std_logic;
        bmp_sda_oen  : out std_logic;
        bmp_scl_oen  : out std_logic;
        uart_rx      : in  std_logic;
        uart_tx      : out std_logic;
        temp_x10     : out integer range 0 to 999;
        humid_x10    : out integer range 0 to 1000;
        press_hpa    : out integer range 300 to 1200;
        pm25_x10     : out integer range 0 to 2000;
        light_pct    : out integer range 0 to 100;
        sht_valid_o  : out std_logic;
        bmp_valid_o  : out std_logic;
        sps_valid_o  : out std_logic;
        sht_active_o : out std_logic;
        bmp_active_o : out std_logic;
        sps_active_o : out std_logic;
        sensor_valid : out std_logic;
        sensor_tick  : out std_logic;
        bus_active   : out std_logic
    );
end entity;

architecture rtl of sensor_hub is
    signal heartbeat       : std_logic := '0';

    signal sht_temp_x10    : integer range 0 to 999 := 0;
    signal sht_humid_x10   : integer range 0 to 1000 := 0;
    signal bmp_press_hpa   : integer range 300 to 1200 := 300;
    signal sps_pm25_x10    : integer range 0 to 2000 := 0;
    signal sht_valid       : std_logic := '0';
    signal bmp_valid       : std_logic := '0';
    signal sps_valid       : std_logic := '0';
    signal active_sht      : std_logic := '0';
    signal active_bmp      : std_logic := '0';
    signal active_uart     : std_logic := '0';
    signal prev_active_sht : std_logic := '0';
    signal prev_active_bmp : std_logic := '0';
    signal prev_active_uart: std_logic := '0';
    signal sht_activity    : std_logic := '0';
    signal bmp_activity    : std_logic := '0';
    signal sps_activity    : std_logic := '0';
begin
    process (clk, reset_n)
    begin
        if reset_n = '0' then
            heartbeat <= '0';
            prev_active_sht <= '0';
            prev_active_bmp <= '0';
            prev_active_uart <= '0';
            sht_activity <= '0';
            bmp_activity <= '0';
            sps_activity <= '0';
        elsif rising_edge(clk) then
            if sec_tick = '1' then
                heartbeat <= not heartbeat;
            end if;

            if active_sht = '1' and prev_active_sht = '0' then
                sht_activity <= not sht_activity;
            end if;
            if active_bmp = '1' and prev_active_bmp = '0' then
                bmp_activity <= not bmp_activity;
            end if;
            if active_uart = '1' and prev_active_uart = '0' then
                sps_activity <= not sps_activity;
            end if;

            prev_active_sht <= active_sht;
            prev_active_bmp <= active_bmp;
            prev_active_uart <= active_uart;
        end if;
    end process;

    u_sht45 : entity work.sht45_stub
        port map (
            clk         => clk,
            reset_n     => reset_n,
            poll_tick   => sec_tick,
            i2c_sda_in  => sht_sda_in,
            i2c_scl_in  => sht_scl_in,
            i2c_sda_oen => sht_sda_oen,
            i2c_scl_oen => sht_scl_oen,
            temp_x10    => sht_temp_x10,
            humid_x10   => sht_humid_x10,
            valid       => sht_valid,
            active      => active_sht
        );

    u_bmp280 : entity work.bmp280_stub
        port map (
            clk         => clk,
            reset_n     => reset_n,
            poll_tick   => sec_tick,
            i2c_sda_in  => bmp_sda_in,
            i2c_scl_in  => bmp_scl_in,
            i2c_sda_oen => bmp_sda_oen,
            i2c_scl_oen => bmp_scl_oen,
            press_hpa   => bmp_press_hpa,
            valid       => bmp_valid,
            active      => active_bmp
        );

    u_sps30 : entity work.sps30_uart_stub
        port map (
            clk         => clk,
            reset_n     => reset_n,
            poll_tick   => sec_tick,
            uart_rx     => uart_rx,
            uart_tx     => uart_tx,
            pm25_x10    => sps_pm25_x10,
            valid       => sps_valid,
            active      => active_uart
        );

    temp_x10 <= sht_temp_x10;
    humid_x10 <= sht_humid_x10;
    press_hpa <= bmp_press_hpa;
    pm25_x10 <= sps_pm25_x10;
    light_pct <= 50;

    sht_valid_o <= sht_valid;
    bmp_valid_o <= bmp_valid;
    sps_valid_o <= sps_valid;
    sht_active_o <= sht_activity;
    bmp_active_o <= bmp_activity;
    sps_active_o <= sps_activity;

    sensor_valid <= sht_valid and bmp_valid and sps_valid;
    sensor_tick <= heartbeat;
    bus_active <= sht_valid or bmp_valid or sps_valid;
end architecture;
