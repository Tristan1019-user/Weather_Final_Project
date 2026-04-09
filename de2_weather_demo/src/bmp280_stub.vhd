library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bmp280_stub is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        poll_tick   : in  std_logic;
        i2c_sda_in  : in  std_logic;
        i2c_scl_in  : in  std_logic;
        i2c_sda_oen : out std_logic;
        i2c_scl_oen : out std_logic;
        press_hpa   : out integer range 300 to 1200;
        valid       : out std_logic;
        active      : out std_logic
    );
end entity;

architecture rtl of bmp280_stub is
    type byte_array24_t is array (0 to 23) of std_logic_vector(7 downto 0);
    type byte_array6_t  is array (0 to 5) of std_logic_vector(7 downto 0);
    type state_t is (
        ST_INIT_WAIT,
        ST_PROBE_ADDR_W,
        ST_PROBE_REG,
        ST_PROBE_ADDR_R,
        ST_PROBE_ID,
        ST_CALIB_ADDR_W,
        ST_CALIB_REG,
        ST_CALIB_ADDR_R,
        ST_CALIB_READ,
        ST_PARSE_CALIB,
        ST_IDLE,
        ST_CFG_ADDR_W,
        ST_CFG_REG,
        ST_CFG_VAL,
        ST_WAIT_CONV,
        ST_DATA_ADDR_W,
        ST_DATA_REG,
        ST_DATA_ADDR_R,
        ST_DATA_READ,
        ST_CALC,
        ST_HOLD
    );

    function s64(i : integer) return signed is
    begin
        return to_signed(i, 64);
    end function;

    function mul64(a, b : signed(63 downto 0)) return signed is
    begin
        return resize(a * b, 64);
    end function;

    function u16_le(lo_b, hi_b : std_logic_vector(7 downto 0)) return integer is
    begin
        return to_integer(unsigned(hi_b & lo_b));
    end function;

    function s16_le(lo_b, hi_b : std_logic_vector(7 downto 0)) return integer is
    begin
        return to_integer(signed(hi_b & lo_b));
    end function;

    constant ADDR76_W : std_logic_vector(7 downto 0) := x"EC";
    constant ADDR76_R : std_logic_vector(7 downto 0) := x"ED";
    constant ADDR77_W : std_logic_vector(7 downto 0) := x"EE";
    constant ADDR77_R : std_logic_vector(7 downto 0) := x"EF";
    constant INIT_WAIT_TICKS : integer := 2500000; -- 50 ms
    constant CONV_WAIT_TICKS : integer := 750000;  -- 15 ms

    signal state          : state_t := ST_INIT_WAIT;
    signal cmd_valid      : std_logic := '0';
    signal cmd_start      : std_logic := '0';
    signal cmd_stop       : std_logic := '0';
    signal cmd_read       : std_logic := '0';
    signal cmd_ack_out    : std_logic := '1';
    signal cmd_tx_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal i2c_done       : std_logic;
    signal i2c_ack_error  : std_logic;
    signal i2c_rx_byte    : std_logic_vector(7 downto 0);
    signal active_r       : std_logic := '0';
    signal valid_r        : std_logic := '0';
    signal press_hpa_r    : integer range 300 to 1200 := 1012;
    signal timer_cnt      : integer range 0 to INIT_WAIT_TICKS := 0;
    signal byte_index     : integer range 0 to 23 := 0;
    signal addr_w         : std_logic_vector(7 downto 0) := ADDR76_W;
    signal addr_r         : std_logic_vector(7 downto 0) := ADDR76_R;
    signal addr_sel       : std_logic := '0'; -- 0=0x76, 1=0x77
    signal calib_bytes    : byte_array24_t;
    signal data_bytes     : byte_array6_t;
    signal calib_loaded   : std_logic := '0';
    signal pending_poll   : std_logic := '0';

    signal dig_t1         : integer := 0;
    signal dig_t2         : integer := 0;
    signal dig_t3         : integer := 0;
    signal dig_p1         : integer := 1;
    signal dig_p2         : integer := 0;
    signal dig_p3         : integer := 0;
    signal dig_p4         : integer := 0;
    signal dig_p5         : integer := 0;
    signal dig_p6         : integer := 0;
    signal dig_p7         : integer := 0;
    signal dig_p8         : integer := 0;
    signal dig_p9         : integer := 0;
