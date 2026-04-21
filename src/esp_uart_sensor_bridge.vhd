library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity esp_uart_sensor_bridge is
    generic (
        CLK_FREQ_HZ     : integer := 50000000;
        BAUD_RATE       : integer := 115200;
        LINK_TIMEOUT_SEC: integer := 5
    );
    port (
        clk          : in  std_logic;
        reset_n      : in  std_logic;
        sec_tick     : in  std_logic;
        uart_rx      : in  std_logic;
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
        bus_active   : out std_logic;
        link_active  : out std_logic
    );
end entity;

architecture rtl of esp_uart_sensor_bridge is
    constant ASCII_W     : std_logic_vector(7 downto 0) := x"57";
    constant ASCII_S     : std_logic_vector(7 downto 0) := x"53";
    constant ASCII_COMMA : std_logic_vector(7 downto 0) := x"2C";
    constant ASCII_CR    : std_logic_vector(7 downto 0) := x"0D";
    constant ASCII_NL    : std_logic_vector(7 downto 0) := x"0A";
    constant ASCII_0     : std_logic_vector(7 downto 0) := x"30";
    constant ASCII_1     : std_logic_vector(7 downto 0) := x"31";
    constant ASCII_9     : std_logic_vector(7 downto 0) := x"39";

    type parse_state_t is (
        ST_WAIT_W,
        ST_WAIT_S,
        ST_WAIT_COMMA0,
        ST_READ_SHT,
        ST_WAIT_COMMA1,
        ST_READ_BMP,
        ST_WAIT_COMMA2,
        ST_READ_SPS,
        ST_WAIT_COMMA3,
        ST_READ_TEMP,
        ST_READ_HUMID,
        ST_READ_PRESS,
        ST_READ_PM25
    );

    function is_digit(value : std_logic_vector(7 downto 0)) return boolean is
    begin
        return (unsigned(value) >= unsigned(ASCII_0)) and (unsigned(value) <= unsigned(ASCII_9));
    end function;

    function digit_to_int(value : std_logic_vector(7 downto 0)) return integer is
    begin
        return to_integer(unsigned(value)) - 48;
    end function;

    function clamp(value : integer; lo : integer; hi : integer) return integer is
    begin
        if value < lo then
            return lo;
        elsif value > hi then
            return hi;
        else
            return value;
        end if;
    end function;

    signal rx_data       : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid      : std_logic := '0';
    signal parse_state   : parse_state_t := ST_WAIT_W;
    signal tick_r        : std_logic := '0';
    signal link_active_r : std_logic := '0';

    signal temp_r        : integer range 0 to 999 := 0;
    signal humid_r       : integer range 0 to 1000 := 0;
    signal press_r       : integer range 300 to 1200 := 1013;
    signal pm25_r        : integer range 0 to 2000 := 0;
    signal light_r       : integer range 0 to 100 := 50;

    signal sht_valid_r   : std_logic := '0';
    signal bmp_valid_r   : std_logic := '0';
    signal sps_valid_r   : std_logic := '0';
