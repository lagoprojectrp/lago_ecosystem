library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_lago_trigger is
  generic (
  AXIS_TDATA_WIDTH      : natural  := 32;
  -- data arrays bit numbers
  ADC_DATA_WIDTH        : natural := 14;    
  DATA_ARRAY_LENGTH     : natural := 20;
  METADATA_ARRAY_LENGTH : natural := 10;
  SUBTRIG_ARRAY_LENGTH  : natural := 3
);
port (
  -- System signals
  aclk               : in std_logic;
  aresetn            : in std_logic;
  trig_lvl_a_i       : in std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  trig_lvl_b_i       : in std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  subtrig_lvl_a_i    : in std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  subtrig_lvl_b_i    : in std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  pps_i              : in std_logic;
  clk_cnt_pps_i      : in std_logic_vector(27-1 downto 0);
  temp_i             : in std_logic_vector(24-1 downto 0);
  pressure_i         : in std_logic_vector(24-1 downto 0);
  time_i             : in std_logic_vector(24-1 downto 0);
  date_i             : in std_logic_vector(24-1 downto 0);
  latitude_i         : in std_logic_vector(24-1 downto 0);
  longitude_i        : in std_logic_vector(24-1 downto 0);
  altitude_i         : in std_logic_vector(24-1 downto 0);
  satellites_i       : in std_logic_vector(24-1 downto 0);

  -- Slave side
  s_axis_tready     : out std_logic;
  s_axis_tdata      : in std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  s_axis_tvalid     : in std_logic;

  -- Master side
  m_axis_tready     : in std_logic;
  m_axis_tdata      : out std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  m_axis_tvalid     : out std_logic
);
end axis_lago_trigger;

architecture rtl of axis_lago_trigger is

  constant PADDING_WIDTH : natural := AXIS_TDATA_WIDTH/2 - ADC_DATA_WIDTH;

  --ADC related signals
  type  adc_data_array_t is array (DATA_ARRAY_LENGTH-1 downto 0) 
  of std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  signal array_adc1_reg, array_adc1_next : adc_data_array_t;
  signal array_adc2_reg, array_adc2_next : adc_data_array_t;

  type array_mtd_t is array (METADATA_ARRAY_LENGTH-1 downto 0) 
  of std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal array_mtd_reg, array_mtd_next : array_mtd_t;

  type array_scalers_t is array (SUBTRIG_ARRAY_LENGTH-1 downto 0) 
  of std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal array_scalers_reg, array_scalers_next : array_scalers_t;

  --Trigger related signals
  --Triggers
  signal tr1_s, tr2_s, tr_s              : std_logic; 
  --Sub-Triggers
  signal subtr1_s, subtr2_s, subtr_s     : std_logic; 

  signal tr_status_reg, tr_status_next   : std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal cnt_status_reg, cnt_status_next : std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);

  signal trig_cnt_reg, trig_cnt_next     : std_logic_vector(30-1 downto 0); 

  --Charge signals
  signal charge1_reg, charge1_next       : unsigned(ADC_DATA_WIDTH-1 downto 0);
  signal charge2_reg, charge2_next       : unsigned(ADC_DATA_WIDTH-1 downto 0);

  --FSM signals
  type state_t is (ST_IDLE,
                      ST_ATT_TR,
                      ST_SEND_TR_STATUS,
                      ST_SEND_CNT_STATUS,
                      ST_ATT_SUBTR,
                      ST_ATT_PPS);
  signal state_reg, state_next: state_t;

  signal wr_count_reg, wr_count_next : unsigned(7 downto 0);
  signal data_to_fifo_reg, data_to_fifo_next : std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal status : std_logic_vector(2 downto 0);

  signal axis_tready_reg, axis_tready_next : std_logic;
  signal axis_tvalid_reg, axis_tvalid_next : std_logic;

  signal trig_lvl_a, trig_lvl_b       : std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  signal subtrig_lvl_a, subtrig_lvl_b : std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  signal data_adc1_reg, data_adc1_next: std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  signal data_adc2_reg, data_adc2_next: std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);

