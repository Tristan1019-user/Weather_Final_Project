library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sht45_stub is
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        poll_tick   : in  std_logic;
        i2c_sda_in  : in  std_logic;
        i2c_scl_in  : in  std_logic;
        i2c_sda_oen : out std_logic;
        i2c_scl_oen : out std_logic;
        temp_x10    : out integer range 0 to 999;
        humid_x10   : out integer range 0 to 1000;
        valid       : out std_logic;
        active      : out std_logic
    );
end entity;

architecture rtl of sht45_stub is
    constant SHT_ADDR_W  : std_logic_vector(7 downto 0) := x"88";
    constant SHT_ADDR_R  : std_logic_vector(7 downto 0) := x"89";
    constant SHT_CMD_HP  : std_logic_vector(7 downto 0) := x"FD";
    constant MEAS_WAIT   : integer := 600000; -- 12 ms @ 50 MHz

    type state_t is (
        ST_IDLE,
        ST_SEND_ADDR_W,
        ST_SEND_CMD,
        ST_WAIT_MEAS,
        ST_SEND_ADDR_R,
        ST_READ_B0,
        ST_READ_B1,
        ST_READ_B2,
        ST_READ_B3,
        ST_READ_B4,
        ST_READ_B5,
        ST_PROCESS,
        ST_HOLD
    );

    function crc8_sht(d0, d1 : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable crc  : unsigned(7 downto 0) := x"FF";
        variable data : unsigned(15 downto 0);
    begin
        data := unsigned(std_logic_vector'(d0 & d1));
        for i in 15 downto 0 loop
            if (crc(7) xor data(i)) = '1' then
                crc := shift_left(crc, 1) xor x"31";
            else
                crc := shift_left(crc, 1);
            end if;
        end loop;
        return std_logic_vector(crc);
    end function;

    signal state          : state_t := ST_IDLE;
    signal cmd_valid      : std_logic := '0';
    signal cmd_start      : std_logic := '0';
    signal cmd_stop       : std_logic := '0';
    signal cmd_read       : std_logic := '0';
    signal cmd_ack_out    : std_logic := '1';
    signal cmd_tx_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal i2c_busy       : std_logic;
    signal i2c_done       : std_logic;
    signal i2c_ack_error  : std_logic;
    signal i2c_rx_byte    : std_logic_vector(7 downto 0);

    signal wait_count     : integer range 0 to MEAS_WAIT := 0;
    signal data0          : std_logic_vector(7 downto 0) := (others => '0');
    signal data1          : std_logic_vector(7 downto 0) := (others => '0');
    signal data2          : std_logic_vector(7 downto 0) := (others => '0');
    signal data3          : std_logic_vector(7 downto 0) := (others => '0');
    signal data4          : std_logic_vector(7 downto 0) := (others => '0');
    signal data5          : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_r        : std_logic := '0';
    signal active_r       : std_logic := '0';
    signal temp_x10_r     : integer range 0 to 999 := 241;
    signal humid_x10_r    : integer range 0 to 1000 := 507;
begin
    temp_x10 <= temp_x10_r;
    humid_x10 <= humid_x10_r;
    valid <= valid_r;
    active <= active_r;

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
            busy        => i2c_busy,
            done        => i2c_done,
            ack_error   => i2c_ack_error,
            rx_byte     => i2c_rx_byte
        );

    process (clk, reset_n)
        variable raw_t    : integer;
        variable raw_rh   : integer;
        variable calc_t   : integer;
        variable calc_rh  : integer;
    begin
        if reset_n = '0' then
            state       <= ST_IDLE;
            cmd_valid   <= '0';
            cmd_start   <= '0';
            cmd_stop    <= '0';
            cmd_read    <= '0';
            cmd_ack_out <= '1';
            cmd_tx_byte <= (others => '0');
            wait_count  <= 0;
            data0       <= (others => '0');
            data1       <= (others => '0');
            data2       <= (others => '0');
            data3       <= (others => '0');
            data4       <= (others => '0');
            data5       <= (others => '0');
            valid_r     <= '0';
            active_r    <= '0';
            temp_x10_r  <= 241;
            humid_x10_r <= 507;
        elsif rising_edge(clk) then
            cmd_valid <= '0';
            if state = ST_IDLE then
                active_r <= '0';
            else
                active_r <= '1';
            end if;

            case state is
                when ST_IDLE =>
                    if poll_tick = '1' then
                        cmd_valid   <= '1';
                        cmd_start   <= '1';
                        cmd_stop    <= '0';
                        cmd_read    <= '0';
                        cmd_ack_out <= '1';
                        cmd_tx_byte <= SHT_ADDR_W;
                        state       <= ST_SEND_ADDR_W;
                    end if;

                when ST_SEND_ADDR_W =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '1';
                            cmd_read    <= '0';
                            cmd_tx_byte <= SHT_CMD_HP;
                            state       <= ST_SEND_CMD;
                        end if;
                    end if;

                when ST_SEND_CMD =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            wait_count <= 0;
                            state <= ST_WAIT_MEAS;
                        end if;
                    end if;

                when ST_WAIT_MEAS =>
                    if wait_count = MEAS_WAIT then
                        cmd_valid   <= '1';
                        cmd_start   <= '1';
                        cmd_stop    <= '0';
                        cmd_read    <= '0';
                        cmd_tx_byte <= SHT_ADDR_R;
                        state       <= ST_SEND_ADDR_R;
                    else
                        wait_count <= wait_count + 1;
                    end if;

                when ST_SEND_ADDR_R =>
                    if i2c_done = '1' then
                        if i2c_ack_error = '1' then
                            state <= ST_IDLE;
                        else
                            cmd_valid   <= '1';
                            cmd_start   <= '0';
                            cmd_stop    <= '0';
                            cmd_read    <= '1';
                            cmd_ack_out <= '0';
                            cmd_tx_byte <= (others => '0');
                            state       <= ST_READ_B0;
                        end if;
                    end if;

                when ST_READ_B0 =>
                    if i2c_done = '1' then
                        data0 <= i2c_rx_byte;
                        cmd_valid   <= '1';
                        cmd_read    <= '1';
                        cmd_ack_out <= '0';
                        cmd_stop    <= '0';
                        state       <= ST_READ_B1;
                    end if;

                when ST_READ_B1 =>
                    if i2c_done = '1' then
                        data1 <= i2c_rx_byte;
                        cmd_valid   <= '1';
                        cmd_read    <= '1';
                        cmd_ack_out <= '0';
                        cmd_stop    <= '0';
                        state       <= ST_READ_B2;
                    end if;

                when ST_READ_B2 =>
                    if i2c_done = '1' then
                        data2 <= i2c_rx_byte;
                        cmd_valid   <= '1';
                        cmd_read    <= '1';
                        cmd_ack_out <= '0';
                        cmd_stop    <= '0';
                        state       <= ST_READ_B3;
                    end if;

                when ST_READ_B3 =>
                    if i2c_done = '1' then
                        data3 <= i2c_rx_byte;
                        cmd_valid   <= '1';
                        cmd_read    <= '1';
                        cmd_ack_out <= '0';
                        cmd_stop    <= '0';
                        state       <= ST_READ_B4;
                    end if;

                when ST_READ_B4 =>
                    if i2c_done = '1' then
                        data4 <= i2c_rx_byte;
                        cmd_valid   <= '1';
                        cmd_read    <= '1';
                        cmd_ack_out <= '1';
                        cmd_stop    <= '1';
                        state       <= ST_READ_B5;
                    end if;

                when ST_READ_B5 =>
                    if i2c_done = '1' then
                        data5 <= i2c_rx_byte;
                        state <= ST_PROCESS;
                    end if;

                when ST_PROCESS =>
                    if (crc8_sht(data0, data1) = data2) and (crc8_sht(data3, data4) = data5) then
                        raw_t := to_integer(unsigned(std_logic_vector'(data0 & data1)));
                        raw_rh := to_integer(unsigned(std_logic_vector'(data3 & data4)));
                        calc_t := -450 + ((1750 * raw_t + 32767) / 65535);
                        calc_rh := -60 + ((1250 * raw_rh + 32767) / 65535);
                        if calc_t < 0 then
                            temp_x10_r <= 0;
                        elsif calc_t > 999 then
                            temp_x10_r <= 999;
                        else
                            temp_x10_r <= calc_t;
                        end if;
                        if calc_rh < 0 then
                            humid_x10_r <= 0;
                        elsif calc_rh > 1000 then
                            humid_x10_r <= 1000;
                        else
                            humid_x10_r <= calc_rh;
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
