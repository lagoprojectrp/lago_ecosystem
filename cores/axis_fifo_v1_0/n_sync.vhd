library ieee;
use ieee.std_logic_1164.all;

entity n_sync is
  generic(
           N : natural
         );
  port(
        clk      : in std_logic;
        reset    : in std_logic;
        in_async : in std_logic_vector(N-1 downto 0);
        out_sync : out std_logic_vector(N-1 downto 0)
      );
end n_sync;

architecture two_ff_arch of n_sync is
  signal meta_reg, sync_reg  : std_logic_vector(N-1 downto 0);
  signal meta_next, sync_next: std_logic_vector(N-1 downto 0);
begin

  -- two registers
  process(clk)
  begin
    if rising_edge(clk) then
      if (reset='0') then
        meta_reg <= (others=>'0');
        sync_reg <= (others=>'0');
      else
        meta_reg <= meta_next;
        sync_reg <= sync_next;
      end if;
    end if;
  end process;

  -- next-state logic
  meta_next <= in_async;
  sync_next <= meta_reg;
  -- output
  out_sync <= sync_reg;

end two_ff_arch;