begin
    
  trig_lvl_a <= ((PADDING_WIDTH-1) downto 0 => trig_lvl_a_i(ADC_DATA_WIDTH-1)) & trig_lvl_a_i(ADC_DATA_WIDTH-1 downto 0);
  trig_lvl_b <= ((PADDING_WIDTH-1) downto 0 => trig_lvl_b_i(ADC_DATA_WIDTH-1)) & trig_lvl_b_i(ADC_DATA_WIDTH-1 downto 0);

  subtrig_lvl_a <= ((PADDING_WIDTH-1) downto 0 => subtrig_lvl_a_i(ADC_DATA_WIDTH-1)) & subtrig_lvl_a_i(ADC_DATA_WIDTH-1 downto 0);
  subtrig_lvl_b <= ((PADDING_WIDTH-1) downto 0 => subtrig_lvl_b_i(ADC_DATA_WIDTH-1)) & subtrig_lvl_b_i(ADC_DATA_WIDTH-1 downto 0);

  data_adc1_next <= ((PADDING_WIDTH-1) downto 0 => s_axis_tdata(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1)) & s_axis_tdata(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1 downto 0) when (s_axis_tvalid = '1') and (axis_tready_reg = '1') else 
                    data_adc1_reg;
  data_adc2_next <= ((PADDING_WIDTH-1) downto 0 => s_axis_tdata(AXIS_TDATA_WIDTH-PADDING_WIDTH-1)) & s_axis_tdata(AXIS_TDATA_WIDTH-PADDING_WIDTH-1 downto AXIS_TDATA_WIDTH/2) when (s_axis_tvalid = '1') and (axis_tready_reg = '1') else
                    data_adc2_reg;

  process(aclk)
  begin
    if (rising_edge(aclk)) then
      if (aresetn = '0') then
        data_adc1_reg <= (others => '0');
        data_adc2_reg <= (others => '0');
      else
        data_adc1_reg <= data_adc1_next;
        data_adc2_reg <= data_adc2_next;
      end if;
    end if;
  end process;
 
  -- data registers for a second
  process(aclk)
  begin
    for i in METADATA_ARRAY_LENGTH-1 downto 0 loop
      if (rising_edge(aclk)) then
      if (aresetn = '0') then
        array_mtd_reg(i) <= (others => '0');
      else
        array_mtd_reg(i) <= array_mtd_next(i);
      end if;
      end if;
    end loop;
  end process;
  --next state logic
  array_mtd_next(METADATA_ARRAY_LENGTH-10)<= x"FFFFFFFF"                              when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-10);
  array_mtd_next(METADATA_ARRAY_LENGTH-9)<= "11" & "000" & clk_cnt_pps_i              when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-9);
  array_mtd_next(METADATA_ARRAY_LENGTH-8)<= "11" & "001" & "000" &  temp_i            when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-8);
  array_mtd_next(METADATA_ARRAY_LENGTH-7)<= "11" & "010" & "000" &  pressure_i        when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-7);
  array_mtd_next(METADATA_ARRAY_LENGTH-6)<= "11" & "011" & "000" &  time_i            when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-6);
  array_mtd_next(METADATA_ARRAY_LENGTH-5)<= "11" & "100" & "000" &  latitude_i        when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-5);
  array_mtd_next(METADATA_ARRAY_LENGTH-4)<= "11" & "100" & "001" &  longitude_i       when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-4);
  array_mtd_next(METADATA_ARRAY_LENGTH-3)<= "11" & "100" & "010" &  altitude_i        when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-3);
  array_mtd_next(METADATA_ARRAY_LENGTH-2)<= "11" & "100" & "011" &  date_i            when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-2);
  array_mtd_next(METADATA_ARRAY_LENGTH-1)<= "11" & "100" & "100" &  satellites_i      when (pps_i = '1') else array_mtd_reg(METADATA_ARRAY_LENGTH-1);

