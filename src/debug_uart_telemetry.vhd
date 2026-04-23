library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debug_uart_telemetry is
    port (
        clk        : in  std_logic;
        reset_n    : in  std_logic;
        tick_1hz   : in  std_logic;
        sht_valid  : in  std_logic;
        bmp_valid  : in  std_logic;
        sps_valid  : in  std_logic;
        all_valid  : in  std_logic;
        sht_active : in  std_logic;
        bmp_active : in  std_logic;
        sps_active : in  std_logic;
        temp_x10   : in  integer range 0 to 999;
        humid_x10  : in  integer range 0 to 1000;
        press_hpa  : in  integer range 300 to 1200;
        pm25_x10   : in  integer range 0 to 2000;
        tx         : out std_logic
    );
end entity;

architecture rtl of debug_uart_telemetry is
    type byte_array_t is array (0 to 63) of std_logic_vector(7 downto 0);

    function char_byte(c : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(c), 8));
    end function;

    function bit_byte(b : std_logic) return std_logic_vector is
    begin
        if b = '1' then
            return char_byte('1');
        else
            return char_byte('0');
        end if;
    end function;

    function digit_byte(value, divisor : integer) return std_logic_vector is
        variable d : integer;
    begin
        d := (value / divisor) mod 10;
        return std_logic_vector(to_unsigned(character'pos('0') + d, 8));
    end function;

    signal tx_start   : std_logic := '0';
    signal tx_data    : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy    : std_logic;
    signal tx_done    : std_logic;
    signal tx_buf     : byte_array_t;
    signal tx_len     : integer range 0 to 63 := 0;
    signal tx_index   : integer range 0 to 63 := 0;
    signal sending    : std_logic := '0';
    signal pending    : std_logic := '0';
begin
    u_uart_tx : entity work.uart_tx
        port map (
            clk     => clk,
            reset_n => reset_n,
            start   => tx_start,
            data_in => tx_data,
            tx      => tx,
            busy    => tx_busy,
            done    => tx_done
        );

    process (clk, reset_n)
    begin
        if reset_n = '0' then
            tx_start <= '0';
            tx_data  <= (others => '0');
            tx_len   <= 0;
            tx_index <= 0;
            sending  <= '0';
            pending  <= '0';
        elsif rising_edge(clk) then
            tx_start <= '0';

            if tick_1hz = '1' then
                pending <= '1';
            end if;

            if sending = '0' and pending = '1' then
                tx_buf(0)  <= char_byte('V');
                tx_buf(1)  <= char_byte('=');
                tx_buf(2)  <= bit_byte(sht_valid);
                tx_buf(3)  <= bit_byte(bmp_valid);
                tx_buf(4)  <= bit_byte(sps_valid);
                tx_buf(5)  <= char_byte(' ');
                tx_buf(6)  <= char_byte('A');
                tx_buf(7)  <= char_byte('=');
                tx_buf(8)  <= bit_byte(sht_active);
                tx_buf(9)  <= bit_byte(bmp_active);
                tx_buf(10) <= bit_byte(sps_active);
                tx_buf(11) <= char_byte(' ');
                tx_buf(12) <= char_byte('T');
                tx_buf(13) <= char_byte('=');
                tx_buf(14) <= digit_byte(temp_x10, 1000);
                tx_buf(15) <= digit_byte(temp_x10, 100);
                tx_buf(16) <= digit_byte(temp_x10, 10);
                tx_buf(17) <= digit_byte(temp_x10, 1);
                tx_buf(18) <= char_byte(' ');
                tx_buf(19) <= char_byte('H');
                tx_buf(20) <= char_byte('=');
                tx_buf(21) <= digit_byte(humid_x10, 1000);
                tx_buf(22) <= digit_byte(humid_x10, 100);
                tx_buf(23) <= digit_byte(humid_x10, 10);
                tx_buf(24) <= digit_byte(humid_x10, 1);
                tx_buf(25) <= char_byte(' ');
                tx_buf(26) <= char_byte('P');
                tx_buf(27) <= char_byte('=');
                tx_buf(28) <= digit_byte(press_hpa, 1000);
                tx_buf(29) <= digit_byte(press_hpa, 100);
                tx_buf(30) <= digit_byte(press_hpa, 10);
                tx_buf(31) <= digit_byte(press_hpa, 1);
                tx_buf(32) <= char_byte(' ');
                tx_buf(33) <= char_byte('M');
                tx_buf(34) <= char_byte('=');
                tx_buf(35) <= digit_byte(pm25_x10, 1000);
                tx_buf(36) <= digit_byte(pm25_x10, 100);
                tx_buf(37) <= digit_byte(pm25_x10, 10);
                tx_buf(38) <= digit_byte(pm25_x10, 1);
                tx_buf(39) <= char_byte(' ');
                tx_buf(40) <= char_byte('G');
                tx_buf(41) <= char_byte('=');
                tx_buf(42) <= bit_byte(all_valid);
                tx_buf(43) <= char_byte(character'val(13));
                tx_buf(44) <= char_byte(character'val(10));
                tx_len     <= 45;
                tx_index   <= 0;
                sending    <= '1';
                pending    <= '0';
            elsif sending = '1' then
                if tx_done = '1' then
                    if tx_index = tx_len - 1 then
                        sending <= '0';
                    else
                        tx_index <= tx_index + 1;
                    end if;
                elsif tx_busy = '0' then
                    tx_data  <= tx_buf(tx_index);
                    tx_start <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture;

