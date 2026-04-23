library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_timing_640x480 is
    port (
        clk        : in  std_logic;
        pix_ce     : in  std_logic;
        reset_n    : in  std_logic;
        hcount     : out integer range 0 to 799;
        vcount     : out integer range 0 to 524;
        visible    : out std_logic;
        hsync      : out std_logic;
        vsync      : out std_logic;
        blank_n    : out std_logic;
        sync_n     : out std_logic
    );
end entity;

architecture rtl of vga_timing_640x480 is
    signal h : integer range 0 to 799 := 0;
    signal v : integer range 0 to 524 := 0;
begin
    process (clk, reset_n)
    begin
        if reset_n = '0' then
            h <= 0;
            v <= 0;
        elsif rising_edge(clk) then
            if pix_ce = '1' then
                if h = 799 then
                    h <= 0;
                    if v = 524 then
                        v <= 0;
                    else
                        v <= v + 1;
                    end if;
                else
                    h <= h + 1;
                end if;
            end if;
        end if;
    end process;

    hcount <= h;
    vcount <= v;
    visible <= '1' when (h < 640 and v < 480) else '0';
    hsync <= '0' when (h >= 656 and h < 752) else '1';
    vsync <= '0' when (v >= 490 and v < 492) else '1';
    blank_n <= '1' when (h < 640 and v < 480) else '0';
    sync_n <= '0';
end architecture;

