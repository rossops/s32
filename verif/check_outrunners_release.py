#!/usr/bin/env python3
"""Static contract for the dedicated OutRunners (Multi 32) release profile."""

from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
common_qsf = (ROOT / "Arcade-SegaSystem32.qsf").read_text(encoding="utf-8")
orunners_qsf = (ROOT / "s32OutRunners.qsf").read_text(encoding="utf-8")
# The whole point of this revision is the Multi 32 runtime path: the shared
# single-screen restriction must not leak into it, nor any other dedicated
# game's profile.
assert 'VERILOG_MACRO "S32_SYSTEM32_ONLY=1"' not in orunners_qsf, \
    "OutRunners revision inherited the single-screen System 32 restriction"
assert 'VERILOG_MACRO "S32_JPARK_ONLY=1"' not in orunners_qsf, \
    "OutRunners revision inherited the unrelated gun-game profile"
assert 'VERILOG_MACRO "S32_REAL_V25=1"' not in orunners_qsf, \
    "OutRunners has no V25; the real-V25 core must stay out of this revision"
for macro in (
    "S32_ORUNNERS_ONLY=1",
    "S32_MULTI32_ONLY=1",
    "S32_V60_NO_FP=1",
    "S32_RELEASE_MINIMAL=1",
    "S32_JT12_MLAB_SHIFTS=1",
):
    assert f'VERILOG_MACRO "{macro}"' in orunners_qsf, \
        f"OutRunners revision is missing {macro}"
    assert f'VERILOG_MACRO "{macro}"' not in common_qsf, \
        f"shared QSF unexpectedly forces {macro}"

# The SDC's V60 two-cycle exception is only legal because this revision pins
# the V70 CE increment (no Turbo): 27127/65536 cannot carry on consecutive
# clk_sys edges.  Both halves of that contract must stay in place together.
top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
assert "wire [15:0] cpu_ce_inc = 16'd27127;" in top, \
    "OutRunners fixed 20 MHz V70 CE cadence is missing from the top level"
sdc = (ROOT / "Arcade-SegaSystem32.sdc").read_text(encoding="utf-8")
assert 's32OutRunners' in sdc, \
    "SDC no longer grants s32OutRunners the fixed-CE V60 timing exception"

matches = []
for path in (ROOT / "mra").glob("OutRunners (*.mra"):
    tree = ET.parse(path)
    matches.append((path, tree.getroot()))

assert len(matches) == 3, f"expected three OutRunners MRAs, found {len(matches)}"
for path, root in matches:
    assert root.findtext("rbf") == "s32OutRunners", \
        f"{path.name} must load s32OutRunners.rbf"

    buttons = root.find("buttons")
    assert buttons is not None, f"{path.name} is missing button metadata"
    assert buttons.get("names") == \
        "Shift Up,Shift Down,DJ Music,Music Prev,Music Next,-,Start,Coin,Test,Service"
    assert buttons.get("count") == "5"

    rom = root.find("rom[@index='0']")
    assert rom is not None and rom.get("zip") is None
    descriptor_part = rom.find("part")
    assert descriptor_part is not None and descriptor_part.text is not None
    descriptor = bytes.fromhex(descriptor_part.text.strip())
    assert len(descriptor) == 64, f"{path.name}: descriptor length changed"
    # b0: Multi 32 board with the MSM6253 ADC (0x01 | 0x08); b1: driving
    # analog profile (wheel/accel/brake) without the cabinet gear toggle;
    # b4: the split shift/DJ digital port layout across both I/O chips.
    assert descriptor[0] == 0x09, \
        f"{path.name}: expected Multi 32+ADC feature byte"
    assert descriptor[1] == 0x10, \
        f"{path.name}: expected the driving analog profile"
    assert descriptor[2] == 0x00, f"{path.name}: unexpected protection HLE"
    assert descriptor[3] == 0x83, f"{path.name}: sprite-bank contract changed"
    assert descriptor[4] == 0x02, \
        f"{path.name}: expected the OutRunners digital port layout"
    assert descriptor[5:] == bytes(59), f"{path.name}: unexpected options"

    nvram = root.find("nvram[@index='3']")
    assert nvram is not None and nvram.get("size") == "128", \
        f"{path.name}: EEPROM contract changed"

print("OUTRUNNERS RELEASE PASS: profile and three regional MRAs")
