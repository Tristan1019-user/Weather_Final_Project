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
    signal reset_n             : std_logic;
    signal pix_ce              : std_logic := '0';
    signal sec_tick            : std_logic := '0';
    signal div2                : std_logic := '0';
    signal sec_count           : unsigned(25 downto 0) := (others => '0');

    signal temp_x10            : integer range 0 to 999 := 0;
    signal humid_x10           : integer range 0 to 1000 := 0;
    signal press_hpa           : integer range 300 to 1200 := 300;
    signal pm25_x10            : integer range 0 to 2000 := 0;
    signal light_pct           : integer range 0 to 100 := 50;
    signal sensor_valid        : std_logic := '0';
    signal sensor_tick         : std_logic := '0';
    signal bus_active          : std_logic := '0';
    signal sht_valid           : std_logic := '0';
    signal bmp_valid           : std_logic := '0';
    signal sps_valid           : std_logic := '0';
    signal sht_active          : std_logic := '0';
    signal bmp_active          : std_logic := '0';
    signal sps_active          : std_logic := '0';

    signal sht_sda_oen         : std_logic;
    signal sht_scl_oen         : std_logic;
    signal sht_sda_in          : std_logic;
    signal sht_scl_in          : std_logic;

    signal bmp_sda_oen         : std_logic;
    signal bmp_scl_oen         : std_logic;
    signal bmp_sda_in          : std_logic;
    signal bmp_scl_in          : std_logic;

    signal sps_uart_tx         : std_logic;
    signal sps_uart_rx         : std_logic;
    signal host_uart_tx        : std_logic := '1';
    signal host_uart_rx        : std_logic;
    signal host_link_active    : std_logic := '0';
    signal remote_fresh        : std_logic := '0';

    signal ex_io_drive         : std_logic_vector(6 downto 0) := (others => 'Z');
    signal gpio_drive          : std_logic_vector(35 downto 0) := (others => 'Z');

    signal local_temp_status   : std_logic_vector(1 downto 0);
    signal local_humid_status  : std_logic_vector(1 downto 0);
    signal local_press_status  : std_logic_vector(1 downto 0);
    signal local_pm_status     : std_logic_vector(1 downto 0);
    signal remote_temp_status  : std_logic_vector(1 downto 0);
    signal remote_humid_status : std_logic_vector(1 downto 0);
    signal remote_press_status : std_logic_vector(1 downto 0);
    signal remote_pm_status    : std_logic_vector(1 downto 0);
    signal disp_temp_status    : std_logic_vector(1 downto 0);
    signal disp_humid_status   : std_logic_vector(1 downto 0);
    signal disp_press_status   : std_logic_vector(1 downto 0);
    signal disp_pm_status      : std_logic_vector(1 downto 0);

    signal temp_tens           : integer range 0 to 9;
    signal temp_ones           : integer range 0 to 9;
    signal humid_tens          : integer range 0 to 9;
    signal humid_ones          : integer range 0 to 9;
    signal press_thou          : integer range 0 to 9;
    signal press_hund          : integer range 0 to 9;
    signal press_tens          : integer range 0 to 9;
    signal press_ones          : integer range 0 to 9;
