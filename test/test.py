# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

CLK_MHZ = 25;
STABLE_MS = 20;
DEBOUNCE_CYCLES = CLK_MHZ * 1000 * STABLE_MS;

def wants_ctrl(dut): 
    return (int(dut.uio_out.value) & 0x01) != 0
def wr_en(dut):      
    return (int(dut.uio_out.value) & 0x02) != 0
def wr_data(dut):    
    return (int(dut.uio_out.value) >> 2) & 0x03
def wr_row(dut):     
    return  int(dut.uo_out.value) & 0x0F
def wr_col(dut):     
    return (int(dut.uo_out.value) >> 4) & 0x0F

async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.ena.value    = 1
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 5)

#Presses gen, waits for debounce, monitors sweep, and releases gen
async def gen_and_sweep(dut):
    # Hold gen high until debounce fires
    dut.ui_in.value = 0x01
    await ClockCycles(dut.clk, DEBOUNCE_CYCLES+2) # +2 for sync

    # Look for wants_ctrl 
    for _ in range(10):
        if wants_ctrl(dut):
            break
        await ClockCycles(dut.clk, 1)
    else:
        assert False, "wants_ctrl did not go high"

    # Monitor sweep
    grid = set()
    cycles = 0
    while wants_ctrl(dut):
        await ClockCycles(dut.clk, 1)
        cycles += 1
        if wr_en(dut):
            assert wr_data(dut) in (1, 2)
            assert wr_row(dut) <= 15
            assert wr_col(dut) <= 15
            grid.add((wr_row(dut), wr_col(dut)))
        assert cycles <= 300, "sweep took too long"
    assert cycles == 257, f"sweep took {cycles} cycles, expected 257"

    # Release gen and wait for debouncer to register the release
    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, DEBOUNCE_CYCLES + 10) # +10 for wiggle room
    return grid

#presses gen and monitors the sweep
#checks that wants_ctrl is high for 257 cycles (256 tiles + 1 DONE)
#checks that wr_data is only either 1(blue) or 2(red)
#checks that wr_row/wr_col are always between 0-15 inclusive
@cocotb.test()
async def test_basic(dut):
    await reset(dut)
    await gen_and_sweep(dut)
    assert not wants_ctrl(dut)

#records the grid that results from a gen and sweep
#records the grid that results from another gen and sweep
#ensures that the patterns are unique
@cocotb.test()
async def test_grids(dut):
    await reset(dut)
    grid_a = await gen_and_sweep(dut)
    await ClockCycles(dut.clk, 20)
    grid_b = await gen_and_sweep(dut)
    assert grid_a != grid_b

#checks that wants_ctrl and wr_en are both low before a gen press
#pressed gen and waits for sweep to complete
#checks that wants_ctrl and wr_en are both low after a gen press
#ensures that the module is not driving the grid outside of an active sweep
@cocotb.test()
async def test_passive(dut):
    await reset(dut)
    await ClockCycles(dut.clk, 10)
    assert not wants_ctrl(dut)
    assert not wr_en(dut)
    await gen_and_sweep(dut)
    assert not wants_ctrl(dut)
    assert not wr_en(dut)