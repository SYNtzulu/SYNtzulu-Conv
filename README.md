# SYNtzulu-Conv: Enabling Spiking 2D Convolutions for Sensor Data Analysis on Low-Power FPGAs

SYNtzulu-Conv is a Convolutional Spiking Neural Network (SNN) processing core designed to be used in low-cost and low-power FPGA devices, enabling real-time and near-sensor data analysis. The system features a **dual-core neuromorphic processor**, with each core capable of processing four synapses and one neuron per clock cycle. Additionally, it includes a **tiny RISC-V subsystem** (SERV + Servant platform) that manages the input/output operations and configures runtime parameters.  evaluated the system, which was implemented on a **Lattice iCE40UP5K FPGA**, in various use cases employing SNNs with accuracy comparable to the state-of-the-art. 
In its current version, SYNtzulu: 
- Fetches input data via a **12 MHz SPI** interface.
- Transmits inference results through a **2 MHz UART**.
- Dissipates a maximum power of **11 mW** when performing SNN inference while clocked at **24 MHz**, excluding input/output power consumption.
- Consumes as little as **0.2 mW** in **idle** mode.

**Device Utilization**  

| Resource             | Used | Total | Utilization (%) |
|----------------------|------|-------|-----------------|
| ICESTORM_LC          | 4557 | 5280  | 86%             |
| ICESTORM_RAM         | 30   | 30    | 100%            |
| SB_IO                | 15   | 96    | 16%             |
| SB_GB                | 8    | 8     | 100%            |
| ICESTORM_DSP         | 2    | 8     | 25%             |
| ICESTORM_HFOSC       | 1    | 1     | 100%            |
| ICESTORM_LFOSC       | 1    | 1     | 100%            |
| ICESTORM_SPRAM       | 4    | 4     | 100%            |

For further details regarding SYNtzulu-Conv see the related paper available in open access [here]()

# SYNtzulu's flow

To introduce you to SYNtzulu, we have prepared a demo that showcases its capabilities. The demo involves continuous force decoding from 4 8x8 patches of electrode sampling sEMG signal. The biosignal is event-encoded using the delta modulation algorithm and the patches are organised in a 16x16 shape. Consequently, the network has 2x16x16 input channels (each sEMG channel is mapped into two spiking channels) and 5 output channels (one for each finger). The network consists of 2 dense layers, a pooling layer, a convolutional layer, and a final dense layer.

The application, named "emg", is already installed. 
If you wish to create your own application you can go through the four Python Notebook located in the Python folder. As a result, you will obtain a folder named according to your application containing all the hardware configuration file needed to run it in hardware.

## Environment setup
SYNtzulu-Conv has been tested with the oss_cad_suite (version 2023-07-28), which can be downloaded [here](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2023-07-28).
After downloading and extracting the archive, prepare the environment by running the following command:
```
source oss_cad_suite/environment
```
Additionally, a **RISC-V cross-compiler** is required to compile the firmware. If your system does not already include it, execute the following commands or refer to the [riscv-gnu-toolchain page](https://github.com/riscv-collab/riscv-gnu-toolchain)
```
git clone https://github.com/riscv/riscv-gnu-toolchain --recursive
cd riscv-gnu-toolchain/
./configure --prefix=/opt/riscv --with-arch=rv32i --with-abi=ilp32
sudo make
```

## Simulation
Step 1.
If you have created a new applicaiton, the first step is to copy the new application folder into the root of SYNtzulu-Conv, otherwise you can skip this, and jump to step 2.
Then, to properly configure the new application, use the following command:
```
make create_application app=emg
```
Replace *emg* with the name of your application folder.
This command will automatically place the configuration files in the proper paths and compile the firmware.

Step 2.
To start the simulation, simply execute the command:
```
make simulate
```
This process may take a few minutes. If the delta modulation and inference results are correct, the inference results will appear in the terminal. If there are mismatches between simulated and expected results, the errors will be reported in the terminal.

## First run

### Flash setup

Before testing the system, you must write the flash memory with the test vector, as the flash will emulate an sEMG SPI sensor:
```
cd flash
./flash_program.sh
```
The operation will take several minutes.

### Building the system

To build SYNtzulu, execute the following command from the root of the project:
```
make build
```

Then write the bitstream to the flash memory using:
```
make prog
```
> [!WARNING]
> Check the jumpers of yours iCEbreaker are in "Program Flash" mode. This should be the default configuration.

To store the inference results, use the following command:
```
make listen
```
**Push the uButton**, located to the right of the supply port on the iCEBreaker, to start execution.

## Power consumption

The most cheap method to measure the power consumption of the system involves:
1. Cutting the VCORE jumper,
2. Soldering a shunt resistor (we used 3.3 ohm)
3. Measuring the voltage drop using an oscilloscope (we used the Analog Discovery 2 Oscilloscope).

# Citation

If you wish to cite this work, please use the following: 

@ARTICLE{SYNtzuluConv,  
  author={Leone, Gianluca and Mura, Federico and Raffo, Luigi and Meloni, Paolo},  
  title={SYNtzulu-Conv: Enabling Spiking 2D Convolutions for Sensor Data Analysis on Low-Power FPGAs},  
  booktitle={Highly Efficient Accelerators & Reconfigurable Technologies (HEART 2026)}, 
  year={2026}
  doi={} }

# Acknowledgments

We would like to thank the following repositories and authors for providing modules and resources that were invaluable in this project:

- [YosysHQ - Open Source EDA](https://github.com/YosysHQ/oss-cad-suite-build)
- [SERV](https://github.com/olofk/serv/tree/main)
- [BasicUART](https://github.com/STjurny/BasicUART)
- [ice40_power](https://github.com/tinyvision-ai-inc/ice40_power)
- [picorv32](https://github.com/YosysHQ/picorv32)
