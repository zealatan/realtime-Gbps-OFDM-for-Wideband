################################################################################
# Automatically-generated file. Do not edit!
################################################################################

-include ../makefile.init

RM := rm -rf

# All of the sources participating in the build are defined here
-include sources.mk
-include src/subdir.mk
-include subdir.mk
-include objects.mk

ifneq ($(MAKECMDGOALS),clean)
ifneq ($(strip $(S_UPPER_DEPS)),)
-include $(S_UPPER_DEPS)
endif
ifneq ($(strip $(C_DEPS)),)
-include $(C_DEPS)
endif
endif

-include ../makefile.defs

# Add inputs and outputs from these tool invocations to the build variables 
ELFSIZE += \
rfdc_capture.elf.size \


# All Target
all: rfdc_capture.elf secondary-outputs

# Tool invocations
rfdc_capture.elf: $(OBJS) ../src/lscript.ld $(USER_OBJS)
	@echo 'Building target: $@'
	@echo 'Invoking: ARM v8 gcc linker'
	aarch64-none-elf-gcc -Wl,-T -Wl,../src/lscript.ld -L/home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/software/generated/rfdc_capture_ws/zcu216_rfdc_capture/export/zcu216_rfdc_capture/sw/zcu216_rfdc_capture/standalone_domain/bsplib/lib -o "rfdc_capture.elf" $(OBJS) $(USER_OBJS) $(LIBS)
	@echo 'Finished building target: $@'
	@echo ' '

rfdc_capture.elf.size: rfdc_capture.elf
	@echo 'Invoking: ARM v8 Print Size'
	aarch64-none-elf-size rfdc_capture.elf  |tee "rfdc_capture.elf.size"
	@echo 'Finished building: $@'
	@echo ' '

# Other Targets
clean:
	-$(RM) $(EXECUTABLES)$(OBJS)$(S_UPPER_DEPS)$(C_DEPS)$(ELFSIZE) rfdc_capture.elf
	-@echo ' '

secondary-outputs: $(ELFSIZE)

.PHONY: all clean dependents

-include ../makefile.targets
