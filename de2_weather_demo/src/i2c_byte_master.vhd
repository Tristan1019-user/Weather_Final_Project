library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_byte_master is
    generic (
        CLK_FREQ_HZ : integer := 50000000;
        I2C_FREQ_HZ : integer := 100000
    );
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        cmd_valid   : in  std_logic;
        cmd_start   : in  std_logic;
        cmd_stop    : in  std_logic;
        cmd_read    : in  std_logic;
        cmd_ack_out : in  std_logic; -- for read: '0' send ACK, '1' send NACK
        tx_byte     : in  std_logic_vector(7 downto 0);
        sda_in      : in  std_logic;
        scl_in      : in  std_logic;
        sda_oen     : out std_logic;
        scl_oen     : out std_logic;
        busy        : out std_logic;
        done        : out std_logic;
        ack_error   : out std_logic;
        rx_byte     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of i2c_byte_master is
    constant DIVIDER      : integer := CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);
    constant TICK_RELOAD  : integer := DIVIDER - 1;

    type state_t is (
        ST_IDLE,
        ST_START_A,
        ST_START_B,
        ST_BIT_PREP,
        ST_BIT_HIGH,
        ST_BIT_SAMPLE,
        ST_BIT_LOW,
        ST_ACK_PREP,
        ST_ACK_HIGH,
        ST_ACK_SAMPLE,
        ST_ACK_LOW,
        ST_STOP_A,
        ST_STOP_B,
        ST_DONE
    );

    signal state        : state_t := ST_IDLE;
    signal tick_count   : integer range 0 to TICK_RELOAD := 0;
    signal phase_tick   : std_logic := '0';

    signal lat_start    : std_logic := '0';
    signal lat_stop     : std_logic := '0';
    signal lat_read     : std_logic := '0';
    signal lat_ack_out  : std_logic := '1';
    signal shreg_tx     : std_logic_vector(7 downto 0) := (others => '0');
    signal shreg_rx     : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_idx      : integer range 0 to 7 := 7;

    signal sda_oen_r    : std_logic := '1';
    signal scl_oen_r    : std_logic := '1';
    signal busy_r       : std_logic := '0';
    signal done_r       : std_logic := '0';
    signal ack_err_r    : std_logic := '0';
begin
    sda_oen <= sda_oen_r;
    scl_oen <= scl_oen_r;
    busy    <= busy_r;
    done    <= done_r;
    ack_error <= ack_err_r;
    rx_byte <= shreg_rx;

    process (clk, reset_n)
    begin
        if reset_n = '0' then
            tick_count <= 0;
            phase_tick <= '0';
        elsif rising_edge(clk) then
            if busy_r = '1' then
                if tick_count = TICK_RELOAD then
                    tick_count <= 0;
                    phase_tick <= '1';
                else
                    tick_count <= tick_count + 1;
                    phase_tick <= '0';
                end if;
            else
                tick_count <= 0;
                phase_tick <= '0';
            end if;
        end if;
    end process;

    process (clk, reset_n)
    begin
        if reset_n = '0' then
            state       <= ST_IDLE;
            sda_oen_r   <= '1';
            scl_oen_r   <= '1';
            busy_r      <= '0';
            done_r      <= '0';
            ack_err_r   <= '0';
            lat_start   <= '0';
            lat_stop    <= '0';
            lat_read    <= '0';
            lat_ack_out <= '1';
            shreg_tx    <= (others => '0');
            shreg_rx    <= (others => '0');
            bit_idx     <= 7;
        elsif rising_edge(clk) then
            done_r <= '0';

            case state is
                when ST_IDLE =>
                    sda_oen_r <= '1';
                    scl_oen_r <= '1';
                    busy_r    <= '0';
                    ack_err_r <= '0';
                    if cmd_valid = '1' then
                        lat_start   <= cmd_start;
                        lat_stop    <= cmd_stop;
                        lat_read    <= cmd_read;
                        lat_ack_out <= cmd_ack_out;
                        shreg_tx    <= tx_byte;
                        shreg_rx    <= (others => '0');
                        bit_idx     <= 7;
                        busy_r      <= '1';
                        if cmd_start = '1' then
                            state <= ST_START_A;
                        else
                            state <= ST_BIT_PREP;
                        end if;
                    end if;

                when ST_START_A =>
                    sda_oen_r <= '1';
                    scl_oen_r <= '1';
                    if phase_tick = '1' then
                        state <= ST_START_B;
                    end if;

                when ST_START_B =>
                    sda_oen_r <= '0';
                    scl_oen_r <= '1';
                    if phase_tick = '1' then
                        state <= ST_BIT_PREP;
                    end if;

                when ST_BIT_PREP =>
                    scl_oen_r <= '0';
                    if lat_read = '1' then
                        sda_oen_r <= '1';
                    else
                        sda_oen_r <= not shreg_tx(bit_idx);
                    end if;
                    if phase_tick = '1' then
                        state <= ST_BIT_HIGH;
                    end if;

                when ST_BIT_HIGH =>
                    scl_oen_r <= '1';
                    if phase_tick = '1' then
                        state <= ST_BIT_SAMPLE;
                    end if;

                when ST_BIT_SAMPLE =>
                    scl_oen_r <= '1';
                    if lat_read = '1' then
                        shreg_rx(bit_idx) <= sda_in;
                    end if;
                    if phase_tick = '1' then
                        state <= ST_BIT_LOW;
                    end if;

                when ST_BIT_LOW =>
                    scl_oen_r <= '0';
                    if phase_tick = '1' then
                        if bit_idx = 0 then
                            state <= ST_ACK_PREP;
                        else
                            bit_idx <= bit_idx - 1;
                            state <= ST_BIT_PREP;
                        end if;
                    end if;

                when ST_ACK_PREP =>
                    scl_oen_r <= '0';
                    if lat_read = '1' then
                        sda_oen_r <= lat_ack_out; -- 0 drives ACK low, 1 releases for NACK
                    else
                        sda_oen_r <= '1';
                    end if;
                    if phase_tick = '1' then
                        state <= ST_ACK_HIGH;
                    end if;

                when ST_ACK_HIGH =>
                    scl_oen_r <= '1';
                    if phase_tick = '1' then
                        state <= ST_ACK_SAMPLE;
                    end if;

                when ST_ACK_SAMPLE =>
                    scl_oen_r <= '1';
                    if lat_read = '0' then
                        if sda_in /= '0' then
                            ack_err_r <= '1';
                        end if;
                    end if;
                    if phase_tick = '1' then
                        state <= ST_ACK_LOW;
                    end if;

                when ST_ACK_LOW =>
                    scl_oen_r <= '0';
                    sda_oen_r <= '0';
                    if phase_tick = '1' then
                        if lat_stop = '1' then
                            state <= ST_STOP_A;
                        else
                            state <= ST_DONE;
                        end if;
                    end if;

                when ST_STOP_A =>
                    scl_oen_r <= '0';
                    sda_oen_r <= '0';
                    if phase_tick = '1' then
                        state <= ST_STOP_B;
                    end if;

                when ST_STOP_B =>
                    scl_oen_r <= '1';
                    sda_oen_r <= '0';
                    if phase_tick = '1' then
                        sda_oen_r <= '1';
                        state <= ST_DONE;
                    end if;

                when ST_DONE =>
                    sda_oen_r <= '1';
                    scl_oen_r <= '1';
                    busy_r    <= '0';
                    done_r    <= '1';
                    state     <= ST_IDLE;
            end case;
        end if;
    end process;
end architecture;
