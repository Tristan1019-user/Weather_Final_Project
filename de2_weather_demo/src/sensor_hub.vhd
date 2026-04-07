library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sensor_hub is
    port (
        clk          : in  std_logic;
        reset_n      : in  std_logic;
        demo_mode    : in  std_logic;
        sec_tick     : in  std_logic;
        i2c_sda_in   : in  std_logic;
        i2c_scl_in   : in  std_logic;
        i2c_sda_oen  : out std_logic;
        i2c_scl_oen  : out std_logic;
        uart_rx      : in  std_logic;
        uart_tx      : out std_logic;
        temp_x10     : out integer range 0 to 999;
        humid_x10    : out integer range 0 to 1000;
        press_hpa    : out integer range 300 to 1200;
        pm25_x10     : out integer range 0 to 2000;
        light_pct    : out integer range 0 to 100;
        sensor_valid : out std_logic;
        sensor_tick  : out std_logic;
        bus_active   : out std_logic
    );
end entity;

architecture rtl of sensor_hub is
    signal demo_temp_x10   : integer range 0 to 999 := 235;
    signal demo_humid_x10  : integer range 0 to 1000 := 520;
    signal demo_press_hpa  : integer range 300 to 1200 := 1013;
    signal demo_pm25_x10   : integer range 0 to 2000 := 85;
    signal demo_light_pct  : integer range 0 to 100 := 50;
    signal dir             : std_logic := '0';
    signal heartbeat       : std_logic := '0';

    signal sht_temp_x10    : integer range 0 to 999 := 240;
    signal sht_humid_x10   : integer range 0 to 1000 := 500;
    signal bmp_press_hpa   : integer range 300 to 1200 := 1012;
    signal sps_pm25_x10    : integer range 0 to 2000 := 120;
    signal sht_valid       : std_logic := '0';
    signal bmp_valid       : std_logic := '0';
    signal sps_valid       : std_logic := '0';
    signal tick_pulse      : std_logic := '0';
    signal active_i2c      : std_logic := '0';
    signal active_uart     : std_logic := '0';
begin
    process (clk, reset_n)
    begin
        if reset_n = '0' then
            demo_temp_x10  <= 235;
            demo_humid_x10 <= 520;
            demo_press_hpa <= 1013;
            demo_pm25_x10  <= 85;
            demo_light_pct <= 50;
            dir            <= '0';
            heartbeat      <= '0';
            tick_pulse     <= '0';
        elsif rising_edge(clk) then
            tick_pulse <= '0';
            if sec_tick = '1' then
                heartbeat <= not heartbeat;
                tick_pulse <= '1';
                if dir = '0' then
                    demo_temp_x10  <= demo_temp_x10 + 3;
                    demo_humid_x10 <= demo_humid_x10 + 4;
                    demo_press_hpa <= demo_press_hpa + 1;
                    demo_pm25_x10  <= demo_pm25_x10 + 7;
                    demo_light_pct <= demo_light_pct + 2;
                    if demo_temp_x10 >= 295 then
                        dir <= '1';
                    end if;
                else
                    demo_temp_x10  <= demo_temp_x10 - 2;
                    demo_humid_x10 <= demo_humid_x10 - 3;
                    demo_press_hpa <= demo_press_hpa - 1;
                    demo_pm25_x10  <= demo_pm25_x10 - 5;
                    demo_light_pct <= demo_light_pct - 2;
                    if demo_temp_x10 <= 190 then
                        dir <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- These are compileable starter stubs.
    -- Replace their internals with real sensor transactions as you bring each sensor up.
    u_sht45 : entity work.sht45_stub
        port map (
            clk         => clk,
            reset_n     => reset_n,
            poll_tick    => sec_tick,
            i2c_sda_in  => i2c_sda_in,
            i2c_scl_in  => i2c_scl_in,
            temp_x10    => sht_temp_x10,
            humid_x10   => sht_humid_x10,
            valid       => sht_valid,
            active      => active_i2c
        );

    u_bmp280 : entity work.bmp280_stub
        port map (
            clk         => clk,
            reset_n     => reset_n,
            poll_tick   => sec_tick,
            i2c_sda_in  => i2c_sda_in,
            i2c_scl_in  => i2c_scl_in,
            press_hpa   => bmp_press_hpa,
            valid       => bmp_valid,
            active      => open
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

    i2c_sda_oen <= '1';
    i2c_scl_oen <= '1';

    temp_x10 <= demo_temp_x10 when demo_mode = '1' else sht_temp_x10;
    humid_x10 <= demo_humid_x10 when demo_mode = '1' else sht_humid_x10;
    press_hpa <= demo_press_hpa when demo_mode = '1' else bmp_press_hpa;
    pm25_x10 <= demo_pm25_x10 when demo_mode = '1' else sps_pm25_x10;
    light_pct <= demo_light_pct when demo_mode = '1' else 50;

    sensor_valid <= '1' when demo_mode = '1' else (sht_valid and bmp_valid and sps_valid);
    sensor_tick <= tick_pulse;
    bus_active <= active_i2c or active_uart or heartbeat;
end architecture;
