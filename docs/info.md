<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

StimulusGen is an ASIC stimulus generator for the TileGrowth simulator. On a button press it sweeps all 256 tiles of a 16×16 grid, using an internal LFSR to randomly place tiles with a 1/16 chance and toggle color with a 50/50 chance per tile. The LFSR is seeded differently each press using a free-running counter, ensuring a unique pattern every time. Outputs `wants_ctrl` while active to signal the FPGA host to hand over the grid write port.

## How to test

Run the cocotb testbench in the repository to verify correct behaviour in simulation. In hardware, press the `gen` button to generate a random tile arrangement on the LED matrix, then press `start` on the FPGA to begin the simulation.

## External hardware

- 16×16 WS2812B LED matrix
- TileGrowth FPGA host
- Momentary push button on `gen` (ui_in[0])
