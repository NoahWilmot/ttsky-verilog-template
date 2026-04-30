# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

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

    sg = dut.user_project.SG

    dut.ui_in.value = 0x01

    # Wait until just before debounce fires
    await ClockCycles(dut.clk, 24990)

    # Sample every single cycle for 20 cycles around the firing point
    for i in range(20):
        await RisingEdge(dut.clk)
        dut._log.info(f"cycle {24990+i}: gen_pulse={int(sg.gen_pulse.value)} gen_stable={int(sg.gen_stable.value)} cur_state={int(sg.cur_state.value)} next_state={int(sg.next_state.value)} wants_ctrl={int(sg.wants_ctrl.value)} deb_cnt={int(sg.deb_cnt.value)}")

    assert True