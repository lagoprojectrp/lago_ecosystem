source projects/base_system/block_design.tcl

#Enable interrupts
set_property -dict [list CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1}] [get_bd_cells ps_0]

# Create xlconstant
cell xilinx.com:ip:xlconstant const_0

# Create proc_sys_reset
cell xilinx.com:ip:proc_sys_reset rst_0 {} {
  ext_reset_in const_0/dout
}

# Create axis_rp_adc
cell labdpr:user:axis_rp_adc adc_0 {
  ADC_DATA_WIDTH 14
} {
  aclk pll_0/clk_out1
  adc_dat_a adc_dat_a_i
  adc_dat_b adc_dat_b_i
  adc_csn adc_csn_o
}

# Create c_counter_binary
cell xilinx.com:ip:c_counter_binary cntr_0 {
  Output_Width 32
} {
  CLK pll_0/clk_out1
}

# Create xlslice
cell xilinx.com:ip:xlslice slice_0 {
  DIN_WIDTH 32 DIN_FROM 26 DIN_TO 26 DOUT_WIDTH 1
} {
  Din cntr_0/Q
}

# Create GPIO core
cell xilinx.com:ip:axi_gpio axi_gpio_0 {
   C_GPIO_WIDTH 8
  C_GPIO2_WIDTH 1
  C_ALL_OUTPUTS 1
  C_IS_DUAL 1 
  C_ALL_INPUTS 0 
  C_ALL_INPUTS_2 1
  C_INTERRUPT_PRESENT 1 
  C_ALL_OUTPUTS 1
} {
  s_axi_aclk pll_0/clk_out1
  s_axi_aresetn rst_0/peripheral_aresetn
  ip2intc_irpt ps_0/IRQ_F2P
  gpio_io_o led_o
  gpio2_io_i slice_0/Dout
}

addr 0x40000000 4K axi_gpio_0/S_AXI /ps_0/M_AXI_GP0
