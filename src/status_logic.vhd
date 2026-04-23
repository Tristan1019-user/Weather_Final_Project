library ieee;
use ieee.std_logic_1164.all;

entity status_logic is
    port (
        temp_x10     : in  integer range 0 to 999;
        humid_x10    : in  integer range 0 to 1000;
        press_hpa    : in  integer range 300 to 1200;
        pm25_x10     : in  integer range 0 to 2000;
        temp_status  : out std_logic_vector(1 downto 0);
        humid_status : out std_logic_vector(1 downto 0);
        press_status : out std_logic_vector(1 downto 0);
        pm_status    : out std_logic_vector(1 downto 0)
    );
end entity;

architecture rtl of status_logic is
begin
    process (temp_x10, humid_x10, press_hpa, pm25_x10)
    begin
        if temp_x10 < 180 then
            temp_status <= "01";
        elsif temp_x10 <= 280 then
            temp_status <= "00";
        else
            temp_status <= "10";
        end if;

        if humid_x10 < 300 then
            humid_status <= "01";
        elsif humid_x10 <= 650 then
            humid_status <= "00";
        else
            humid_status <= "10";
        end if;

        if press_hpa < 990 then
            press_status <= "10";
        elsif press_hpa <= 1025 then
            press_status <= "00";
        else
            press_status <= "01";
        end if;

        if pm25_x10 < 120 then
            pm_status <= "00";
        elsif pm25_x10 < 350 then
            pm_status <= "01";
        else
            pm_status <= "10";
        end if;
    end process;
end architecture;