begin
    u_uart_rx : entity work.uart_rx
        generic map (
            CLK_FREQ_HZ => CLK_FREQ_HZ,
            BAUD_RATE   => BAUD_RATE
        )
        port map (
            clk        => clk,
            reset_n    => reset_n,
            rx         => uart_rx,
            data_out   => rx_data,
            data_valid => rx_valid
        );

    temp_x10     <= temp_r;
    humid_x10    <= humid_r;
    press_hpa    <= press_r;
    pm25_x10     <= pm25_r;
    light_pct    <= light_r;
    sht_valid_o  <= sht_valid_r;
    bmp_valid_o  <= bmp_valid_r;
    sps_valid_o  <= sps_valid_r;
    sht_active_o <= sht_valid_r and link_active_r;
    bmp_active_o <= bmp_valid_r and link_active_r;
    sps_active_o <= sps_valid_r and link_active_r;
    sensor_valid <= (sht_valid_r or bmp_valid_r or sps_valid_r) and link_active_r;
    sensor_tick  <= tick_r;
    bus_active   <= '1' when parse_state /= ST_WAIT_W else '0';
    link_active  <= link_active_r;

    process (clk, reset_n)
        variable age_sec      : integer range 0 to LINK_TIMEOUT_SEC := 0;
        variable field_acc    : integer range 0 to 32767 := 0;
        variable cand_sht     : std_logic := '0';
        variable cand_bmp     : std_logic := '0';
        variable cand_sps     : std_logic := '0';
        variable cand_temp    : integer := 0;
        variable cand_humid   : integer := 0;
        variable cand_press   : integer := 1013;
        variable cand_pm25    : integer := 0;
    begin
        if reset_n = '0' then
            parse_state   <= ST_WAIT_W;
            tick_r        <= '0';
            link_active_r <= '0';
            temp_r        <= 0;
            humid_r       <= 0;
            press_r       <= 1013;
            pm25_r        <= 0;
            light_r       <= 50;
            sht_valid_r   <= '0';
            bmp_valid_r   <= '0';
            sps_valid_r   <= '0';
            age_sec       := 0;
            field_acc     := 0;
            cand_sht      := '0';
            cand_bmp      := '0';
            cand_sps      := '0';
            cand_temp     := 0;
            cand_humid    := 0;
            cand_press    := 1013;
            cand_pm25     := 0;
        elsif rising_edge(clk) then
            tick_r <= '0';

            if sec_tick = '1' then
                if age_sec > 0 then
                    age_sec := age_sec - 1;
                end if;

                if age_sec = 0 then
                    link_active_r <= '0';
                end if;
            end if;

            if rx_valid = '1' then
                if rx_data = ASCII_CR then
                    null;
                else
                    case parse_state is
                        when ST_WAIT_W =>
                            if rx_data = ASCII_W then
                                parse_state <= ST_WAIT_S;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_WAIT_S =>
                            if rx_data = ASCII_S then
                                parse_state <= ST_WAIT_COMMA0;
                            elsif rx_data = ASCII_W then
                                parse_state <= ST_WAIT_S;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_WAIT_COMMA0 =>
                            if rx_data = ASCII_COMMA then
                                parse_state <= ST_READ_SHT;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_READ_SHT =>
                            if (rx_data = ASCII_0) or (rx_data = ASCII_1) then
                                cand_sht := rx_data(0);
                                parse_state <= ST_WAIT_COMMA1;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_WAIT_COMMA1 =>
                            if rx_data = ASCII_COMMA then
                                parse_state <= ST_READ_BMP;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_READ_BMP =>
                            if (rx_data = ASCII_0) or (rx_data = ASCII_1) then
                                cand_bmp := rx_data(0);
                                parse_state <= ST_WAIT_COMMA2;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_WAIT_COMMA2 =>
                            if rx_data = ASCII_COMMA then
                                parse_state <= ST_READ_SPS;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_READ_SPS =>
                            if (rx_data = ASCII_0) or (rx_data = ASCII_1) then
                                cand_sps := rx_data(0);
                                parse_state <= ST_WAIT_COMMA3;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_WAIT_COMMA3 =>
                            if rx_data = ASCII_COMMA then
                                field_acc := 0;
                                parse_state <= ST_READ_TEMP;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_READ_TEMP =>
                            if is_digit(rx_data) then
                                field_acc := clamp(field_acc * 10 + digit_to_int(rx_data), 0, 32767);
                            elsif rx_data = ASCII_COMMA then
                                cand_temp := clamp(field_acc, 0, 999);
                                field_acc := 0;
                                parse_state <= ST_READ_HUMID;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_READ_HUMID =>
                            if is_digit(rx_data) then
                                field_acc := clamp(field_acc * 10 + digit_to_int(rx_data), 0, 32767);
                            elsif rx_data = ASCII_COMMA then
                                cand_humid := clamp(field_acc, 0, 1000);
                                field_acc := 0;
                                parse_state <= ST_READ_PRESS;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_READ_PRESS =>
                            if is_digit(rx_data) then
                                field_acc := clamp(field_acc * 10 + digit_to_int(rx_data), 0, 32767);
                            elsif rx_data = ASCII_COMMA then
                                cand_press := clamp(field_acc, 300, 1200);
                                field_acc := 0;
                                parse_state <= ST_READ_PM25;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;

                        when ST_READ_PM25 =>
                            if is_digit(rx_data) then
                                field_acc := clamp(field_acc * 10 + digit_to_int(rx_data), 0, 32767);
                            elsif rx_data = ASCII_NL then
                                cand_pm25 := clamp(field_acc, 0, 2000);

                                temp_r      <= clamp(cand_temp, 0, 999);
                                humid_r     <= clamp(cand_humid, 0, 1000);
                                press_r     <= clamp(cand_press, 300, 1200);
                                pm25_r      <= clamp(cand_pm25, 0, 2000);
                                light_r     <= 50;
                                sht_valid_r <= cand_sht;
                                bmp_valid_r <= cand_bmp;
                                sps_valid_r <= cand_sps;
                                link_active_r <= '1';
                                age_sec := LINK_TIMEOUT_SEC;
                                tick_r  <= '1';

                                field_acc   := 0;
                                parse_state <= ST_WAIT_W;
                            else
                                parse_state <= ST_WAIT_W;
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture;
