# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

STABLE_CYCLES = 26000  # STABLE_MS=1, CLK_MHZ=25 -> 25000 cycles + margin

def wants_ctrl(dut): return (int(dut.uio_out.value) & 0x01) != 0
def wr_en(dut):      return (int(dut.uio_out.value) & 0x02) != 0
def wr_data(dut):    return (int(dut.uio_out.value) >> 2) & 0x03
def wr_row(dut):     return  int(dut.uo_out.value)        & 0x0F
def wr_col(dut):     return (int(dut.uo_out.value) >> 4)  & 0x0F

async def reset(dut):
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.ena.value    = 1
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)

async def press_gen(dut):
    dut.ui_in.value = 0x01
    await ClockCycles(dut.clk, STABLE_CYCLES)
    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, 2)

async def sweep(dut):
    """Run one full sweep, return set of (row,col) cells written."""
    await ClockCycles(dut.clk, 1)
    assert wants_ctrl(dut), "wants_ctrl did not go high"
    pattern = set()
    cycles = 0
    while wants_ctrl(dut):
        await ClockCycles(dut.clk, 1)
        cycles += 1
        if wr_en(dut):
            assert wr_data(dut) in (1, 2)
            assert wr_row(dut) <= 15
            assert wr_col(dut) <= 15
            pattern.add((wr_row(dut), wr_col(dut)))
        assert cycles <= 300, "sweep took too long"
    assert cycles == 257, f"sweep took {cycles} cycles, expected 257"
    return pattern


@cocotb.test()
async def test_basic_sweep(dut):
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    await reset(dut)
    await press_gen(dut)
    await sweep(dut)
    assert not wants_ctrl(dut)


@cocotb.test()
async def test_different_patterns(dut):
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    await reset(dut)
    await press_gen(dut)
    pattern_a = await sweep(dut)
    await ClockCycles(dut.clk, 20)
    await press_gen(dut)
    pattern_b = await sweep(dut)
    assert pattern_a != pattern_b


@cocotb.test()
async def test_wr_en_gated(dut):
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    await reset(dut)
    await ClockCycles(dut.clk, 10)
    assert not wants_ctrl(dut)
    assert not wr_en(dut)
    await press_gen(dut)
    await sweep(dut)
    assert not wants_ctrl(dut)
    assert not wr_en(dut)