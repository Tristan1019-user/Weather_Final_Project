library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLK_FREQ_HZ : integer := 50000000;
        BAUD_RATE   : integer := 115200
    );
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;
        start    : in  std_logic;
        data_in  : in  std_logic_vector(7 downto 0);
        tx       : out std_logic;
        busy     : out std_logic;
        done     : out std_logic
    );
end entity;

architecture rtl of uart_tx is
    constant CLKS_PER_BIT : integer := CLK_FREQ_HZ / BAUD_RATE;
    type state_t is (ST_IDLE, ST_START, ST_DATA, ST_STOP, ST_DONE);
    signal state      : state_t := ST_IDLE;
    signal shreg      : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_idx    : integer range 0 to 7 := 0;
    signal baud_cnt   : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal tx_r       : std_logic := '1';
    signal busy_r     : std_logic := '0';
    signal done_r     : std_logic := '0';
begin
    tx   <= tx_r;
    busy <= busy_r;
    done <= done_r;

    process (clk, reset_n)
    begin
        if reset_n = '0' then
            state    <= ST_IDLE;
            shreg    <= (others => '0');
            bit_idx  <= 0;
            baud_cnt <= 0;
            tx_r     <= '1';
            busy_r   <= '0';
            done_r   <= '0';
        elsif rising_edge(clk) then
            done_r <= '0';
            case state is
                when ST_IDLE =>
                    tx_r   <= '1';
                    busy_r <= '0';
                    baud_cnt <= 0;
                    if start = '1' then
                        shreg   <= data_in;
                        bit_idx <= 0;
                        busy_r  <= '1';
                        state   <= ST_START;
                    end if;

                when ST_START =>
                    tx_r <= '0';
                    if baud_cnt = CLKS_PER_BIT-1 then
                        baud_cnt <= 0;
                        state <= ST_DATA;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;

                when ST_DATA =>
                    tx_r <= shreg(bit_idx);
                    if baud_cnt = CLKS_PER_BIT-1 then
                        baud_cnt <= 0;
                        if bit_idx = 7 then
                            state <= ST_STOP;
                        else
                            bit_idx <= bit_idx + 1;
                        end if;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;

                when ST_STOP =>
                    tx_r <= '1';
                    if baud_cnt = CLKS_PER_BIT-1 then
                        baud_cnt <= 0;
                        state <= ST_DONE;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;

                when ST_DONE =>
                    tx_r   <= '1';
                    busy_r <= '0';
                    done_r <= '1';
                    state  <= ST_IDLE;
            end case;
        end if;
    end process;
end architecture;

