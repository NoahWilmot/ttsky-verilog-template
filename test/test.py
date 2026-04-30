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
async def test_debug(dut):
    await init(dut)

    # Probe internal signals
    sg = dut.user_project.SG

    dut._log.info(f"cur_state={int(sg.cur_state.value)} gen_pulse={int(sg.gen_pulse.value)} wants_ctrl={int(sg.wants_ctrl.value)}")

    dut.ui_in.value = 0x01
    dut._log.info("Gen pressed")

    for i in range(7):
        await ClockCycles(dut.clk, 5000)
        dut._log.info(f"t={i*5000+5000}: cur_state={int(sg.cur_state.value)} gen_pulse={int(sg.gen_pulse.value)} gen_stable={int(sg.gen_stable.value)} wants_ctrl={int(sg.wants_ctrl.value)} deb_cnt={int(sg.deb_cnt.value)}")

    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, 10)
    dut._log.info(f"After release: cur_state={int(sg.cur_state.value)} wants_ctrl={int(sg.wants_ctrl.value)}")

    assert True