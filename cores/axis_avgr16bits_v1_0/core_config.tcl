set display_name {AXI4-Stream Averager 16 bits v1.0}

set core [ipx::current_core]

set_property DISPLAY_NAME $display_name $core
set_property DESCRIPTION $display_name $core

core_parameter S_AXIS_DWIDTH {S_AXIS TDATA WIDTH} {Width of the S_AXIS data bus.}
core_parameter M_AXIS_DWIDTH {M_AXIS TDATA WIDTH} {Width of the M_AXI data bus.}
core_parameter ADC_DWIDTH {ADC DATA WIDTH} {Width of the ADC data.}
core_parameter MEM_AWIDTH {MEMORY ADDR WIDTH} {Address width of the data memory.}
core_parameter MEM_DEPTH {MEMORY DEPTH} {Depth of the data memory.}

set bus [ipx::get_bus_interfaces -of_objects $core s_axis]
set_property NAME S_AXIS $bus
set_property INTERFACE_MODE slave $bus

set bus [ipx::get_bus_interfaces s_axis_aclk]
set parameter [ipx::get_bus_parameters -of_objects $bus ASSOCIATED_BUSIF]
set_property VALUE S_AXIS $parameter

set bus [ipx::get_bus_interfaces -of_objects $core m_axis]
set_property NAME M_AXIS $bus
set_property INTERFACE_MODE master $bus

set bus [ipx::get_bus_interfaces m_axis_aclk]
set parameter [ipx::get_bus_parameters -of_objects $bus ASSOCIATED_BUSIF]
set_property VALUE M_AXIS $parameter