begin
    press_hpa <= press_hpa_r;
    valid     <= valid_r;
    active    <= active_r;

    u_i2c : entity work.i2c_byte_master
        port map (
            clk         => clk,
            reset_n     => reset_n,
            cmd_valid   => cmd_valid,
            cmd_start   => cmd_start,
            cmd_stop    => cmd_stop,
            cmd_read    => cmd_read,
            cmd_ack_out => cmd_ack_out,
            tx_byte     => cmd_tx_byte,
            sda_in      => i2c_sda_in,
            scl_in      => i2c_scl_in,
            sda_oen     => i2c_sda_oen,
            scl_oen     => i2c_scl_oen,
            busy        => open,
            done        => i2c_done,
            ack_error   => i2c_ack_error,
            rx_byte     => i2c_rx_byte
        );

    process (clk, reset_n)
        variable adc_p      : integer;
        variable adc_t      : integer;
        variable var1_s     : signed(63 downto 0);
        variable var2_s     : signed(63 downto 0);
        variable p_s        : signed(63 downto 0);
        variable tmp_s      : signed(63 downto 0);
        variable tfine_s    : signed(63 downto 0);
        variable press_pa   : integer;
    begin
        if reset_n = '0' then
            state        <= ST_INIT_WAIT;
            cmd_valid    <= '0';
            cmd_start    <= '0';
            cmd_stop     <= '0';
            cmd_read     <= '0';
            cmd_ack_out  <= '1';
            cmd_tx_byte  <= (others => '0');
            active_r     <= '0';
            valid_r      <= '0';
            press_hpa_r  <= 1012;
            timer_cnt    <= 0;
            byte_index   <= 0;
            addr_sel     <= '0';
            addr_w       <= ADDR76_W;
            addr_r       <= ADDR76_R;
            calib_loaded <= '0';
            pending_poll <= '0';
        elsif rising_edge(clk) then
            cmd_valid <= '0';

            if state = ST_IDLE or state = ST_HOLD then
                active_r <= '0';
            else
                active_r <= '1';
            end if;

            if poll_tick = '1' then
                pending_poll <= '1';
            end if;

            case state is
                when ST_INIT_WAIT =>
                    if timer_cnt = INIT_WAIT_TICKS then
                        cmd_valid   <= '1';
                        cmd_start   <= '1';
                        cmd_stop    <= '0';
                        cmd_read    <= '0';
                        cmd_tx_byte <= addr_w;
                        state       <= ST_PROBE_ADDR_W;
                    else
                        timer_cnt <= timer_cnt + 1;
                    end if;

                when ST_PROBE_ADDR_W =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            if addr_sel = '0' then
                                addr_sel  <= '1';
                                addr_w    <= ADDR77_W;
                                addr_r    <= ADDR77_R;
                            else
                                addr_sel  <= '0';
                                addr_w    <= ADDR76_W;
                                addr_r    <= ADDR76_R;
                            end if;
                            timer_cnt <= 0;
                            state <= ST_INIT_WAIT;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= x"D0";
                            state       <= ST_PROBE_REG;
                        end if;
                    end if;

                when ST_PROBE_REG =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            timer_cnt <= 0;
                            state <= ST_INIT_WAIT;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '1';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= addr_r;
                            state       <= ST_PROBE_ADDR_R;
                        end if;
                    end if;

                when ST_PROBE_ADDR_R =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            timer_cnt <= 0;
                            state <= ST_INIT_WAIT;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '1';
                            cmd_read    <= '1';
                            cmd_ack_out <= '1';
                            state       <= ST_PROBE_ID;
                        end if;
                    end if;

                when ST_PROBE_ID =>
                    if i2c_done = '1' then
                        if i2c_rx_byte = x"58" then
                            cmd_valid   <= '1';
                            cmd_start   <= '1';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= addr_w;
                            state       <= ST_CALIB_ADDR_W;
                        else
                            if addr_sel = '0' then
                                addr_sel  <= '1';
                                addr_w    <= ADDR77_W;
                                addr_r    <= ADDR77_R;
                            else
                                addr_sel  <= '0';
                                addr_w    <= ADDR76_W;
                                addr_r    <= ADDR76_R;
                            end if;
                            timer_cnt <= 0;
                            state <= ST_INIT_WAIT;
                        end if;
                    end if;

                when ST_CALIB_ADDR_W =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            timer_cnt <= 0;
                            state <= ST_INIT_WAIT;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= x"88";
                            state       <= ST_CALIB_REG;
                        end if;
                    end if;

                when ST_CALIB_REG =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            timer_cnt <= 0;
                            state <= ST_INIT_WAIT;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '1';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= addr_r;
                            state       <= ST_CALIB_ADDR_R;
                        end if;
                    end if;

                when ST_CALIB_ADDR_R =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            timer_cnt <= 0;
                            state <= ST_INIT_WAIT;
                        else
                            byte_index <= 0;
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '0';
                            cmd_read    <= '1';
                            cmd_ack_out <= '0';
                            state       <= ST_CALIB_READ;
                        end if;
                    end if;

                when ST_CALIB_READ =>
                    if i2c_done = '1' then
                        calib_bytes(byte_index) <= i2c_rx_byte;
                        if byte_index = 23 then
                            state <= ST_PARSE_CALIB;
                        else
                            byte_index <= byte_index + 1;
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_read    <= '1';
                            if byte_index = 22 then
                                cmd_stop    <= '1';
                                cmd_ack_out <= '1';
                            else
                                cmd_stop    <= '0';
                                cmd_ack_out <= '0';
                            end if;
                        end if;
                    end if;

                when ST_PARSE_CALIB =>
                    dig_t1 <= u16_le(calib_bytes(0), calib_bytes(1));
                    dig_t2 <= s16_le(calib_bytes(2), calib_bytes(3));
                    dig_t3 <= s16_le(calib_bytes(4), calib_bytes(5));
                    dig_p1 <= u16_le(calib_bytes(6), calib_bytes(7));
                    dig_p2 <= s16_le(calib_bytes(8), calib_bytes(9));
                    dig_p3 <= s16_le(calib_bytes(10), calib_bytes(11));
                    dig_p4 <= s16_le(calib_bytes(12), calib_bytes(13));
                    dig_p5 <= s16_le(calib_bytes(14), calib_bytes(15));
                    dig_p6 <= s16_le(calib_bytes(16), calib_bytes(17));
                    dig_p7 <= s16_le(calib_bytes(18), calib_bytes(19));
                    dig_p8 <= s16_le(calib_bytes(20), calib_bytes(21));
                    dig_p9 <= s16_le(calib_bytes(22), calib_bytes(23));
                    calib_loaded <= '1';
                    state <= ST_IDLE;

                when ST_IDLE =>
                    if calib_loaded = '1' and pending_poll = '1' then
                        pending_poll <= '0';
                        cmd_valid   <= '1';
                        cmd_start   <= '1';
                        cmd_stop    <= '0';
                        cmd_read    <= '0';
                        cmd_tx_byte <= addr_w;
                        state       <= ST_CFG_ADDR_W;
                    end if;

                when ST_CFG_ADDR_W =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= x"F4";
                            state       <= ST_CFG_REG;
                        end if;
                    end if;

                when ST_CFG_REG =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '1';
                            cmd_read    <= '0';
                            cmd_tx_byte <= x"25";
                            state       <= ST_CFG_VAL;
                        end if;
                    end if;

                when ST_CFG_VAL =>
                    if i2c_done = '1' then
                        timer_cnt <= 0;
                        state <= ST_WAIT_CONV;
                    end if;

                when ST_WAIT_CONV =>
                    if timer_cnt = CONV_WAIT_TICKS then
                        cmd_valid   <= '1';
                        cmd_start   <= '1';
                        cmd_stop    <= '0';
                        cmd_read    <= '0';
                        cmd_tx_byte <= addr_w;
                        state       <= ST_DATA_ADDR_W;
                    else
                        timer_cnt <= timer_cnt + 1;
                    end if;

                when ST_DATA_ADDR_W =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= x"F7";
                            state       <= ST_DATA_REG;
                        end if;
                    end if;

                when ST_DATA_REG =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '1';
                            cmd_stop    <= '0';
                            cmd_read    <= '0';
                            cmd_tx_byte <= addr_r;
                            state       <= ST_DATA_ADDR_R;
                        end if;
                    end if;

                when ST_DATA_ADDR_R =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            byte_index <= 0;
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '0';
                            cmd_read    <= '1';
                            cmd_ack_out <= '0';
                            state       <= ST_DATA_READ;
                        end if;
                    end if;

                when ST_DATA_READ =>
                    if i2c_done = '1' then
                        data_bytes(byte_index) <= i2c_rx_byte;
                        if byte_index = 5 then
                            state <= ST_CALC;
                        else
                            byte_index <= byte_index + 1;
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_read    <= '1';
                            if byte_index = 4 then
                                cmd_stop    <= '1';
                                cmd_ack_out <= '1';
                            else
                                cmd_stop    <= '0';
                                cmd_ack_out <= '0';
                            end if;
                        end if;
                    end if;

                when ST_CALC =>
                    adc_p := to_integer(unsigned(data_bytes(0) & data_bytes(1) & data_bytes(2)(7 downto 4)));
                    adc_t := to_integer(unsigned(data_bytes(3) & data_bytes(4) & data_bytes(5)(7 downto 4)));

                    var1_s := shift_right(mul64(shift_right(s64(adc_t), 3) - shift_left(s64(dig_t1), 1), s64(dig_t2)), 11);
                    tmp_s := shift_right(s64(adc_t), 4) - s64(dig_t1);
                    var2_s := shift_right(mul64(shift_right(mul64(tmp_s, tmp_s), 12), s64(dig_t3)), 14);
                    tfine_s := var1_s + var2_s;

                    var1_s := shift_right(tfine_s, 1) - s64(64000);
                    tmp_s := shift_right(var1_s, 2);
                    var2_s := mul64(shift_right(mul64(tmp_s, tmp_s), 11), s64(dig_p6));
                    var2_s := var2_s + shift_left(mul64(var1_s, s64(dig_p5)), 1);
                    var2_s := shift_right(var2_s, 2) + shift_left(s64(dig_p4), 16);
                    tmp_s := shift_right(mul64(s64(dig_p3), shift_right(mul64(tmp_s, tmp_s), 13)), 3);
                    var1_s := shift_right(tmp_s + shift_right(mul64(s64(dig_p2), var1_s), 1), 18);
                    var1_s := shift_right(mul64(s64(32768) + var1_s, s64(dig_p1)), 15);

                    if to_integer(var1_s) /= 0 then
                        p_s := mul64((s64(1048576 - adc_p) - shift_right(var2_s, 12)), s64(3125));
                        p_s := resize(shift_left(p_s, 1) / s64(to_integer(var1_s)), 64);
                        var1_s := shift_right(mul64(s64(dig_p9), shift_right(mul64(shift_right(p_s, 3), shift_right(p_s, 3)), 13)), 12);
                        var2_s := shift_right(mul64(shift_right(p_s, 2), s64(dig_p8)), 13);
                        p_s := p_s + shift_right(var1_s + var2_s + s64(dig_p7), 4);
                        press_pa := to_integer(p_s);
                        if press_pa < 30000 then
                            press_hpa_r <= 300;
                        elsif press_pa > 120000 then
                            press_hpa_r <= 1200;
                        else
                            press_hpa_r <= (press_pa + 50) / 100;
                        end if;
                        valid_r <= '1';
                    end if;
                    state <= ST_HOLD;

                when ST_HOLD =>
                    state <= ST_IDLE;
            end case;
        end if;
    end process;
end architecture;
