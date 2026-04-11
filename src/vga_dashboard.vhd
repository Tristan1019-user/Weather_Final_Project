library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_dashboard is
    port (
        clk          : in  std_logic;
        pix_ce       : in  std_logic;
        reset_n      : in  std_logic;
        temp_x10     : in  integer range 0 to 999;
        humid_x10    : in  integer range 0 to 1000;
        press_hpa    : in  integer range 300 to 1200;
        pm25_x10     : in  integer range 0 to 2000;
        light_pct    : in  integer range 0 to 100;
        temp_status  : in  std_logic_vector(1 downto 0);
        humid_status : in  std_logic_vector(1 downto 0);
        press_status : in  std_logic_vector(1 downto 0);
        pm_status    : in  std_logic_vector(1 downto 0);
        sensor_valid : in  std_logic;
        sensor_tick  : in  std_logic;
        remote_fresh : in  std_logic;
        vga_r        : out std_logic_vector(7 downto 0);
        vga_g        : out std_logic_vector(7 downto 0);
        vga_b        : out std_logic_vector(7 downto 0);
        vga_hs       : out std_logic;
        vga_vs       : out std_logic;
        vga_blank_n  : out std_logic;
        vga_sync_n   : out std_logic
    );
end entity;

architecture rtl of vga_dashboard is
    function clamp(value, lo, hi : integer) return integer is
    begin
        if value < lo then
            return lo;
        elsif value > hi then
            return hi;
        else
            return value;
        end if;
    end function;

    signal x        : integer range 0 to 799;
    signal y        : integer range 0 to 524;
    signal visible  : std_logic;
    signal r        : std_logic_vector(7 downto 0) := (others => '0');
    signal g        : std_logic_vector(7 downto 0) := (others => '0');
    signal b        : std_logic_vector(7 downto 0) := (others => '0');

    signal temp_bar  : integer range 0 to 500;
    signal humid_bar : integer range 0 to 500;
    signal press_bar : integer range 0 to 500;
    signal pm_bar    : integer range 0 to 500;
    signal light_bar : integer range 0 to 500;
begin
    u_timing : entity work.vga_timing_640x480
        port map (
            clk     => clk,
            pix_ce  => pix_ce,
            reset_n => reset_n,
            hcount  => x,
            vcount  => y,
            visible => visible,
            hsync   => vga_hs,
            vsync   => vga_vs,
            blank_n => vga_blank_n,
            sync_n  => vga_sync_n
        );

    temp_bar  <= clamp((temp_x10 * 500) / 400, 0, 500);
    humid_bar <= clamp((humid_x10 * 500) / 1000, 0, 500);
    press_bar <= clamp(((press_hpa - 900) * 500) / 200, 0, 500);
    pm_bar    <= clamp(pm25_x10, 0, 500);
    light_bar <= clamp(light_pct * 5, 0, 500);

    process (x, y, visible, temp_bar, humid_bar, press_bar, pm_bar, light_bar,
             temp_status, humid_status, press_status, pm_status,
             sensor_valid, sensor_tick, remote_fresh)
    begin
        r <= (others => '0');
        g <= (others => '0');
        b <= (others => '0');

        if visible = '1' then
            r <= x"08";
            g <= x"08";
            b <= x"14";

            if (y = 60) or (y = 150) or (y = 240) or (y = 330) or (y = 420) then
                r <= x"40";
                g <= x"40";
                b <= x"40";
            end if;

            if (x >= 20 and x < 60) and (y >= 80 and y < 130) then
                if temp_status = "00" then r <= x"00"; g <= x"D0"; b <= x"20";
                elsif temp_status = "01" then r <= x"40"; g <= x"80"; b <= x"FF";
                else r <= x"FF"; g <= x"20"; b <= x"20"; end if;
            elsif (x >= 20 and x < 60) and (y >= 170 and y < 220) then
                if humid_status = "00" then r <= x"00"; g <= x"D0"; b <= x"20";
                elsif humid_status = "01" then r <= x"FF"; g <= x"D0"; b <= x"20";
                else r <= x"20"; g <= x"80"; b <= x"FF"; end if;
            elsif (x >= 20 and x < 60) and (y >= 260 and y < 310) then
                if press_status = "00" then r <= x"00"; g <= x"D0"; b <= x"20";
                elsif press_status = "01" then r <= x"20"; g <= x"80"; b <= x"FF";
                else r <= x"FF"; g <= x"A0"; b <= x"20"; end if;
            elsif (x >= 20 and x < 60) and (y >= 350 and y < 400) then
                if pm_status = "00" then r <= x"00"; g <= x"D0"; b <= x"20";
                elsif pm_status = "01" then r <= x"FF"; g <= x"D0"; b <= x"20";
                else r <= x"FF"; g <= x"20"; b <= x"20"; end if;
            end if;

            if (x >= 100 and x < 600) and (y >= 90 and y < 120) then
                r <= x"20"; g <= x"20"; b <= x"20";
                if x < 100 + temp_bar then r <= x"FF"; g <= x"60"; b <= x"40"; end if;
            elsif (x >= 100 and x < 600) and (y >= 180 and y < 210) then
                r <= x"20"; g <= x"20"; b <= x"20";
                if x < 100 + humid_bar then r <= x"40"; g <= x"A0"; b <= x"FF"; end if;
            elsif (x >= 100 and x < 600) and (y >= 270 and y < 300) then
                r <= x"20"; g <= x"20"; b <= x"20";
                if x < 100 + press_bar then r <= x"60"; g <= x"FF"; b <= x"80"; end if;
            elsif (x >= 100 and x < 600) and (y >= 360 and y < 390) then
                r <= x"20"; g <= x"20"; b <= x"20";
                if x < 100 + pm_bar then r <= x"FF"; g <= x"B0"; b <= x"20"; end if;
            elsif (x >= 100 and x < 600) and (y >= 435 and y < 455) then
                r <= x"20"; g <= x"20"; b <= x"20";
                if x < 100 + light_bar then r <= x"FF"; g <= x"FF"; b <= x"60"; end if;
            end if;

            if (x >= 0 and x < 640) and (y >= 0 and y < 30) then
                if remote_fresh = '1' then
                    r <= x"70";
                    g <= x"20";
                    b <= x"D0";
                elsif sensor_valid = '1' then
                    r <= x"00";
                    g <= x"B0";
                    b <= x"20";
                else
                    r <= x"C0";
                    g <= x"20";
                    b <= x"20";
                end if;
            end if;

            if (x >= 560 and x < 590) and (y >= 90 and y < 120) then
                if remote_fresh = '1' then
                    r <= x"60";
                    g <= x"FF";
                    b <= x"FF";
                else
                    r <= x"20";
                    g <= x"20";
                    b <= x"20";
                end if;
            end if;

            if (x >= 600 and x < 630) and (y >= 90 and y < 120) then
                if sensor_tick = '1' then
                    r <= x"FF";
                    g <= x"FF";
                    b <= x"FF";
                else
                    r <= x"30";
                    g <= x"30";
                    b <= x"30";
                end if;
            end if;
        end if;
    end process;

    vga_r <= r;
    vga_g <= g;
    vga_b <= b;
end architecture;
