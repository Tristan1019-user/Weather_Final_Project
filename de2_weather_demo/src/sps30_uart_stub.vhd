library ieee;
use ieee.std_logic_1164.all;

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
begin
    process (clk, reset_n)
    begin
        if reset_n = '0' then
            uart_tx  <= '1';
            pm25_x10 <= 120;
            valid    <= '0';
            active   <= '0';
        elsif rising_edge(clk) then
            uart_tx <= '1';
            active  <= '0';
            if poll_tick = '1' then
                -- TODO: replace with a real SPS30 UART SHDLC command sequence.
                -- Bring-up plan:
                -- 1) start measurement
                -- 2) wait for ready interval
                -- 3) request measured values
                -- 4) decode PM2.5 and scale to x10
                pm25_x10 <= 120;
                valid    <= '1';
                active   <= '1';
            end if;
        end if;
    end process;
end architecture;
