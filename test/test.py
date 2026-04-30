# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge

# =============================================================================
# Pin mapping (from tt_um_example):
#   ui_in[0]      -> gen
#   uio_out[0]    -> wants_ctrl
#   uio_out[1]    -> wr_en
#   uio_out[3:2]  -> wr_data
#   uo_out[3:0]   -> wr_row
#   uo_out[7:4]   -> wr_col
#
# Debounce: StimulusGen STABLE_MS parameter must be small for simulation.
# Set STABLE_MS=1 in StimulusGen for TT sim (1000 cycles at 25MHz = 40us,
# manageable in simulation).
# =============================================================================

STABLE_CYCLES = 1100   # slightly more than STABLE_MS*1000 cycles to clear debounce

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def get_wants_ctrl(dut):
    return (dut.uio_out.value & 0x01) != 0

def get_wr_en(dut):
    return (dut.uio_out.value & 0x02) != 0

def get_wr_data(dut):
    return (dut.uio_out.value >> 2) & 0x03

def get_wr_row(dut):
    return dut.uo_out.value & 0x0F

def get_wr_col(dut):
    return (dut.uo_out.value >> 4) & 0x0F

async def reset(dut):
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.ena.value    = 1
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)

async def press_gen(dut):
    """Hold gen high long enough to pass debouncer then release."""
    dut.ui_in.value = 0x01   # gen = ui_in[0] = 1
    await ClockCycles(dut.clk, STABLE_CYCLES)
    dut.ui_in.value = 0x00   # release
    await ClockCycles(dut.clk, 2)

async def run_sweep(dut):
    """
    Wait for wants_ctrl to go high then monitor until it drops.
    Returns: (write_count, pattern_set)
      write_count  -- number of wr_en pulses seen
      pattern_set  -- set of (row, col) tuples that were written
    """
    errors = []

    # Wait for wants_ctrl
    timeout = 50
    for _ in range(timeout):
        await ClockCycles(dut.clk, 1)
        if get_wants_ctrl(dut):
            break
    else:
        errors.append("wants_ctrl never went high")
        return 0, set(), errors

    write_count  = 0
    pattern      = set()
    sweep_cycles = 0

    while get_wants_ctrl(dut):
        await ClockCycles(dut.clk, 1)
        sweep_cycles += 1

        if get_wr_en(dut):
            wd  = get_wr_data(dut)
            row = get_wr_row(dut)
            col = get_wr_col(dut)

            # wr_data must be 1 or 2
            if wd not in (1, 2):
                errors.append(f"wr_data={wd} invalid at row={row} col={col}")

            # row and col in range
            if row > 15 or col > 15:
                errors.append(f"out of range: row={row} col={col}")

            # wants_ctrl must be high
            if not get_wants_ctrl(dut):
                errors.append("wr_en high but wants_ctrl low")

            pattern.add((row, col))
            write_count += 1

        if sweep_cycles > 300:
            errors.append("sweep took more than 300 cycles, possible hang")
            break

    # Sweep should take exactly 257 cycles (256 SWEEP + 1 DONE)
    if sweep_cycles != 257:
        errors.append(f"sweep took {sweep_cycles} cycles, expected 257")

    return write_count, pattern, errors


# =============================================================================
# Tests
# =============================================================================

@cocotb.test()
async def test_basic_sweep(dut):
    """Test 1: Basic sweep — wants_ctrl, duration, data validity."""
    dut._log.info("Starting test_basic_sweep")

    clock = Clock(dut.clk, 40, unit="ns")   # 25 MHz
    cocotb.start_soon(clock.start())

    await reset(dut)

    dut._log.info("Pressing gen...")
    await press_gen(dut)

    count, pattern, errors = await run_sweep(dut)

    for e in errors:
        dut._log.error(f"FAIL: {e}")

    assert len(errors) == 0, f"test_basic_sweep had {len(errors)} error(s)"

    # wants_ctrl should now be low
    assert not get_wants_ctrl(dut), "FAIL: wants_ctrl still high after sweep"

    dut._log.info(f"PASS: sweep complete, {count} tiles written")


@cocotb.test()
async def test_different_patterns(dut):
    """Test 2: Two gen presses produce different patterns."""
    dut._log.info("Starting test_different_patterns")

    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    await reset(dut)

    # First press
    await press_gen(dut)
    _, pattern_a, errors_a = await run_sweep(dut)
    for e in errors_a:
        dut._log.error(f"Sweep 1 FAIL: {e}")

    # Wait between presses so free_cnt advances
    await ClockCycles(dut.clk, 20)

    # Second press
    await press_gen(dut)
    _, pattern_b, errors_b = await run_sweep(dut)
    for e in errors_b:
        dut._log.error(f"Sweep 2 FAIL: {e}")

    assert len(errors_a) == 0 and len(errors_b) == 0, "Errors during sweeps"
    assert pattern_a != pattern_b, "FAIL: both sweeps produced identical patterns"

    dut._log.info("PASS: sweeps produced different patterns")


@cocotb.test()
async def test_wr_en_only_during_ctrl(dut):
    """Test 3: wr_en never fires when wants_ctrl is low."""
    dut._log.info("Starting test_wr_en_only_during_ctrl")

    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    await reset(dut)

    # Check before any gen press — both should be low
    await ClockCycles(dut.clk, 10)
    assert not get_wants_ctrl(dut), "FAIL: wants_ctrl high before gen press"
    assert not get_wr_en(dut),      "FAIL: wr_en high before gen press"

    # Run a sweep and check wr_en after
    await press_gen(dut)
    _, _, errors = await run_sweep(dut)

    # After sweep, check again
    await ClockCycles(dut.clk, 5)
    assert not get_wr_en(dut), "FAIL: wr_en still high after sweep"

    assert len(errors) == 0
    dut._log.info("PASS: wr_en only fired during wants_ctrl")


@cocotb.test()
async def test_wr_data_valid(dut):
    """Test 4: wr_data is always 1 or 2 during a sweep."""
    dut._log.info("Starting test_wr_data_valid")

    clock = Clock(dut.clk, 40, unit="ns")
    cocotb.start_soon(clock.start())

    await reset(dut)

    await press_gen(dut)
    _, _, errors = await run_sweep(dut)

    data_errors = [e for e in errors if "wr_data" in e]
    assert len(data_errors) == 0, f"FAIL: invalid wr_data values: {data_errors}"

    dut._log.info("PASS: all wr_data values were 1 or 2")
