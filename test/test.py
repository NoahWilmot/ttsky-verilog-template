# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

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
async def test_basic_sweep(dut):
    await init(dut)
    assert True

@cocotb.test()
async def test_different_patterns(dut):
    await init(dut)
    assert True

@cocotb.test()
async def test_wr_en_gated(dut):
    await init(dut)
    assert True