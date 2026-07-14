################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
LD_SRCS += \
../src/lscript.ld 

C_SRCS += \
../src/main.c \
../src/xrfclk.c 

OBJS += \
./src/main.o \
./src/xrfclk.o 

C_DEPS += \
./src/main.d \
./src/xrfclk.d 


# Each subdirectory must supply rules for building sources it contributes
src/%.o: ../src/%.c
	@echo 'Building file: $<'
	@echo 'Invoking: ARM v8 gcc compiler'
	aarch64-none-elf-gcc -Wall -O0 -g3 -c -fmessage-length=0 -MT"$@" -D __BAREMETAL__ -I/home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/software/generated/rfdc_capture_ws/zcu216_rfdc_capture/export/zcu216_rfdc_capture/sw/zcu216_rfdc_capture/standalone_domain/bspinclude/include -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -o "$@" "$<"
	@echo 'Finished building: $<'
	@echo ' '