------------------------------------------------------------------------------------------------------
  --data acquisition for each channel
  process(aclk)
  begin
    for i in (DATA_ARRAY_LENGTH-1) downto 0 loop
      if (rising_edge(aclk)) then
      if (aresetn = '0') then
        array_adc1_reg(i) <= (others=>'0');
        array_adc2_reg(i) <= (others=>'0');
      else
        array_adc1_reg(i) <= array_adc1_next(i);
        array_adc2_reg(i) <= array_adc2_next(i);
      end if;
      end if;
      -- next state logic
      if (i = (DATA_ARRAY_LENGTH-1)) then
        if ((s_axis_tvalid = '1') and (axis_tready_reg = '1')) then
        array_adc1_next(i) <= data_adc1_reg;
        array_adc2_next(i) <= data_adc2_reg;
        else
        array_adc1_next(i) <= array_adc1_reg(i); 
        array_adc2_next(i) <= array_adc2_reg(i); 
        end if;
      else
        if ((s_axis_tvalid = '1') and (axis_tready_reg = '1')) then
        array_adc1_next(i) <= array_adc1_reg(i+1);
        array_adc2_next(i) <= array_adc2_reg(i+1);
        else
        array_adc1_next(i) <= array_adc1_reg(i);
        array_adc2_next(i) <= array_adc2_reg(i);
        end if;
      end if;
    end loop;
  end process;

-----------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------------
  --trigger
  process(aclk)
  begin
    if (rising_edge(aclk)) then
    if (aresetn = '0') then
      tr_status_reg  <= (others => '0');
      cnt_status_reg <= (others => '0');
      trig_cnt_reg   <= (others => '0');
    else
      tr_status_reg  <= tr_status_next;
      cnt_status_reg <= cnt_status_next;
      trig_cnt_reg   <= trig_cnt_next;
    end if;
    end if;
  end process;
  

  -- The trigger is at  bin 4 because we loose a clock pulse in the state machine
  -- next state logic
  tr1_s <=  '1' when ((array_adc1_reg(3)(array_adc1_reg(3)'left) = trig_lvl_a(trig_lvl_a'left)) and 
                      (unsigned(array_adc1_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) >= unsigned(trig_lvl_a(AXIS_TDATA_WIDTH/2-2 downto 0))) and
                      (unsigned(array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_a(AXIS_TDATA_WIDTH/2-2 downto 0))) and
                      (unsigned(array_adc1_reg(1)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_a(AXIS_TDATA_WIDTH/2-2 downto 0)))) else
            '0';
  tr2_s <=  '1' when ((array_adc2_reg(3)(array_adc2_reg(3)'left) = trig_lvl_b(trig_lvl_b'left)) and 
                      (unsigned(array_adc2_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) >= unsigned(trig_lvl_b(AXIS_TDATA_WIDTH/2-2 downto 0))) and
                      (unsigned(array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_b(AXIS_TDATA_WIDTH/2-2 downto 0))) and
                      (unsigned(array_adc2_reg(1)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_b(AXIS_TDATA_WIDTH/2-2 downto 0)))) else
            '0';

  tr_s <= '1' when  ((tr1_s = '1') or (tr2_s = '1')) else '0';

  tr_status_next <=   "010" & tr2_s & tr1_s & clk_cnt_pps_i when (tr_s = '1') else
                      tr_status_reg;
  cnt_status_next <=  "10" & trig_cnt_reg when (tr_s = '1') else
                      cnt_status_reg;

  trig_cnt_next <= std_logic_vector(unsigned(trig_cnt_reg) + 1) when (tr_s = '1') else
                   trig_cnt_reg;

