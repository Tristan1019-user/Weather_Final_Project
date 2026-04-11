library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sps30_uart_stub is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        poll_tick   : in  std_logic;
        uart_rx     : in  std_logic;
        uart_tx     : out std_logic;
        pm25_x10    : out integer range 0 to 2000;
        valid       : out std_logic;
        active      : out std_logic
    );
end entity;

architecture rtl of sps30_uart_stub is
    type byte_array64_t is array (0 to 63) of std_logic_vector(7 downto 0);
    type state_t is (
        ST_POWER_WAIT,
        ST_START_PREP,
        ST_TX_FRAME,
        ST_WAIT_START_RESP,
        ST_WARMUP,
        ST_IDLE,
        ST_READ_PREP,
        ST_WAIT_READ_RESP,
        ST_PARSE_READ,
        ST_HOLD
    );

    function shdlc_checksum(buf : byte_array64_t; count : integer) return std_logic_vector is
        variable sum_v : integer := 0;
    begin
        for i in 0 to 63 loop
            if i < count then
                sum_v := (sum_v + to_integer(unsigned(buf(i)))) mod 256;
            end if;
        end loop;
        return std_logic_vector(to_unsigned((255 - sum_v) mod 256, 8));
    end function;

    function decode_escaped(b : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        if b = x"5E" then
            return x"7E";
        elsif b = x"5D" then
            return x"7D";
        elsif b = x"31" then
            return x"11";
        elsif b = x"33" then
            return x"13";
        else
            return b;
        end if;
    end function;

    function float_be_to_x10(b0, b1, b2, b3 : std_logic_vector(7 downto 0)) return integer is
        variable word_v    : unsigned(31 downto 0);
        variable exp_v     : integer;
        variable mant8_v   : integer;
        variable base_x10  : integer;
        variable scaled    : integer;
        variable shiftv    : integer;
    begin
        word_v := unsigned(std_logic_vector'(b0 & b1 & b2 & b3));

        if word_v(31) = '1' then
            return 0;
        end if;

        exp_v := to_integer(word_v(30 downto 23));

        if exp_v < 127 then
            return 0;
        elsif exp_v > 134 then
            return 2000;
        end if;

        mant8_v := to_integer(word_v(22 downto 15));
        base_x10 := ((128 + mant8_v) * 10 + 64) / 128;
        shiftv := exp_v - 127;
        scaled := base_x10 * (2 ** shiftv);

        if scaled < 0 then
            return 0;
        elsif scaled > 2000 then
            return 2000;
        else
            return scaled;
        end if;
    end function;

    constant POWER_WAIT_TICKS  : integer := 50000000;  -- 1 s
    constant WARMUP_TICKS      : integer := 100000000; -- 2 s

    signal state           : state_t := ST_POWER_WAIT;
    signal timer_cnt       : integer range 0 to WARMUP_TICKS := 0;
    signal pending_poll    : std_logic := '0';
    signal active_r        : std_logic := '0';
    signal valid_r         : std_logic := '0';
    signal pm25_x10_r      : integer range 0 to 2000 := 0;

    signal tx_start        : std_logic := '0';
    signal tx_data         : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy         : std_logic;
    signal tx_done         : std_logic;
    signal rx_data         : std_logic_vector(7 downto 0);
    signal rx_valid        : std_logic;

    signal tx_buf          : byte_array64_t;
    signal tx_len          : integer range 0 to 63 := 0;
    signal tx_index        : integer range 0 to 63 := 0;

    signal rx_buf          : byte_array64_t;
    signal rx_len          : integer range 0 to 64 := 0;
    signal rx_in_frame     : std_logic := '0';
    signal rx_escape       : std_logic := '0';
    signal frame_ready     : std_logic := '0';
    signal frame_clear     : std_logic := '0';
begin
    pm25_x10 <= pm25_x10_r;
    valid    <= valid_r;
    active   <= active_r;

    u_tx : entity work.uart_tx
        port map (
            clk      => clk,
            reset_n  => reset_n,
            start    => tx_start,
            data_in  => tx_data,
            tx       => uart_tx,
            busy     => tx_busy,
            done     => tx_done
        );

    u_rx : entity work.uart_rx
        port map (
            clk        => clk,
            reset_n    => reset_n,
            rx         => uart_rx,
            data_out   => rx_data,
            data_valid => rx_valid
        );

    process (clk, reset_n)
        variable decoded : std_logic_vector(7 downto 0);
    begin
        if reset_n = '0' then
            rx_len      <= 0;
            rx_in_frame <= '0';
            rx_escape   <= '0';
            frame_ready <= '0';
        elsif rising_edge(clk) then
            if frame_clear = '1' then
                frame_ready <= '0';
            end if;

            if rx_valid = '1' then
                if rx_data = x"7E" then
                    if rx_in_frame = '0' then
                        rx_in_frame <= '1';
                        rx_escape   <= '0';
                        rx_len      <= 0;
                    else
                        frame_ready <= '1';
                        rx_in_frame <= '0';
                        rx_escape   <= '0';
                    end if;
                elsif rx_in_frame = '1' then
                    if rx_escape = '1' then
                        decoded := decode_escaped(rx_data);
                        if rx_len < 64 then
                            rx_buf(rx_len) <= decoded;
                            rx_len <= rx_len + 1;
                        end if;
                        rx_escape <= '0';
                    elsif rx_data = x"7D" then
                        rx_escape <= '1';
                    else
                        if rx_len < 64 then
                            rx_buf(rx_len) <= rx_data;
                            rx_len <= rx_len + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process (clk, reset_n)
    begin
        if reset_n = '0' then
            state        <= ST_POWER_WAIT;
            timer_cnt    <= 0;
            pending_poll <= '0';
            active_r     <= '0';
            valid_r      <= '0';
            pm25_x10_r   <= 0;
            tx_start     <= '0';
            tx_data      <= (others => '0');
            tx_len       <= 0;
            tx_index     <= 0;
            frame_clear  <= '0';
        elsif rising_edge(clk) then
            tx_start    <= '0';
            frame_clear <= '0';

            if poll_tick = '1' then
                pending_poll <= '1';
            end if;

            if state = ST_IDLE or state = ST_HOLD then
                active_r <= '0';
            else
                active_r <= '1';
            end if;

            case state is
                when ST_POWER_WAIT =>
                    if timer_cnt = POWER_WAIT_TICKS then
                        state <= ST_START_PREP;
                    else
                        timer_cnt <= timer_cnt + 1;
                    end if;

                when ST_START_PREP =>
                    tx_buf(0) <= x"7E";
                    tx_buf(1) <= x"00";
                    tx_buf(2) <= x"00";
                    tx_buf(3) <= x"02";
                    tx_buf(4) <= x"01";
                    tx_buf(5) <= x"03";
                    tx_buf(6) <= x"F9";
                    tx_buf(7) <= x"7E";
                    tx_len    <= 8;
                    tx_index  <= 0;
                    state     <= ST_TX_FRAME;

                when ST_TX_FRAME =>
                    if tx_done = '1' then
                        if tx_index = tx_len - 1 then
                            if tx_buf(2) = x"00" then
                                state <= ST_WAIT_START_RESP;
                            else
                                state <= ST_WAIT_READ_RESP;
                            end if;
                        else
                            tx_index <= tx_index + 1;
                        end if;
                    elsif tx_busy = '0' then
                        tx_data  <= tx_buf(tx_index);
                        tx_start <= '1';
                    end if;

                when ST_WAIT_START_RESP =>
                    if frame_ready = '1' then
                        frame_clear <= '1';
                        if rx_len >= 5 and rx_buf(1) = x"00" and rx_buf(2) = x"00" and rx_buf(3) = x"00" then
                            timer_cnt <= 0;
                            state <= ST_WARMUP;
                        else
                            timer_cnt <= 0;
                            state <= ST_START_PREP;
                        end if;
                    end if;

                when ST_WARMUP =>
                    if timer_cnt = WARMUP_TICKS then
                        state <= ST_IDLE;
                    else
                        timer_cnt <= timer_cnt + 1;
                    end if;

                when ST_IDLE =>
                    if pending_poll = '1' then
                        pending_poll <= '0';
                        state <= ST_READ_PREP;
                    end if;

                when ST_READ_PREP =>
                    tx_buf(0) <= x"7E";
                    tx_buf(1) <= x"00";
                    tx_buf(2) <= x"03";
                    tx_buf(3) <= x"00";
                    tx_buf(4) <= x"FC";
                    tx_buf(5) <= x"7E";
                    tx_len    <= 6;
                    tx_index  <= 0;
                    state     <= ST_TX_FRAME;

                when ST_WAIT_READ_RESP =>
                    if frame_ready = '1' then
                        frame_clear <= '1';
                        state <= ST_PARSE_READ;
                    end if;

                when ST_PARSE_READ =>
                    if rx_len >= 12 then
                        if rx_buf(1) = x"03" and rx_buf(2) = x"00" and rx_buf(3) = x"28" then
                            pm25_x10_r <= float_be_to_x10(rx_buf(8), rx_buf(9), rx_buf(10), rx_buf(11));
                            valid_r <= '1';
                        end if;
                    end if;
                    state <= ST_HOLD;

                when ST_HOLD =>
                    state <= ST_IDLE;
            end case;
        end if;
    end process;
end architecture;
