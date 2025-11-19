Hummingbirdv2 E203 Core and SoC 
===============================
//////////////////////////////////////////////////////////////////////////////////

rtl/e203/perips/lenet_accel_icb.v ：寄存器读写，向计算核发 start 信号、接收 done 信号

rtl\e203\subsys\e203_subsys_perips.v： 修改了Example-AXI模块换成Lenet ，信号模块约在七百多行，未修改，保留 ICB 总线到 O14 的映射；后面修改了模块实例，改为了lenet_accel_icb u_lenet_accel_icb，约一千八百行

（未验证）

SoC 结构变成：CPU 访问 0x1004_1000 这段地址 →ICB fabric 把请求送到 O14 → O14 的 ICB 信号接到 lenet_accel_icb →lenet_accel_icb 里：把写寄存器的命令记在内部寄存器里（IMG/WGT/OUT/CTRL）当 CTRL[0] 被写 1 → 发出一个 accel_start 脉冲、把 busy=1看到 accel_done（现在我们先 Tie = 1）→ 把 done=1, busy=0

在sdk的 lenet_accel.h 访问同一地址，写寄存器 → 启动读 STATUS → 看到 DONE 位置 1

//////////////////////////////////////////////////////////////////////////////////



[![Deploy Documentation](https://github.com/riscv-mcu/e203_hbirdv2/workflows/Deploy%20Documentation/badge.svg)](https://doc.nucleisys.com/hbirdv2)

> [!NOTE]
> **Hummingbird E603** is now available —— a 64-bit RISC-V core you can
freely use for academic and non-commercial projects.  
> Explore it here: [Nuclei-Software/e603_hbird](https://github.com/Nuclei-Software/e603_hbird)

About
-----

This repository hosts the project for open-source Hummingbirdv2 E203 RISC-V processor Core and SoC, it's developped and opensourced by [Nuclei System Technology](www.nucleisys.com), the leading RISC-V IP and Solution company based on China Mainland.

This's an upgraded version of the project Hummingbird E203 maintained in [SI-RISCV/e200_opensource](https://github.com/SI-RISCV/e200_opensource), so we call it Hummingbirdv2 E203, and its architecture is shown in the figure below.
![hbirdv2](pics/hbirdv2_soc.JPG)


In this new version, we have following updates.
* Add NICE(Nuclei Instruction Co-unit Extension) for E203 core, so user could create customized HW co-units with E203 core easily.
* Integrate the APB interface peripherals(GPIO, I2C, UART, SPI, PWM) from [PULP Platform](https://github.com/pulp-platform) into Hummingbirdv2 SoC, these peripherals are implemented in Verilog language, so it's easy for user to understand. 
* Add new development boards(Nuclei ddr200t and mcu200t) support for Hummingbirdv2 SoC. 

**Welcome to visit https://github.com/riscv-mcu/hbird-sdk/ to use software development kit for the Hummingbird E203.**

**Welcome to visit https://www.rvmcu.com/community.html to participate in the discussion of the Hummingbird E203.**

**Welcome to visit http://www.rvmcu.com/ for more comprehensive information of availiable RISC-V MCU chips and embedded development.**


Detailed Introduction and Quick Start-up
----------------------------------------

We have provided very detailed introduction and quick start-up documents to help you ramping it up. 

The detailed introduction and the quick start documentation can be seen 
from https://doc.nucleisys.com/hbirdv2/.

By following the guidences from the doc, you can very easily start to use Hummingbirdv2 E203 processor Core and SoC.

What are you waiting for? Try it out now!

Dedicated FPGA-Boards and JTAG-Debugger 
---------------------------------------

In order to easy user to study RISC-V in a quick and easy way, we have made dedicated FPGA-Boards and JTAG-Debugger.

#### Nuclei ddr200t development board

<img src="pics/DDR200T.JPG" width= 80% alt="DDR200T"/>

#### Nuclei mcu200t development board

<img src="pics/MCU200T.JPG" width= 80% alt="MCU200T"/>

#### Hummingbird Debugger

![Debugger](pics/debugger.JPG)

The detailed introduction and the relevant documentation can be seen from https://nucleisys.com/developboard.php.

HummingBird SDK
---------------

Click https://github.com/riscv-mcu/hbird-sdk for software development kit.

WeChat Group
------------

If you would like to join our WeChat group for discussion and support,
please scan the following QR code:

![wechat QR code](./pics/QR_code.png)

Release History
---------------

#### Notice

* **Many people asked if this core and SoC can be commercially used, the answer as below:**
  - According to the Apache 2.0 license, this open-sourced core can be used in commercial way.
  - But the feature is not full. 
  - The main purpose of this open-sourced core is to be used by students/university/research/
    and entry-level-beginners, hence, the commercial quality (bug-free) and service of this core
    is not not not warranted!!! 

#### Release 0.2.1, Feb 26, 2021

This is `release 0.2.1` of Hummingbirdv2.

+ Hbirdv2 SoC
  - Covert the peripheral IPs implemented in system verilog to verilog implementation.

+ SIM
  - Add new simulation tool(iVerilog) and wave viewer(GTKWave) support for Hummingbirdv2 SoC

#### Release 0.1.2, Nov 20, 2020

This is `release 0.1.2` of Hummingbirdv2.

+ Hbirdv2 SoC
  - Remove unused module
  - Add one more UART

+ FPGA
  - Add new development board(Nuclei mcu200t) support for Hummingbirdv2 SoC
 
#### Release 0.1.1, Jul 28, 2020

This is `release 0.1.1` of Hummingbirdv2.

NOTE:
  + This's an upgraded version of the project Hummingbird E203 maintained in
    [SI-RISCV/e200_opensource](https://github.com/SI-RISCV/e200_opensource).
  + Here are the new features of this release.
    - Add NICE(Nuclei Instruction Co-unit Extension) for E203 core
    - Integrate the APB interface peripherals(GPIO, I2C, UART, SPI, PWM) from PULP Platform
    - Add new development board(Nuclei ddr200t) support for Hummingbirdv2 SoC. 
