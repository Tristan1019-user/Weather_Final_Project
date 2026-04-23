library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.weather_icons_pkg.all;  -- weather icon ROMs

-- ============================================================
-- vga_dashboard.vhd  -  ATMOS Diagnostic Display
-- Layout:
--   Header (52px): time | title | date / location
--   Body left  (x=8..295):   info text box
--   Body right (x=465..595): weather icon circle + temp box
--   Bottom:                  4 bar meters + LEDs
-- ============================================================

entity vga_dashboard is

    port (
        clk25        : in  std_logic;
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
		  hike_status : in std_logic_vector(1 downto 0);
        demo_mode    : in  std_logic;
        sensor_valid : in  std_logic;
        sensor_tick  : in  std_logic;
        sw           : in  std_logic_vector(5 downto 0);
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

    signal h_count : integer range 0 to 799 := 0;
    signal v_count : integer range 0 to 524 := 0;
    signal active  : std_logic;

    constant CHAR_W : integer := 8;
    constant CHAR_H : integer := 16;

    -- -------------------------------------------------------
    -- Header 52px
    -- ROW0 y=6:  HH:MM (left) | DD.MM.YYYY (right)
    -- ROW1 y=30: ATMOS Diagnostic (centre, 12px wide glyphs)
    --            | Location name (right)
    -- -------------------------------------------------------
    constant HEADER_H    : integer := 52;
    constant HDR_BG_R    : std_logic_vector(7 downto 0) := x"B8";
    constant HDR_BG_G    : std_logic_vector(7 downto 0) := x"C8";
    constant HDR_BG_B    : std_logic_vector(7 downto 0) := x"E8";
    constant HDR_TXT_R   : std_logic_vector(7 downto 0) := x"1A";
    constant HDR_TXT_G   : std_logic_vector(7 downto 0) := x"1A";
    constant HDR_TXT_B   : std_logic_vector(7 downto 0) := x"3A";

    constant ROW0_Y      : integer := 8;   -- time + date (moved down slightly)
    constant ROW1_Y      : integer := 30;  -- title + loc (moved up slightly)

    constant TIME_X      : integer := 8;
    constant DATE_CHARS  : integer := 10;
    constant DATE_X      : integer := 636 - DATE_CHARS * CHAR_W;

    -- Title: render at 12px wide per glyph (1.5x scale by skipping every 3rd col)
    -- "ATMOS Diagnostic" = 16 chars * 12px = 192px, centred in 640
    constant TITLE_GLYPH_W : integer := 12;
    constant TITLE_CHARS   : integer := 16;
    constant TITLE_PX_W    : integer := TITLE_CHARS * TITLE_GLYPH_W;  -- 192
    constant TITLE_X       : integer := (640 - TITLE_PX_W) / 2;       -- 224
    constant TITLE_Y       : integer := 28;   -- slightly higher than ROW1

    constant LOC_RIGHT   : integer := 636;

    -- -------------------------------------------------------
    -- Body colours
    -- -------------------------------------------------------
    constant BODY_R   : std_logic_vector(7 downto 0) := x"33";
    constant BODY_G   : std_logic_vector(7 downto 0) := x"33";
    constant BODY_B   : std_logic_vector(7 downto 0) := x"36";
    constant TRACK_R  : std_logic_vector(7 downto 0) := x"4A";
    constant TRACK_G  : std_logic_vector(7 downto 0) := x"4A";
    constant TRACK_B  : std_logic_vector(7 downto 0) := x"4A";
    -- Light grey for info box and circle background
    constant LGREY_R  : std_logic_vector(7 downto 0) := x"EB";
    constant LGREY_G  : std_logic_vector(7 downto 0) := x"EB";
    constant LGREY_B  : std_logic_vector(7 downto 0) := x"EB";
    -- Info box text colour (dark grey)
    constant ITXT_R   : std_logic_vector(7 downto 0) := x"2A";
    constant ITXT_G   : std_logic_vector(7 downto 0) := x"2A";
    constant ITXT_B   : std_logic_vector(7 downto 0) := x"2A";

    -- -------------------------------------------------------
    -- Info text box (left side of body)
    -- -------------------------------------------------------
    constant INFO_X1  : integer := 8;
    constant INFO_X2  : integer := 295;
    constant INFO_Y1  : integer := 58;
    constant INFO_Y2  : integer := 268;
    constant INFO_PAD : integer := 6;   -- inner padding
    -- text starts at x=14, y=64, width=34 chars, max 8 rows

    -- -------------------------------------------------------
    -- Weather icon circle (top right of body)
    -- -------------------------------------------------------
    constant CIRC_CX  : integer := 530;
    constant CIRC_CY  : integer := 147;
    constant CIRC_R   : integer := 72;

    -- -------------------------------------------------------
    -- Temp reading box (below circle)
    -- -------------------------------------------------------
    constant TEMP_X1  : integer := 498;
    constant TEMP_Y1  : integer := 223;
    constant TEMP_X2  : integer := 562;
    constant TEMP_Y2  : integer := 247;
    -- temp text centred inside, 6 chars "XX.X C" max

    -- -------------------------------------------------------
    -- Bar meters (bottom)
    -- -------------------------------------------------------
    constant BAR_W    : integer := 40;
    constant BAR_H    : integer := 120;
    constant BAR_BOT  : integer := 428;
    constant BAR_TOP  : integer := BAR_BOT - BAR_H;
    constant BAR0_X   : integer := 100;
    constant BAR1_X   : integer := 220;
    constant BAR2_X   : integer := 380;
    constant BAR3_X   : integer := 500;
    constant LABEL_Y  : integer := BAR_BOT + 3;
    constant LED_CY   : integer := LABEL_Y + CHAR_H + 6;
    constant LED_RX   : integer := 8;   -- horizontal radius
    constant LED_RY   : integer := 8;   -- vertical radius (equal = circle)

    -- -------------------------------------------------------
    -- 8x16 font ROM (complete for all needed characters)
    -- -------------------------------------------------------
    type font_rom_t is array (0 to 127, 0 to 15) of std_logic_vector(7 downto 0);
    constant FONT_ROM : font_rom_t := (
        -- SPACE (32->0)
        0  => (x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- ' apostrophe (39->7)
        7  => (x"00",x"18",x"18",x"18",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- + (43->11)
        11 => (x"00",x"00",x"18",x"18",x"18",x"7E",x"18",x"18",x"18",x"00",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- , comma (44->12)
        12 => (x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"18",x"18",x"30",x"00",x"00",x"00",x"00"),
        -- - hyphen (45->13)
        13 => (x"00",x"00",x"00",x"00",x"00",x"00",x"7E",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- . period (46->14)
        14 => (x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"18",x"18",x"00",x"00",x"00",x"00"),
        -- / (47->15)
        15 => (x"00",x"02",x"02",x"06",x"04",x"0C",x"08",x"18",x"10",x"30",x"20",x"60",x"40",x"00",x"00",x"00"),
        -- 0-9 (48-57 -> 16-25)
        16 => (x"00",x"3C",x"66",x"6E",x"76",x"66",x"66",x"66",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        17 => (x"00",x"18",x"38",x"18",x"18",x"18",x"18",x"18",x"18",x"7E",x"00",x"00",x"00",x"00",x"00",x"00"),
        18 => (x"00",x"3C",x"66",x"06",x"06",x"0C",x"18",x"30",x"60",x"7E",x"00",x"00",x"00",x"00",x"00",x"00"),
        19 => (x"00",x"3C",x"66",x"06",x"06",x"1C",x"06",x"06",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        20 => (x"00",x"0C",x"1C",x"2C",x"4C",x"CC",x"FE",x"0C",x"0C",x"0C",x"00",x"00",x"00",x"00",x"00",x"00"),
        21 => (x"00",x"7E",x"60",x"60",x"7C",x"06",x"06",x"06",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        22 => (x"00",x"1C",x"30",x"60",x"7C",x"66",x"66",x"66",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        23 => (x"00",x"7E",x"06",x"06",x"0C",x"0C",x"18",x"18",x"30",x"30",x"00",x"00",x"00",x"00",x"00",x"00"),
        24 => (x"00",x"3C",x"66",x"66",x"66",x"3C",x"66",x"66",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        25 => (x"00",x"3C",x"66",x"66",x"66",x"3E",x"06",x"06",x"0C",x"38",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- : (58->26)
        26 => (x"00",x"00",x"00",x"18",x"18",x"00",x"00",x"18",x"18",x"00",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- degree symbol as small circle (176->not in range; use index 3 = ascii 35 = # repurposed)
        -- We'll use index 3 for degree symbol
        3  => (x"00",x"1C",x"22",x"22",x"1C",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- A-Z (65-90 -> 33-58)
        33 => (x"00",x"18",x"18",x"3C",x"24",x"66",x"66",x"7E",x"C3",x"C3",x"00",x"00",x"00",x"00",x"00",x"00"),
        34 => (x"00",x"FC",x"66",x"66",x"66",x"7C",x"66",x"66",x"66",x"FC",x"00",x"00",x"00",x"00",x"00",x"00"),
        35 => (x"00",x"3C",x"66",x"C0",x"C0",x"C0",x"C0",x"C0",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        36 => (x"00",x"F8",x"6C",x"66",x"66",x"66",x"66",x"66",x"6C",x"F8",x"00",x"00",x"00",x"00",x"00",x"00"),
        37 => (x"00",x"FE",x"60",x"60",x"60",x"7C",x"60",x"60",x"60",x"FE",x"00",x"00",x"00",x"00",x"00",x"00"),
        38 => (x"00",x"FE",x"60",x"60",x"60",x"7C",x"60",x"60",x"60",x"60",x"00",x"00",x"00",x"00",x"00",x"00"),
        39 => (x"00",x"3C",x"66",x"C0",x"C0",x"CE",x"C6",x"C6",x"66",x"3A",x"00",x"00",x"00",x"00",x"00",x"00"),
        40 => (x"00",x"C3",x"C3",x"C3",x"C3",x"FF",x"C3",x"C3",x"C3",x"C3",x"00",x"00",x"00",x"00",x"00",x"00"),
        41 => (x"00",x"3C",x"18",x"18",x"18",x"18",x"18",x"18",x"18",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        42 => (x"00",x"1E",x"0C",x"0C",x"0C",x"0C",x"0C",x"CC",x"CC",x"78",x"00",x"00",x"00",x"00",x"00",x"00"),
        43 => (x"00",x"C6",x"CC",x"D8",x"F0",x"E0",x"F0",x"D8",x"CC",x"C6",x"00",x"00",x"00",x"00",x"00",x"00"),
        44 => (x"00",x"60",x"60",x"60",x"60",x"60",x"60",x"60",x"60",x"FE",x"00",x"00",x"00",x"00",x"00",x"00"),
        45 => (x"00",x"C3",x"E7",x"FF",x"DB",x"C3",x"C3",x"C3",x"C3",x"C3",x"00",x"00",x"00",x"00",x"00",x"00"),
        46 => (x"00",x"C3",x"E3",x"F3",x"DB",x"CF",x"C7",x"C3",x"C3",x"C3",x"00",x"00",x"00",x"00",x"00",x"00"),
        47 => (x"00",x"3C",x"66",x"C3",x"C3",x"C3",x"C3",x"C3",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        48 => (x"00",x"FC",x"66",x"66",x"66",x"7C",x"60",x"60",x"60",x"60",x"00",x"00",x"00",x"00",x"00",x"00"),
        49 => (x"00",x"3C",x"66",x"C3",x"C3",x"C3",x"DB",x"CF",x"66",x"3C",x"03",x"00",x"00",x"00",x"00",x"00"),
        50 => (x"00",x"FC",x"66",x"66",x"66",x"7C",x"78",x"6C",x"66",x"63",x"00",x"00",x"00",x"00",x"00",x"00"),
        51 => (x"00",x"3C",x"66",x"60",x"60",x"3C",x"06",x"06",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        52 => (x"00",x"FF",x"18",x"18",x"18",x"18",x"18",x"18",x"18",x"18",x"00",x"00",x"00",x"00",x"00",x"00"),
        53 => (x"00",x"C3",x"C3",x"C3",x"C3",x"C3",x"C3",x"C3",x"C3",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        54 => (x"00",x"C3",x"C3",x"C3",x"66",x"66",x"3C",x"3C",x"18",x"18",x"00",x"00",x"00",x"00",x"00",x"00"),
        55 => (x"00",x"C3",x"C3",x"C3",x"C3",x"DB",x"DB",x"FF",x"66",x"66",x"00",x"00",x"00",x"00",x"00",x"00"),
        56 => (x"00",x"C3",x"C3",x"66",x"3C",x"18",x"3C",x"66",x"C3",x"C3",x"00",x"00",x"00",x"00",x"00",x"00"),
        57 => (x"00",x"C3",x"C3",x"66",x"3C",x"18",x"18",x"18",x"18",x"18",x"00",x"00",x"00",x"00",x"00",x"00"),
        58 => (x"00",x"FF",x"03",x"06",x"0C",x"18",x"30",x"60",x"C0",x"FF",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- a-z (97-122 -> 65-90)
        65 => (x"00",x"00",x"00",x"3C",x"06",x"3E",x"66",x"66",x"66",x"3B",x"00",x"00",x"00",x"00",x"00",x"00"),
        66 => (x"00",x"60",x"60",x"7C",x"66",x"66",x"66",x"66",x"66",x"7C",x"00",x"00",x"00",x"00",x"00",x"00"),
        67 => (x"00",x"00",x"00",x"3C",x"66",x"60",x"60",x"60",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        68 => (x"00",x"06",x"06",x"3E",x"66",x"66",x"66",x"66",x"66",x"3E",x"00",x"00",x"00",x"00",x"00",x"00"),
        69 => (x"00",x"00",x"00",x"3C",x"66",x"66",x"7E",x"60",x"60",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        70 => (x"00",x"1C",x"30",x"30",x"7C",x"30",x"30",x"30",x"30",x"30",x"00",x"00",x"00",x"00",x"00",x"00"),
        71 => (x"00",x"00",x"00",x"3E",x"66",x"66",x"66",x"3E",x"06",x"06",x"7C",x"00",x"00",x"00",x"00",x"00"),
        72 => (x"00",x"60",x"60",x"7C",x"66",x"66",x"66",x"66",x"66",x"66",x"00",x"00",x"00",x"00",x"00",x"00"),
        73 => (x"00",x"18",x"00",x"38",x"18",x"18",x"18",x"18",x"18",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        74 => (x"00",x"06",x"00",x"06",x"06",x"06",x"06",x"06",x"06",x"06",x"66",x"3C",x"00",x"00",x"00",x"00"),
        75 => (x"00",x"60",x"60",x"66",x"6C",x"78",x"78",x"6C",x"66",x"63",x"00",x"00",x"00",x"00",x"00",x"00"),
        76 => (x"00",x"38",x"18",x"18",x"18",x"18",x"18",x"18",x"18",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        77 => (x"00",x"00",x"00",x"E6",x"FF",x"DB",x"DB",x"DB",x"DB",x"DB",x"00",x"00",x"00",x"00",x"00",x"00"),
        78 => (x"00",x"00",x"00",x"7C",x"66",x"66",x"66",x"66",x"66",x"66",x"00",x"00",x"00",x"00",x"00",x"00"),
        79 => (x"00",x"00",x"00",x"3C",x"66",x"66",x"66",x"66",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- p (112->80) was missing
        80 => (x"00",x"00",x"00",x"7C",x"66",x"66",x"66",x"7C",x"60",x"60",x"60",x"00",x"00",x"00",x"00",x"00"),
        81 => (x"00",x"00",x"00",x"3E",x"66",x"66",x"66",x"3E",x"06",x"06",x"06",x"00",x"00",x"00",x"00",x"00"),
        82 => (x"00",x"00",x"00",x"7C",x"66",x"60",x"60",x"60",x"60",x"60",x"00",x"00",x"00",x"00",x"00",x"00"),
        83 => (x"00",x"00",x"00",x"3C",x"66",x"60",x"3C",x"06",x"66",x"3C",x"00",x"00",x"00",x"00",x"00",x"00"),
        84 => (x"00",x"30",x"30",x"FC",x"30",x"30",x"30",x"30",x"30",x"1C",x"00",x"00",x"00",x"00",x"00",x"00"),
        85 => (x"00",x"00",x"00",x"66",x"66",x"66",x"66",x"66",x"66",x"3B",x"00",x"00",x"00",x"00",x"00",x"00"),
        -- v (118->86) was missing
        86 => (x"00",x"00",x"00",x"66",x"66",x"66",x"66",x"3C",x"3C",x"18",x"00",x"00",x"00",x"00",x"00",x"00"),
        87 => (x"00",x"00",x"00",x"DB",x"DB",x"DB",x"DB",x"FF",x"66",x"66",x"00",x"00",x"00",x"00",x"00",x"00"),
        88 => (x"00",x"00",x"00",x"66",x"66",x"3C",x"18",x"3C",x"66",x"66",x"00",x"00",x"00",x"00",x"00",x"00"),
        89 => (x"00",x"00",x"00",x"66",x"66",x"66",x"3E",x"06",x"06",x"7C",x"00",x"00",x"00",x"00",x"00",x"00"),
        90 => (x"00",x"00",x"00",x"7E",x"06",x"0C",x"18",x"30",x"60",x"7E",x"00",x"00",x"00",x"00",x"00",x"00"),
        others => (x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00")
    );

    -- -------------------------------------------------------
    -- Location name strings
    -- -------------------------------------------------------
    type loc_str_t is array (0 to 23) of integer range 0 to 127;
    type loc_arr_t is array (0 to 5)  of loc_str_t;
    type loc_len_t is array (0 to 5)  of integer range 1 to 24;
    constant LOC_LENS : loc_len_t := (17, 22, 22, 11, 24, 17);
    constant LOCS : loc_arr_t := (
        0 => (80,101,114,99,121,32,87,97,114,110,101,114,32,80,97,114,107,32,32,32,32,32,32,32),
        1 => (82,97,100,110,111,114,32,76,97,107,101,32,83,116,97,116,101,32,80,97,114,107,32,32),
        2 => (76,111,110,103,32,72,117,110,116,101,114,32,83,116,97,116,101,32,80,97,114,107,32,32),
        3 => (66,101,97,109,97,110,32,80,97,114,107,32,32,32,32,32,32,32,32,32,32,32,32,32),
        4 => (72,97,114,112,101,116,104,32,82,105,118,101,114,32,83,116,97,116,101,32,80,97,114,107),
        5 => (69,100,119,105,110,32,87,97,114,110,101,114,32,80,97,114,107,32,32,32,32,32,32,32)
    );

    -- -------------------------------------------------------
    -- Title string
    -- -------------------------------------------------------
    type title_str_t is array (0 to 15) of integer range 0 to 127;
    constant TITLE_STR : title_str_t :=
        (65,84,77,79,83,32,68,105,97,103,110,111,115,116,105,99);

    -- -------------------------------------------------------
    -- Description text: 6 locations x 8 rows x 34 chars
    -- -------------------------------------------------------
    constant DESC_ROWS : integer := 8;
    constant DESC_COLS : integer := 34;
    type desc_row_t  is array (0 to DESC_COLS-1) of integer range 0 to 127;
    type desc_loc_t  is array (0 to DESC_ROWS-1) of desc_row_t;
    type desc_all_t  is array (0 to 5) of desc_loc_t;

    constant DESC : desc_all_t := (
        -- Location 0: Percy Warner Park
        0 => (
            (79,118,101,114,32,50,48,32,109,105,108,101,115,32,111,102,32,104,105,107,105,110,103,32,116,114,97,105,108,115,32,32,32,32),
            (119,105,110,100,105,110,103,32,116,104,114,111,117,103,104,32,102,111,114,101,115,116,101,100,32,104,105,108,108,115,32,32,32,32),
            (119,105,116,104,32,115,99,101,110,105,99,32,111,118,101,114,108,111,111,107,115,46,32,80,111,112,117,108,97,114,32,32,32,32),
            (119,105,116,104,32,116,114,97,105,108,32,114,117,110,110,101,114,115,32,97,110,100,32,100,111,103,32,32,32,32,32,32,32,32),
            (119,97,108,107,101,114,115,44,32,119,105,116,104,32,100,101,101,114,32,97,110,100,32,119,105,108,100,32,116,117,114,107,101,121),
            (99,111,109,109,111,110,108,121,32,115,112,111,116,116,101,100,46,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32)
        ),
        -- Location 1: Radnor Lake State Park
        1 => (
            (70,101,97,116,117,114,101,115,32,54,32,116,114,97,105,108,115,32,114,97,110,103,105,110,103,32,102,114,111,109,32,32,32,32),
            (101,97,115,121,32,108,97,107,101,115,105,100,101,32,112,97,116,104,115,32,116,111,32,114,117,103,103,101,100,32,32,32,32,32),
            (114,105,100,103,101,32,104,105,107,101,115,44,32,97,108,108,32,119,105,116,104,105,110,32,97,32,32,32,32,32,32,32,32,32),
            (112,114,111,116,101,99,116,101,100,32,110,97,116,117,114,97,108,32,97,114,101,97,46,32,65,98,117,110,100,97,110,116,32,32),
            (119,105,108,100,108,105,102,101,32,105,110,99,108,117,100,105,110,103,32,98,108,117,101,32,104,101,114,111,110,115,44,32,32,32),
            (98,97,108,100,32,101,97,103,108,101,115,44,32,112,97,105,110,116,101,100,32,116,117,114,116,108,101,115,44,32,97,110,100,32),
            (119,104,105,116,101,45,116,97,105,108,101,100,32,100,101,101,114,46,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32)
        ),
        -- Location 2: Long Hunter State Park
        2 => (
            (79,102,102,101,114,115,32,52,32,109,97,105,110,32,116,114,97,105,108,115,32,116,111,116,97,108,105,110,103,32,32,32,32,32),
            (114,111,117,103,104,108,121,32,50,48,32,109,105,108,101,115,32,97,108,111,110,103,32,116,104,101,32,115,104,111,114,101,115,32),
            (111,102,32,80,101,114,99,121,32,80,114,105,101,115,116,32,76,97,107,101,32,119,105,116,104,32,99,101,100,97,114,32,32,32),
            (97,110,100,32,104,105,99,107,111,114,121,32,102,111,114,101,115,116,32,118,105,101,119,115,46,32,32,32,32,32,32,32,32,32),
            (70,114,101,113,117,101,110,116,108,121,32,118,105,115,105,116,101,100,32,98,121,32,100,101,101,114,44,32,32,32,32,32,32,32),
            (98,117,116,116,101,114,102,108,105,101,115,44,32,104,101,114,111,110,115,44,32,97,110,100,32,116,104,101,32,32,32,32,32,32),
            (111,99,99,97,115,105,111,110,97,108,32,119,105,108,100,32,116,117,114,107,101,121,46,32,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32)
        ),
        -- Location 3: Beaman Park
        3 => (
            (79,110,101,32,111,102,32,78,97,115,104,118,105,108,108,101,39,115,32,109,111,115,116,32,117,110,100,101,114,114,97,116,101,100),
            (112,97,114,107,115,32,119,105,116,104,32,111,118,101,114,32,49,44,55,48,48,32,97,99,114,101,115,32,97,110,100,32,49,52),
            (109,105,108,101,115,32,111,102,32,109,111,100,101,114,97,116,101,32,110,97,116,117,114,97,108,32,116,114,97,105,108,115,46,32),
            (72,111,109,101,32,116,111,32,69,97,115,116,101,114,110,32,98,108,117,101,98,105,114,100,115,44,32,102,111,120,101,115,44,32),
            (115,97,108,97,109,97,110,100,101,114,115,44,32,97,110,100,32,97,32,114,105,99,104,32,118,97,114,105,101,116,121,32,111,102),
            (119,105,108,100,102,108,111,119,101,114,115,32,97,110,100,32,104,97,114,100,119,111,111,100,32,102,111,114,101,115,116,46,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32)
        ),
        -- Location 4: Harpeth River State Park
        4 => (
            (84,104,114,101,101,32,100,105,115,116,105,110,99,116,32,116,114,97,105,108,115,32,105,110,99,108,117,100,105,110,103,32,32,32),
            (116,104,101,32,115,116,101,101,112,32,66,108,117,102,102,32,84,114,97,105,108,32,119,105,116,104,32,97,32,32,32,32,32,32),
            (115,116,117,110,110,105,110,103,32,52,55,48,45,102,111,111,116,32,101,108,101,118,97,116,105,111,110,32,99,108,105,109,98,32),
            (111,118,101,114,108,111,111,107,105,110,103,32,116,104,101,32,72,97,114,112,101,116,104,32,82,105,118,101,114,46,32,32,32,32),
            (87,105,108,100,108,105,102,101,32,105,110,99,108,117,100,101,115,32,114,105,118,101,114,32,111,116,116,101,114,115,44,32,32,32),
            (104,101,114,111,110,115,44,32,109,117,115,107,114,97,116,115,44,32,97,110,100,32,100,105,118,101,114,115,101,32,98,105,114,100),
            (115,112,101,99,105,101,115,32,97,108,111,110,103,32,116,104,101,32,119,97,116,101,114,46,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32)
        ),
        -- Location 5: Edwin Warner Park
        5 => (
            (65,100,106,97,99,101,110,116,32,116,111,32,80,101,114,99,121,32,87,97,114,110,101,114,44,32,111,102,102,101,114,105,110,103),
            (49,48,43,32,109,105,108,101,115,32,111,102,32,103,101,110,116,108,101,114,32,116,114,97,105,108,115,32,105,100,101,97,108,32),
            (102,111,114,32,102,97,109,105,108,105,101,115,32,97,110,100,32,98,101,103,105,110,110,101,114,115,46,32,83,104,97,114,101,115),
            (116,104,101,32,115,97,109,101,32,114,105,99,104,32,119,111,111,100,108,97,110,100,32,101,99,111,115,121,115,116,101,109,32,32),
            (119,105,116,104,32,102,114,101,113,117,101,110,116,32,100,101,101,114,44,32,115,111,110,103,98,105,114,100,44,32,97,110,100,32),
            (119,105,108,100,32,116,117,114,107,101,121,32,115,105,103,104,116,105,110,103,115,46,32,32,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32),
            (32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32)
        )
    );
	 constant LIVE_DEMO_TXT : string := "LIVE DEMO MODE";
	 constant LIVE_DATA_TXT : string := "LIVE DATA MODE";
	 
	 
	 type hike_row_t is array (0 to 33) of integer range 0 to 127;

		constant HIKE_LABEL : hike_row_t := (
			 0=>72, 1=>73, 2=>75, 3=>69, 4=>32, 5=>83, 6=>84, 7=>65, 8=>84, 9=>85, 10=>83, 11=>58,
			 others=>32
		);

		constant HIKE_YES : hike_row_t := (
			 0=>89, 1=>69, 2=>83,
			 others=>32
		);

		constant HIKE_MAYBE : hike_row_t := (
			 0=>77, 1=>65, 2=>89, 3=>66, 4=>69,
			 others=>32
		);

		constant HIKE_NO : hike_row_t := (
			 0=>78, 1=>79,
			 others=>32
		);

    -- Bar labels
    type label3_t is array (0 to 2) of integer range 0 to 127;
    type labels_t is array (0 to 3) of label3_t;
    constant BAR_LABELS : labels_t := (
        0=>(76,71,84), 1=>(72,85,77), 2=>(66,65,82), 3=>(65,81,73));
    constant LABEL_OFFSET : integer := 6;
    constant LABEL_GAP    : integer := 2;

    -- -------------------------------------------------------
    -- Clock
    -- -------------------------------------------------------
    signal sec_count  : integer range 0 to 59 := 10;   -- PATCHED_SEC
    signal min_count  : integer range 0 to 59 := 11;   -- PATCHED_MIN
    signal hour_count : integer range 0 to 23 := 14;  -- PATCHED_HOUR

    -- -------------------------------------------------------
    -- Bar demo values
    -- -------------------------------------------------------
    -- Per-location fixed sensor values (randomised at compile)
    type loc_vals_t is array (0 to 5) of integer range 0 to 100;
    type loc_temp_t is array (0 to 5) of integer range 0 to 999;
    constant LGT_VALS : loc_vals_t := (48, 57, 72, 66, 31, 58);
	 constant HUM_VALS : loc_vals_t := (52, 46, 68, 72, 85, 34);
	 constant BAR_VALS : loc_vals_t := (74, 61, 45, 52, 28, 48);
	 constant AQI_VALS : loc_vals_t := (81, 72, 44, 50, 22, 41);
	 constant TMP_VALS : loc_temp_t := (224, 198, 287, 276, 342, 305);

    -- LED status
    signal lgt_led   : std_logic_vector(1 downto 0);
    signal hum_led   : std_logic_vector(1 downto 0);
    signal bar_led   : std_logic_vector(1 downto 0);
    signal aqi_led   : std_logic_vector(1 downto 0);
    signal tmp_led   : std_logic_vector(1 downto 0);  -- 00=green 01=orange 10=red
	 signal hike_demo_status : std_logic_vector(1 downto 0) := "01";
	 
	 signal auto_idx   : integer range 0 to 5 := 0;
	 signal slow_count : integer range 0 to 49999999 := 0;

    signal loc_idx   : integer range 0 to 5 := 0;
	 signal live_lgt : integer range 0 to 100 := 50;
	 signal live_hum : integer range 0 to 100 := 55;
	 signal live_bar : integer range 0 to 100 := 60;
	 signal live_aqi : integer range 0 to 100 := 45;
	 signal live_tmp : integer range 150 to 400 := 250;

	 signal disp_lgt     : integer range 0 to 100 := 50;
	 signal lgt_from_sensor : integer range 0 to 100 := 0; -- inverted digital input
	 signal disp_hum : integer range 0 to 100 := 55;
	 signal disp_bar : integer range 0 to 100 := 60;
	 signal disp_aqi : integer range 0 to 100 := 45;
	 signal disp_tmp : integer range 0 to 400 := 0;
	 signal header_txt : loc_str_t;
	 signal header_len : integer range 1 to 24 := 24;
		 

    -- Rendering
    signal in_header    : std_logic;
    signal hdr_ascii    : integer range 0 to 127;
    signal hdr_glyph_x  : integer range 0 to 11;
    signal hdr_glyph_y  : integer range 0 to 15;
    signal hdr_font_idx : integer range 0 to 127;
    signal hdr_font_row : std_logic_vector(7 downto 0);
    signal hdr_pixel    : std_logic;

    signal in_info      : std_logic;
    signal info_pixel   : std_logic;
    signal info_ascii   : integer range 0 to 127;

    signal in_circle    : std_logic;
    signal in_temp_box  : std_logic;
    signal temp_pixel   : std_logic;

    signal in_any_bar   : std_logic;
    signal which_bar    : integer range 0 to 3;
    signal bar_py       : integer range 0 to BAR_H-1;
    signal bar_fill_h   : integer range 0 to BAR_H;
    signal bar_fill_y   : integer range 0 to BAR_H;
    signal in_led       : std_logic;
    signal in_label     : std_logic;
    signal led_status   : std_logic_vector(1 downto 0);
    signal label_pixel  : std_logic;

    -- temp reading (demo: from temp_x10, e.g. 253 = 25.3C)
    -- display as "XX.XC" 5 chars
    signal temp_disp_h  : integer range 0 to 9;  -- tens
    signal temp_disp_l  : integer range 0 to 9;  -- units
    signal temp_disp_f  : integer range 0 to 9;  -- fraction

    -- Weather icon (0=SUN 1=MOON 2=RAIN 3=OVERCAST)
    signal icon_sel      : integer range 0 to 3 := 0;
    signal icon_pixel_r  : std_logic_vector(7 downto 0);
    signal icon_pixel_g  : std_logic_vector(7 downto 0);
    signal icon_pixel_b  : std_logic_vector(7 downto 0);
    signal icon_rom_addr : integer range 0 to ICON_ROM_DEPTH-1;

begin
	 process(lgt_led, hum_led, bar_led, aqi_led, tmp_led)
			 variable red_count    : integer range 0 to 5;
			 variable orange_count : integer range 0 to 5;
		begin
			 red_count := 0;
			 orange_count := 0;

			 if lgt_led = "10" then
				  red_count := red_count + 1;
				 elsif lgt_led = "01" then
					  orange_count := orange_count + 1;
				 end if;

				 if hum_led = "10" then
					  red_count := red_count + 1;
				 elsif hum_led = "01" then
					  orange_count := orange_count + 1;
				 end if;

				 if bar_led = "10" then
					  red_count := red_count + 1;
				 elsif bar_led = "01" then
					  orange_count := orange_count + 1;
				 end if;

				 if aqi_led = "10" then
					  red_count := red_count + 1;
				 elsif aqi_led = "01" then
					  orange_count := orange_count + 1;
				 end if;

				 if tmp_led = "10" then
					  red_count := red_count + 1;
				 elsif tmp_led = "01" then
					  orange_count := orange_count + 1;
				 end if;

				 if red_count >= 2 then
					  hike_demo_status <= "10"; -- NO
				 elsif red_count = 1 or orange_count >= 2 then
					  hike_demo_status <= "01"; -- MAYBE
				 else
					  hike_demo_status <= "00"; -- YES
				 end if;
		end process;
		
		loc_idx <= auto_idx when sw(5) = '1'
          else 0 when sw(4) = '1'
          else to_integer(unsigned(sw(2 downto 0))) mod 6;
			 
		

		process(sw, loc_idx)
		begin
			 if sw(5) = '1' then
				  header_txt <= (76,73,86,69,32,68,69,77,79,32,77,79,68,69,32,32,32,32,32,32,32,32,32,32);
				  header_len <= 14;
			 elsif sw(4) = '1' then
				  header_txt <= (76,73,86,69,32,68,65,84,65,32,77,79,68,69,32,32,32,32,32,32,32,32,32,32);
				  header_len <= 14;
			 else
				  header_txt <= LOCS(loc_idx);
				  header_len <= LOC_LENS(loc_idx);
			 end if;
		end process;
					 
		-- SW5=Live Demo: animated drift  SW4=Live Sensor: real ports (0 until sensor_valid)
		-- LGT: digital input 0=day->100, 1=night->0
		lgt_from_sensor <= 100 when light_pct = 0 else 0;
		disp_lgt <= live_lgt        when sw(5) = '1' else
		            lgt_from_sensor when (sw(4) = '1' and sensor_valid = '1') else
		            0               when sw(4) = '1' else
		            LGT_VALS(loc_idx);
		disp_hum <= live_hum                        when sw(5) = '1' else
		            (humid_x10 / 10)                when (sw(4) = '1' and sensor_valid = '1') else
		            0                               when sw(4) = '1' else
		            HUM_VALS(loc_idx);
		disp_bar <= live_bar                        when sw(5) = '1' else
		            ((press_hpa - 300) * 100 / 900) when (sw(4) = '1' and sensor_valid = '1') else
		            0                               when sw(4) = '1' else
		            BAR_VALS(loc_idx);
		-- AQI sensor broken: fixed at 65 (green) in all modes
		disp_aqi <= 65;
		disp_tmp <= live_tmp                        when sw(5) = '1' else
		            temp_x10                        when (sw(4) = '1' and sensor_valid = '1') else
		            0                               when sw(4) = '1' else
		            TMP_VALS(loc_idx);
		
		process(clk25)
			begin
				 if rising_edge(clk25) then
					  if slow_count = 12499999 then   -- about 0.5 sec at 25 MHz
							slow_count <= 0;
							-- Only advance auto_idx and drift values in live demo mode (sw5)
							if sw(5) = '1' then
							auto_idx <= (auto_idx + 1) mod 6;

							-- live demo values drift slowly
							if live_lgt < 85 then
								 live_lgt <= live_lgt + 3;
							else
								 live_lgt <= 35;
							end if;

							if live_hum < 90 then
								 live_hum <= live_hum + 4;
							else
								 live_hum <= 40;
							end if;

							if live_bar < 80 then
								 live_bar <= live_bar + 5;
							else
								 live_bar <= 25;
							end if;

							if live_aqi < 75 then
								 live_aqi <= live_aqi + 6;
							else
								 live_aqi <= 20;
							end if;

							if live_tmp < 330 then
								 live_tmp <= live_tmp + 7;
							else
								 live_tmp <= 210;
							end if;

							end if; -- sw(5)='1'

					  else
							slow_count <= slow_count + 1;
					  end if;
				 end if;
			end process;
    -- VGA counters
    process(clk25)
    begin
        if rising_edge(clk25) then
            if h_count=799 then
                h_count<=0;
                if v_count=524 then v_count<=0; else v_count<=v_count+1; end if;
            else h_count<=h_count+1; end if;
        end if;
    end process;

    active      <= '1' when h_count<640 and v_count<480 else '0';
    vga_hs      <= '0' when h_count>=656 and h_count<752 else '1';
    vga_vs      <= '0' when v_count>=490 and v_count<492 else '1';
    vga_blank_n <= active;
    vga_sync_n  <= '0';

    -- Clock counter
    process(clk25)
    begin
        if rising_edge(clk25) then
            if sensor_tick='1' then
                if sec_count=59 then
                    sec_count<=0;
                    if min_count=59 then
                        min_count<=0;
                        hour_count<=(hour_count+1) mod 24;
                    else min_count<=min_count+1; end if;
                else sec_count<=sec_count+1; end if;
            end if;
        end if;
    end process;

    -- Bar values fixed at compile-time (randomised initial values)

    -- LED thresholds
    -- LGT: digital day/night ƒ?" day(100)=green, night(0)=red, no orange
    lgt_led <= "00" when disp_lgt >= 50 else "10";
    hum_led <= "00" when (disp_hum>=40 and disp_hum<=60) else
               "10" when (disp_hum<20 or disp_hum>80) else "01";
    bar_led <= "00" when disp_bar>55 else "10" when disp_bar<35 else "01";
    aqi_led <= "00" when disp_aqi>60 else "10" when disp_aqi<30 else "01";
    -- Temp LED: green=18-26C (180-260), orange=10-17.9 or 26.1-33C (100-179/261-330), red=else
    tmp_led <= "00" when (disp_tmp>=180 and disp_tmp<=260) else
               "01" when (disp_tmp>=100 and disp_tmp<=330) else "10";

    -- Icon ROM address
    -- Icon 128x128 at 2:1 scale centred at (530,130): top-left=(466,66)
    -- Each source pixel maps to a 2x2 block: addr = (dy/2)*64 + (dx/2)
    icon_rom_addr <= ((v_count - 83)/2)*64 + ((h_count - 466)/2)
        when (h_count >= 466 and h_count < 594 and
              v_count >= 83  and v_count < 211)
        else 0;

    -- Icon selection logic (all in VHDL, no Python involvement)
    -- Priority: RAIN > OVERCAST > MOON > SUN
    --
    -- RAIN:     humidity > 75 AND pressure < 40 (heavy moisture, low pressure)
    -- OVERCAST: humidity > 65 OR light < 30 during daytime (7-19)
    -- MOON:     hour < 7 OR hour >= 19  (night)
    -- SUN:      default daytime
    process(hour_count, loc_idx)
        variable hum : integer range 0 to 100;
        variable bar : integer range 0 to 100;
        variable lgt : integer range 0 to 100;
    begin
        hum := disp_hum;
        bar := disp_bar;
        lgt := disp_lgt;
        if hum > 75 and bar < 40 then
            icon_sel <= 2;  -- RAIN
        elsif hum > 65 or (lgt < 30 and hour_count >= 7 and hour_count < 19) then
            icon_sel <= 3;  -- OVERCAST
        elsif hour_count < 7 or hour_count >= 19 then
            icon_sel <= 1;  -- MOON
        else
            icon_sel <= 0;  -- SUN
        end if;
    end process;

    -- Icon pixel RGB lookup
    process(icon_sel, icon_rom_addr)
        variable px : std_logic_vector(23 downto 0);
    begin
        case icon_sel is
            when 0 => px := SUN_ROM(icon_rom_addr);
            when 1 => px := MOON_ROM(icon_rom_addr);
            when 2 => px := RAIN_ROM(icon_rom_addr);
            when 3 => px := OVERCAST_ROM(icon_rom_addr);
            when others => px := x"333336";
        end case;
        icon_pixel_r <= px(23 downto 16);
        icon_pixel_g <= px(15 downto 8);
        icon_pixel_b <= px(7  downto 0);
    end process;

    -- Temp display digits from per-location constant
    temp_disp_h <= disp_tmp / 100;
    temp_disp_l <= (disp_tmp / 10) mod 10;
    temp_disp_f <= disp_tmp mod 10;


    in_header <= '1' when v_count<HEADER_H else '0';

    -- -------------------------------------------------------
    -- Header font rendering
    -- -------------------------------------------------------
    process(h_count, v_count, loc_idx, hour_count, min_count, header_len, header_txt)
        variable px          : integer range 0 to 639;
        variable py          : integer range 0 to 51;
        variable cidx        : integer range 0 to 23;
        variable loc_len     : integer range 1 to 24;
        variable loc_start_x : integer range 0 to 639;
        variable trel        : integer range 0 to 191;
    begin
        hdr_ascii   <= 32;
        hdr_glyph_x <= 0;
        hdr_glyph_y <= 0;
        px := h_count; py := v_count;
        -- Use header_len so title position is stable in demo/sensor modes
        loc_len     := header_len;
        loc_start_x := LOC_RIGHT - loc_len * CHAR_W;

        -- ROW0: time + date
        if py >= ROW0_Y and py < ROW0_Y+CHAR_H then
            hdr_glyph_y <= py - ROW0_Y;
            if px >= TIME_X and px < TIME_X+5*CHAR_W then
                case (px-TIME_X)/CHAR_W is
                    when 0 => hdr_ascii<=48+hour_count/10;
                    when 1 => hdr_ascii<=48+hour_count mod 10;
                    when 2 => hdr_ascii<=58;
                    when 3 => hdr_ascii<=48+min_count/10;
                    when 4 => hdr_ascii<=48+min_count mod 10;
                    when others => hdr_ascii<=32;
                end case;
                hdr_glyph_x <= (px-TIME_X) mod CHAR_W;
            elsif px>=DATE_X and px<DATE_X+DATE_CHARS*CHAR_W then
                case (px-DATE_X)/CHAR_W is
                    when 0=>hdr_ascii<=48+0; when 1=>hdr_ascii<=48+4;
                    when 2=>hdr_ascii<=46;
                    when 3=>hdr_ascii<=48+2; when 4=>hdr_ascii<=48+1;
                    when 5=>hdr_ascii<=46;
                    when 6=>hdr_ascii<=48+2; when 7=>hdr_ascii<=48+0;
                    when 8=>hdr_ascii<=48+2; when 9=>hdr_ascii<=48+6;
                    when others=>hdr_ascii<=32;
                end case;
                hdr_glyph_x <= (px-DATE_X) mod CHAR_W;
            end if;

        -- ROW1: title (12px wide glyphs) + location
        elsif py >= TITLE_Y and py < TITLE_Y+CHAR_H then
            hdr_glyph_y <= py - TITLE_Y;
            if px >= TITLE_X and px < TITLE_X+TITLE_PX_W then
                trel  := px - TITLE_X;
                cidx  := trel / TITLE_GLYPH_W;
                hdr_ascii   <= TITLE_STR(cidx);
                -- scale 8px glyph into 12px: map pixel to glyph bit
                -- 12px -> 8px: multiply by 8 div 12 = *2/3
                hdr_glyph_x <= (trel mod TITLE_GLYPH_W) * 8 / TITLE_GLYPH_W;
            elsif px>=loc_start_x and px<LOC_RIGHT then
                cidx := (px-loc_start_x)/CHAR_W;
                if cidx < header_len then hdr_ascii <= header_txt(cidx); end if;
                hdr_glyph_x <= (px-loc_start_x) mod CHAR_W;
            end if;
        end if;
    end process;

    hdr_font_idx <= hdr_ascii-32 when hdr_ascii>=32 else 0;
    hdr_font_row <= FONT_ROM(hdr_font_idx, hdr_glyph_y);
    hdr_pixel    <= hdr_font_row(7-hdr_glyph_x);

    -- -------------------------------------------------------
    -- Info text box
    -- -------------------------------------------------------
    in_info <= '1' when
        h_count>=INFO_X1 and h_count<INFO_X2 and
        v_count>=INFO_Y1 and v_count<INFO_Y2 else '0';

    process(h_count, v_count, loc_idx, in_info, sw)
        variable tx      : integer range 0 to 639;
        variable ty      : integer range 0 to 479;
        variable col     : integer range 0 to 33;
        variable row     : integer range 0 to 7;
        variable gx      : integer range 0 to 7;
        variable gy      : integer range 0 to 15;
        variable fidx    : integer range 0 to 127;
        variable frow    : std_logic_vector(7 downto 0);
        variable asc     : integer range 0 to 127;
        variable info_li : integer range 0 to 5;
    begin
        info_pixel <= '0';
        info_ascii <= 32;
        -- In demo mode lock description to location 0 (no cycling text)
        if sw(5) = '1' then info_li := 0; else info_li := loc_idx; end if;
        if in_info='1' then
            tx := h_count - (INFO_X1+INFO_PAD);
            ty := v_count - (INFO_Y1+INFO_PAD);
            if tx < DESC_COLS*CHAR_W and ty < DESC_ROWS*CHAR_H then
                col  := tx / CHAR_W;
                row  := ty / CHAR_H;
                gx   := tx mod CHAR_W;
                gy   := ty mod CHAR_H;
					 if row <= 5 then
							 asc := DESC(info_li)(row)(col);
					 elsif row = 6 then
							 asc := HIKE_LABEL(col);
					 else
							 case hike_demo_status is
								  when "00"   => asc := HIKE_YES(col);
								  when "01"   => asc := HIKE_MAYBE(col);
								  when others => asc := HIKE_NO(col);
							 end case;
					 end if;
                info_ascii <= asc;
                fidx := asc - 32;
                frow := FONT_ROM(fidx, gy);
                info_pixel <= frow(7-gx);
            end if;
        end if;
    end process;

    -- -------------------------------------------------------
    -- Circle detection (true circle: dx^2+dy^2 <= r^2)
    -- -------------------------------------------------------
    process(h_count, v_count)
        variable dx : integer range 0 to 319;
        variable dy : integer range 0 to 239;
    begin
        in_circle <= '0';
        if v_count>=CIRC_CY-CIRC_R and v_count<=CIRC_CY+CIRC_R then
            if v_count >= CIRC_CY then dy := v_count-CIRC_CY;
            else                        dy := CIRC_CY-v_count; end if;
            if h_count>=CIRC_CX-CIRC_R and h_count<=CIRC_CX+CIRC_R then
                if h_count >= CIRC_CX then dx := h_count-CIRC_CX;
                else                        dx := CIRC_CX-h_count; end if;
                if dx*dx+dy*dy <= CIRC_R*CIRC_R then
                    in_circle <= '1';
                end if;
            end if;
        end if;
    end process;

    -- -------------------------------------------------------
    -- Temp box + text
    -- -------------------------------------------------------
    in_temp_box <= '1' when
        h_count>=TEMP_X1 and h_count<TEMP_X2 and
        v_count>=TEMP_Y1 and v_count<TEMP_Y2 else '0';

    process(h_count, v_count, in_temp_box, temp_disp_h, temp_disp_l, temp_disp_f)
        variable tx   : integer range 0 to 63;
        variable ty   : integer range 0 to 23;
        variable gx   : integer range 0 to 7;
        variable gy   : integer range 0 to 15;
        variable cidx : integer range 0 to 5;
        variable asc  : integer range 0 to 127;
        variable fidx : integer range 0 to 127;
        variable frow : std_logic_vector(7 downto 0);
        -- box 64px wide, text 48px, h-offset=8; box 24px tall, text 16px, v-offset=4
        constant H_OFF : integer := 8;
        constant V_OFF : integer := 4;
    begin
        temp_pixel <= '0';
        if in_temp_box='1' then
            tx := h_count - TEMP_X1;
            ty := v_count - TEMP_Y1;
            if tx >= H_OFF and tx < H_OFF + 6*CHAR_W and
               ty >= V_OFF and ty < V_OFF + CHAR_H then
                cidx := (tx - H_OFF) / CHAR_W;
                gx   := (tx - H_OFF) mod CHAR_W;
                gy   := ty - V_OFF;
                case cidx is
                    when 0 => asc := 48 + temp_disp_h;
                    when 1 => asc := 48 + temp_disp_l;
                    when 2 => asc := 46;   -- '.'
                    when 3 => asc := 48 + temp_disp_f;
                    when 4 => asc := 3;    -- degree symbol
                    when 5 => asc := 67;   -- 'C'
                    when others => asc := 32;
                end case;
                if asc >= 32 then fidx := asc - 32; else fidx := asc; end if;
                frow := FONT_ROM(fidx, gy);
                temp_pixel <= frow(7 - gx);
            end if;
        end if;
    end process;

    -- -------------------------------------------------------
    -- Bar / LED / label detection
    -- -------------------------------------------------------
    process(h_count, v_count)
        variable cx : integer range 0 to 639;
        variable dx : integer range 0 to 319;
        variable dy : integer range 0 to 239;
    begin
        in_any_bar<='0'; which_bar<=0; bar_py<=0;
        in_led<='0'; in_label<='0';
        cx := h_count;
        if cx>=BAR0_X and cx<BAR0_X+BAR_W then
            which_bar<=0;
            if v_count>=BAR_TOP and v_count<BAR_BOT then in_any_bar<='1'; bar_py<=v_count-BAR_TOP; end if;
        elsif cx>=BAR1_X and cx<BAR1_X+BAR_W then
            which_bar<=1;
            if v_count>=BAR_TOP and v_count<BAR_BOT then in_any_bar<='1'; bar_py<=v_count-BAR_TOP; end if;
        elsif cx>=BAR2_X and cx<BAR2_X+BAR_W then
            which_bar<=2;
            if v_count>=BAR_TOP and v_count<BAR_BOT then in_any_bar<='1'; bar_py<=v_count-BAR_TOP; end if;
        elsif cx>=BAR3_X and cx<BAR3_X+BAR_W then
            which_bar<=3;
            if v_count>=BAR_TOP and v_count<BAR_BOT then in_any_bar<='1'; bar_py<=v_count-BAR_TOP; end if;
        end if;

        -- True circle LEDs: dx^2 + dy^2 <= r^2
        if v_count>=LED_CY-LED_RY and v_count<=LED_CY+LED_RY then
            if v_count>=LED_CY then dy:=v_count-LED_CY; else dy:=LED_CY-v_count; end if;
            if cx>=BAR0_X+BAR_W/2-LED_RX and cx<=BAR0_X+BAR_W/2+LED_RX then
                if cx>=BAR0_X+BAR_W/2 then dx:=cx-(BAR0_X+BAR_W/2); else dx:=(BAR0_X+BAR_W/2)-cx; end if;
                if dx*dx+dy*dy<=LED_RX*LED_RX then in_led<='1'; which_bar<=0; end if;
            elsif cx>=BAR1_X+BAR_W/2-LED_RX and cx<=BAR1_X+BAR_W/2+LED_RX then
                if cx>=BAR1_X+BAR_W/2 then dx:=cx-(BAR1_X+BAR_W/2); else dx:=(BAR1_X+BAR_W/2)-cx; end if;
                if dx*dx+dy*dy<=LED_RX*LED_RX then in_led<='1'; which_bar<=1; end if;
            elsif cx>=BAR2_X+BAR_W/2-LED_RX and cx<=BAR2_X+BAR_W/2+LED_RX then
                if cx>=BAR2_X+BAR_W/2 then dx:=cx-(BAR2_X+BAR_W/2); else dx:=(BAR2_X+BAR_W/2)-cx; end if;
                if dx*dx+dy*dy<=LED_RX*LED_RX then in_led<='1'; which_bar<=2; end if;
            elsif cx>=BAR3_X+BAR_W/2-LED_RX and cx<=BAR3_X+BAR_W/2+LED_RX then
                if cx>=BAR3_X+BAR_W/2 then dx:=cx-(BAR3_X+BAR_W/2); else dx:=(BAR3_X+BAR_W/2)-cx; end if;
                if dx*dx+dy*dy<=LED_RX*LED_RX then in_led<='1'; which_bar<=3; end if;
            end if;
        end if;

        if v_count>=LABEL_Y and v_count<LABEL_Y+CHAR_H then in_label<='1'; end if;
    end process;

    process(which_bar, loc_idx)
    begin
        case which_bar is
            when 0=>bar_fill_h<=disp_lgt*BAR_H/100;
            when 1=>bar_fill_h<=disp_hum*BAR_H/100;
            when 2=>bar_fill_h<=disp_bar*BAR_H/100;
            when 3=>bar_fill_h<=disp_aqi*BAR_H/100;
            when others=>bar_fill_h<=0;
        end case;
    end process;
    bar_fill_y <= BAR_H - bar_fill_h;

    process(which_bar,lgt_led,hum_led,bar_led,aqi_led)
    begin
        case which_bar is
            when 0=>led_status<=lgt_led;
            when 1=>led_status<=hum_led;
            when 2=>led_status<=bar_led;
            when 3=>led_status<=aqi_led;
            when others=>led_status<="00";
        end case;
    end process;

    -- Label pixel renderer (spaced)
    process(h_count,v_count,which_bar,in_label)
        variable cx     : integer range 0 to 639;
        variable bar_cx : integer range 0 to 639;
        variable lx     : integer range 0 to 639;
        variable lrel   : integer range 0 to 39;
        variable chi    : integer range 0 to 2;
        variable cpx    : integer range 0 to 9;
        variable fidx   : integer range 0 to 127;
        variable frow   : std_logic_vector(7 downto 0);
        variable gy     : integer range 0 to 15;
    begin
        label_pixel<='0';
        cx:=h_count;
        case which_bar is
            when 0=>bar_cx:=BAR0_X; when 1=>bar_cx:=BAR1_X;
            when 2=>bar_cx:=BAR2_X; when 3=>bar_cx:=BAR3_X;
            when others=>bar_cx:=BAR0_X;
        end case;
        lx:=bar_cx+LABEL_OFFSET;
        if in_label='1' and cx>=lx and cx<lx+28 then
            lrel:=cx-lx;
            chi:=lrel/(CHAR_W+LABEL_GAP);
            cpx:=lrel mod(CHAR_W+LABEL_GAP);
            if chi<=2 and cpx<CHAR_W then
                fidx:=BAR_LABELS(which_bar)(chi)-32;
                gy:=v_count-LABEL_Y;
                frow:=FONT_ROM(fidx,gy);
                label_pixel<=frow(7-cpx);
            end if;
        end if;
    end process;

    -- -------------------------------------------------------
    -- Pixel output
    -- -------------------------------------------------------
    process(active,in_header,in_any_bar,in_led,in_label,
            in_info,in_circle,in_temp_box,
            hdr_pixel,info_pixel,temp_pixel,label_pixel,
            bar_py,bar_fill_y,which_bar,led_status,
            icon_pixel_r,icon_pixel_g,icon_pixel_b,
            h_count,v_count)
    begin
        if active='0' then
            vga_r<=x"00";vga_g<=x"00";vga_b<=x"00";

        elsif in_header='1' then
            if hdr_pixel='1' then
                vga_r<=HDR_TXT_R;vga_g<=HDR_TXT_G;vga_b<=HDR_TXT_B;
            else
                vga_r<=HDR_BG_R;vga_g<=HDR_BG_G;vga_b<=HDR_BG_B;
            end if;

        elsif in_info='1' then
            if info_pixel='1' then
                vga_r<=ITXT_R;vga_g<=ITXT_G;vga_b<=ITXT_B;
            else
                vga_r<=LGREY_R;vga_g<=LGREY_G;vga_b<=LGREY_B;
            end if;

        elsif in_circle='1' then
            -- Weather icon 128x128 at 2:1 scale, centred at (530,130)
            if h_count >= 466 and h_count < 594 and
               v_count >= 83  and v_count < 211 then
                vga_r <= icon_pixel_r;
                vga_g <= icon_pixel_g;
                vga_b <= icon_pixel_b;
            else
                vga_r<=LGREY_R;vga_g<=LGREY_G;vga_b<=LGREY_B;
            end if;

        elsif in_temp_box='1' then
            -- Green: 18-26C (180-260), Orange: 10-17.9 or 26.1-33C, Red: <10 or >33C
            if (disp_tmp >= 180 and disp_tmp <= 260) then
                if temp_pixel='1' then
                    vga_r<=x"1A";vga_g<=x"3A";vga_b<=x"1A";  -- dark green text
                else
                    vga_r<=x"7C";vga_g<=x"D4";vga_b<=x"6F";  -- fresh green box
                end if;
            elsif (disp_tmp >= 100 and disp_tmp <= 330) then
                if temp_pixel='1' then
                    vga_r<=x"3A";vga_g<=x"20";vga_b<=x"00";  -- dark text on orange
                else
                    vga_r<=x"FF";vga_g<=x"A8";vga_b<=x"30";  -- amber/orange box
                end if;
            else
                if temp_pixel='1' then
                    vga_r<=x"FF";vga_g<=x"FF";vga_b<=x"FF";  -- white text on red
                else
                    vga_r<=x"CC";vga_g<=x"2A";vga_b<=x"2A";  -- red box
                end if;
            end if;

        elsif in_any_bar='1' then
            if bar_py>=bar_fill_y then
                case which_bar is
                    when 0=>vga_r<=x"F5";vga_g<=x"E6";vga_b<=x"7A"; -- soft yellow LGT
                    when 1=>vga_r<=x"90";vga_g<=x"EE";vga_b<=x"90"; -- green HUM
                    when 2=>vga_r<=x"90";vga_g<=x"B8";vga_b<=x"EE"; -- blue BAR
                    when 3=>vga_r<=x"EE";vga_g<=x"90";vga_b<=x"90"; -- red AQI
                    when others=>vga_r<=x"FF";vga_g<=x"FF";vga_b<=x"FF";
                end case;
            else
                vga_r<=TRACK_R;vga_g<=TRACK_G;vga_b<=TRACK_B;
            end if;

        elsif in_led='1' then
            case led_status is
                when "00"  =>vga_r<=x"00";vga_g<=x"DD";vga_b<=x"44";
                when "01"  =>vga_r<=x"FF";vga_g<=x"88";vga_b<=x"00";
                when others=>vga_r<=x"EE";vga_g<=x"22";vga_b<=x"22";
            end case;

        elsif in_label='1' then
            if label_pixel='1' then
                vga_r<=x"FF";vga_g<=x"FF";vga_b<=x"FF";
            else
                vga_r<=BODY_R;vga_g<=BODY_G;vga_b<=BODY_B;
            end if;

        else
            vga_r<=BODY_R;vga_g<=BODY_G;vga_b<=BODY_B;
        end if;
    end process;

end architecture rtl;
