library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        CLK_FREQ_HZ : integer := 50000000;
        BAUD_RATE   : integer := 115200
    );
    port (
        clk       : in  std_logic;
        reset_n   : in  std_logic;
        rx        : in  std_logic;
        data_out  : out std_logic_vector(7 downto 0);
        data_valid: out std_logic
    );
end entity;

architecture rtl of uart_rx is
    constant CLKS_PER_BIT  : integer := CLK_FREQ_HZ / BAUD_RATE;
    constant HALF_BIT_TICK : integer := CLKS_PER_BIT / 2;
    type state_t is (ST_IDLE, ST_START, ST_DATA, ST_STOP);
    signal state        : state_t := ST_IDLE;
    signal baud_cnt     : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_idx      : integer range 0 to 7 := 0;
    signal shreg        : std_logic_vector(7 downto 0) := (others => '0');
    signal data_valid_r : std_logic := '0';
begin
    data_out   <= shreg;
    data_valid <= data_valid_r;

    process (clk, reset_n)
    begin
        if reset_n = '0' then
            state        <= ST_IDLE;
            baud_cnt     <= 0;
            bit_idx      <= 0;
            shreg        <= (others => '0');
            data_valid_r <= '0';
        elsif rising_edge(clk) then
            data_valid_r <= '0';
            case state is
                when ST_IDLE =>
                    baud_cnt <= 0;
                    bit_idx  <= 0;
                    if rx = '0' then
                        state <= ST_START;
                    end if;

                when ST_START =>
                    if baud_cnt = HALF_BIT_TICK then
                        if rx = '0' then
                            baud_cnt <= 0;
                            state <= ST_DATA;
                        else
                            state <= ST_IDLE;
                        end if;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;

                when ST_DATA =>
                    if baud_cnt = CLKS_PER_BIT-1 then
                        baud_cnt <= 0;
                        shreg(bit_idx) <= rx;
                        if bit_idx = 7 then
                            bit_idx <= 0;
                            state <= ST_STOP;
                        else
                            bit_idx <= bit_idx + 1;
                        end if;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;

                when ST_STOP =>
                    if baud_cnt = CLKS_PER_BIT-1 then
                        baud_cnt <= 0;
                        data_valid_r <= '1';
                        state <= ST_IDLE;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;
            end case;
        end if;
    end process;
end architecture;