begin
    reset_n <= KEY(0);

    process (CLOCK_50, reset_n)
    begin
        if reset_n = '0' then
            div2      <= '0';
            pix_ce    <= '0';
            sec_count <= (others => '0');
            sec_tick  <= '0';
        elsif rising_edge(CLOCK_50) then
            pix_ce <= div2;
            div2   <= not div2;
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

    process (sht_sda_oen, sht_scl_oen, bmp_sda_oen, bmp_scl_oen, sps_uart_tx, host_uart_tx)
    begin
        ex_io_drive <= (others => 'Z');
        gpio_drive  <= (others => 'Z');

        if sht_sda_oen = '0' then
            ex_io_drive(0) <= '0'; -- JP4 pin 13 / PIN_J10
        end if;

        if sht_scl_oen = '0' then
            ex_io_drive(1) <= '0'; -- JP4 pin 11 / PIN_J14
        end if;

        gpio_drive(2) <= sps_uart_tx;   -- PIN_AB21 -> SPS30 RX

        if bmp_sda_oen = '0' then
            gpio_drive(4) <= '0'; -- PIN_AC21 -> BMP280 SDA
        end if;

        if bmp_scl_oen = '0' then
            gpio_drive(5) <= '0'; -- PIN_Y16 -> BMP280 SCL
        end if;

        gpio_drive(6) <= host_uart_tx; -- PIN_AD21 -> host adapter RXD
    end process;

    EX_IO <= ex_io_drive;
    GPIO  <= gpio_drive;

    sht_sda_in  <= EX_IO(0);
    sht_scl_in  <= EX_IO(1);
    bmp_sda_in  <= GPIO(4);
    bmp_scl_in  <= GPIO(5);
    sps_uart_rx <= GPIO(3);                                    -- PIN_Y17  <- SPS30 TX
    host_uart_rx <= GPIO(7);                                   -- PIN_AE16 <- host adapter TXD (currently unused)

    u_sensor_hub : entity work.sensor_hub
        port map (
            clk           => CLOCK_50,
            reset_n       => reset_n,
            sec_tick      => sec_tick,
            sht_sda_in    => sht_sda_in,
            sht_scl_in    => sht_scl_in,
            sht_sda_oen   => sht_sda_oen,
            sht_scl_oen   => sht_scl_oen,
            bmp_sda_in    => bmp_sda_in,
            bmp_scl_in    => bmp_scl_in,
            bmp_sda_oen   => bmp_sda_oen,
            bmp_scl_oen   => bmp_scl_oen,
            uart_rx       => sps_uart_rx,
            uart_tx       => sps_uart_tx,
            temp_x10      => temp_x10,
            humid_x10     => humid_x10,
            press_hpa     => press_hpa,
            pm25_x10      => pm25_x10,
            light_pct     => light_pct,
            sht_valid_o   => sht_valid,
            bmp_valid_o   => bmp_valid,
            sps_valid_o   => sps_valid,
            sht_active_o  => sht_active,
            bmp_active_o  => bmp_active,
            sps_active_o  => sps_active,
            sensor_valid  => sensor_valid,
            sensor_tick   => sensor_tick,
            bus_active    => bus_active
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

    remote_temp_status  <= "00";
    remote_humid_status <= "00";
    remote_press_status <= "00";
    remote_pm_status    <= "00";
    remote_fresh        <= '0';
    host_link_active    <= '0';

    disp_temp_status  <= local_temp_status;
    disp_humid_status <= local_humid_status;
    disp_press_status <= local_press_status;
    disp_pm_status    <= local_pm_status;

    u_vga : entity work.vga_dashboard
        port map (
            clk          => CLOCK_50,
            pix_ce       => pix_ce,
            reset_n      => reset_n,
            temp_x10     => temp_x10,
            humid_x10    => humid_x10,
            press_hpa    => press_hpa,
            pm25_x10     => pm25_x10,
            light_pct    => light_pct,
            temp_status  => disp_temp_status,
            humid_status => disp_humid_status,
            press_status => disp_press_status,
            pm_status    => disp_pm_status,
            sensor_valid => sensor_valid,
            sensor_tick  => sensor_tick,
            remote_fresh => remote_fresh,
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

    -- Keep the sensor-validation LEDs, but dedicate the top LEDs to the new host path.
    LEDG(0) <= sht_valid;
    LEDG(1) <= bmp_valid;
    LEDG(2) <= sps_valid;
    LEDG(3) <= sensor_valid;
    LEDG(4) <= sht_active;
    LEDG(5) <= bmp_active;
    LEDG(6) <= sps_active;
    LEDG(7) <= host_link_active;
    LEDG(8) <= remote_fresh;
end architecture;
