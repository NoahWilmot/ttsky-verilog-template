# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

STABLE_CYCLES = 26000

def wants_ctrl(dut): return (int(dut.uio_out.value) & 0x01) != 0
def wr_en(dut):      return (int(dut.uio_out.value) & 0x02) != 0
def wr_data(dut):    return (int(dut.uio_out.value) >> 2) & 0x03
def wr_row(dut):     return  int(dut.uo_out.value)        & 0x0F
def wr_col(dut):     return (int(dut.uo_out.value) >> 4)  & 0x0F

async def init(dut):
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.ena.value    = 1
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 5)

@cocotb.test()
async def test_debug(dut):
    await init(dut)

    # Sample before press
    dut._log.info(f"Before press: ui_in={int(dut.ui_in.value)} uio_out={int(dut.uio_out.value)} uo_out={int(dut.uo_out.value)}")

    # Press gen
    dut.ui_in.value = 0x01
    dut._log.info(f"Gen pressed")

    # Sample every 5000 cycles during press
    for i in range(6):
        await ClockCycles(dut.clk, 5000)
        dut._log.info(f"  t={i*5000+5000} cycles: ui_in={int(dut.ui_in.value)} uio_out={int(dut.uio_out.value):08b} wants_ctrl={wants_ctrl(dut)}")

    # Release
    dut.ui_in.value = 0x00
    dut._log.info(f"Gen released")
    await ClockCycles(dut.clk, 10)
    dut._log.info(f"After release: uio_out={int(dut.uio_out.value):08b} wants_ctrl={wants_ctrl(dut)}")

    assert True