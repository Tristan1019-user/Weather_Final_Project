library ieee;
use ieee.std_logic_1164.all;

entity hex7seg is
    port (
        value : in  integer range 0 to 9;
        seg   : out std_logic_vector(6 downto 0)
    );
end entity;

architecture rtl of hex7seg is
begin
    process (value)
    begin
        case value is
            when 0 => seg <= "1000000";
            when 1 => seg <= "1111001";
            when 2 => seg <= "0100100";
            when 3 => seg <= "0110000";
            when 4 => seg <= "0011001";
            when 5 => seg <= "0010010";
            when 6 => seg <= "0000010";
            when 7 => seg <= "1111000";
            when 8 => seg <= "0000000";
            when 9 => seg <= "0010000";
            when others => seg <= "1111111";
        end case;
    end process;
end architecture;

