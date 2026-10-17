# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 100)

    # Nothing should be stuck at X or Z once the design has been reset and clocked.
    assert dut.uo_out.value.is_resolvable, "uo_out has X or Z bits"
    assert dut.uio_out.value.is_resolvable, "uio_out has X or Z bits"
    assert dut.uio_oe.value.is_resolvable, "uio_oe has X or Z bits"