----------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------
  --sub-trigger: we test for a sub-trigger and we must not have a trigger in the next two clocks
  process(aclk)
  begin
    if (rising_edge(aclk)) then
    if (aresetn = '0') then
      charge1_reg <= (others => '0');
      charge2_reg <= (others => '0');
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-1) <= (others => '0');
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-2) <= (others => '0');
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-3) <= (others => '0');
    else
      charge1_reg <= charge1_next;
      charge2_reg <= charge2_next;
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-1) <= array_scalers_next(SUBTRIG_ARRAY_LENGTH-1);
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-2) <= array_scalers_next(SUBTRIG_ARRAY_LENGTH-2);
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-3) <= array_scalers_next(SUBTRIG_ARRAY_LENGTH-3);
    end if;
    end if;
  end process;
  -- next state logic
  subtr1_s <= '1' when array_adc1_reg(2)(array_adc1_reg(2)'left) = subtrig_lvl_a(subtrig_lvl_a'left) and 
                      unsigned(array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) >= unsigned(subtrig_lvl_a(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc1_reg(1)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      (unsigned(array_adc1_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) or
                      (unsigned(array_adc1_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) = unsigned(array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc1_reg(4)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)))) and
                      (array_adc1_reg(2)(array_adc1_reg(2)'left) = trig_lvl_a(trig_lvl_a'left)) and 
                      unsigned(array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_a(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc1_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_a(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc1_reg(4)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_a(AXIS_TDATA_WIDTH/2-2 downto 0)) else
                    '0';
  subtr2_s <= '1' when array_adc2_reg(2)(array_adc2_reg(2)'left) = subtrig_lvl_b(subtrig_lvl_b'left) and
                      unsigned(array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) >= unsigned(subtrig_lvl_b(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc2_reg(1)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      (unsigned(array_adc2_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) or
                      (unsigned(array_adc2_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) = unsigned(array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc2_reg(4)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)))) and
                      (array_adc2_reg(2)(array_adc2_reg(2)'left) = trig_lvl_b(trig_lvl_b'left)) and 
                      unsigned(array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_b(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc2_reg(3)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_b(AXIS_TDATA_WIDTH/2-2 downto 0)) and
                      unsigned(array_adc2_reg(4)(AXIS_TDATA_WIDTH/2-2 downto 0)) < unsigned(trig_lvl_b(AXIS_TDATA_WIDTH/2-2 downto 0)) else
                    '0';
  subtr_s <=  '1' when  ((subtr1_s = '1') or (subtr2_s = '1')) else '0';

  charge1_next <= charge1_reg + array_adc1_reg'left - array_adc1_reg'right;
  charge2_next <= charge2_reg + array_adc2_reg'left - array_adc2_reg'right;

  array_scalers_next(SUBTRIG_ARRAY_LENGTH-1) <= "010" & subtr2_s & subtr1_s & clk_cnt_pps_i when (subtr_s = '1') else
                                              array_scalers_reg(SUBTRIG_ARRAY_LENGTH-1);
  array_scalers_next(SUBTRIG_ARRAY_LENGTH-2) <= "0000" & std_logic_vector(charge1_reg) & std_logic_vector(charge2_reg) when (subtr_s = '1') else
                                              array_scalers_reg(SUBTRIG_ARRAY_LENGTH-2); --charge values per channel
  array_scalers_next(SUBTRIG_ARRAY_LENGTH-3) <= "0000" & array_adc1_reg(2)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1 downto 0) & array_adc2_reg(2)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1 downto 0) when (subtr_s = '1') else
                                              array_scalers_reg(SUBTRIG_ARRAY_LENGTH-3); --we send the pulse maximum too

----------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------
  -- FSM controlling all
  --================================================================
  -- state and data registers
  --================================================================
  process (aclk)
  begin
    if (rising_edge(aclk)) then
    if (aresetn = '0') then
      state_reg      <= ST_IDLE;
      wr_count_reg   <= (others => '0');
      data_to_fifo_reg <= (others => '0');
      axis_tvalid_reg <= '0';
      axis_tready_reg <= '0';
    else
      state_reg      <= state_next;
      wr_count_reg   <= wr_count_next;
      data_to_fifo_reg <= data_to_fifo_next;
      axis_tvalid_reg <= axis_tvalid_next;
      axis_tready_reg <= axis_tready_next;
    end if;
    end if;
  end process;
  --=================================================================
  --next-state logic & data path functional units/routing
  --=================================================================
  process(state_reg, status, wr_count_reg)
  begin
    state_next        <= state_reg;         -- default 
    wr_count_next     <= (others => '0'); -- wr_count_reg;
    data_to_fifo_next <= data_to_fifo_reg;  -- default 
    axis_tvalid_next  <= '0';               -- default disable write
    axis_tready_next  <= '0';               -- always ready
    case state_reg is
      when ST_IDLE =>
        axis_tready_next  <= '1';               -- always ready
          case status is
            when "001" | "011" | "101" | "111" => -- priority is for PPS data every second
              state_next <= ST_ATT_PPS;
            when "100" | "110" =>
              state_next <= ST_ATT_TR;
            when "010" =>
              state_next <= ST_ATT_SUBTR;
            when others => --"000"
              state_next <= ST_IDLE;
          end case;

      --we send adc data because we have a trigger
      when ST_ATT_TR =>
        axis_tready_next <= '1';
        axis_tvalid_next <= '1';
        if (m_axis_tready = '1') then
          wr_count_next <= wr_count_reg + 1;
          data_to_fifo_next <= "00" & array_adc2_reg(0)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1) & array_adc2_reg(0)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-2 downto 0) & "00" & array_adc1_reg(0)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1) & array_adc1_reg(0)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-2 downto 0);
          if (wr_count_reg = DATA_ARRAY_LENGTH-1) then
            state_next <= ST_SEND_TR_STATUS;
          else
            state_next <= ST_ATT_TR;
          end if;
        else
          state_next <= ST_ATT_TR;
        end if;

      when ST_SEND_TR_STATUS =>
        axis_tready_next <= '0';
        axis_tvalid_next <= '1';
        if (m_axis_tready = '1') then
          data_to_fifo_next <= tr_status_reg;
          state_next <= ST_SEND_CNT_STATUS;
        else
          state_next <= ST_SEND_TR_STATUS;
        end if;

      when ST_SEND_CNT_STATUS =>
        axis_tready_next <= '0';
        axis_tvalid_next <= '1';
        if (m_axis_tready = '1') then
          data_to_fifo_next <= cnt_status_reg;
          state_next <= ST_IDLE;
        else
          state_next <= ST_SEND_CNT_STATUS;
        end if;

      when ST_ATT_SUBTR =>
        axis_tready_next <= '1';
        axis_tvalid_next <= '1';
        if (m_axis_tready = '1') then
          wr_count_next <= wr_count_reg + 1;
          data_to_fifo_next <= array_scalers_reg(to_integer(wr_count_reg));
          if (wr_count_reg = SUBTRIG_ARRAY_LENGTH-1) then
            state_next <= ST_IDLE;
          else 
            state_next <= ST_ATT_SUBTR;
          end if;
        else
          state_next <= ST_ATT_SUBTR;
        end if;

      when ST_ATT_PPS =>
        axis_tready_next <= '0';
        axis_tvalid_next <= '1';
        if (m_axis_tready = '1') then
          wr_count_next <= wr_count_reg + 1;
          data_to_fifo_next <= array_mtd_reg(to_integer(wr_count_reg));
          if (wr_count_reg = METADATA_ARRAY_LENGTH-1) then
            state_next <= ST_IDLE;
          else
            state_next <= ST_ATT_PPS;
          end if;
        else
          state_next <= ST_ATT_PPS;
        end if;
   end case;
  end process;

  status <= tr_s & subtr_s & pps_i;
  s_axis_tready <= axis_tready_reg;
  m_axis_tdata <= data_to_fifo_reg;
  m_axis_tvalid <= axis_tvalid_reg;

end architecture rtl;

