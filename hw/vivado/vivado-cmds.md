# Vivado commands

Copy-paste commands for the scripts in this folder. Run everything **from the repo root**. The scripts find their own paths, so the folder you start from only matters for where Vivado drops its log files.

Vivado is not on PATH. Set a shortcut once per terminal:

```powershell
# PowerShell
$v = "F:\Xilinx\2026.1\Vivado\bin\vivado.bat"
```

```bash
# Git Bash
v=/f/Xilinx/2026.1/Vivado/bin/vivado.bat
```

Change the path if Vivado is installed somewhere else on your PC.

`-nojournal -nolog` stops Vivado from leaving `vivado.jou` / `vivado.log` in the repo root. `-notrace` stops it echoing every line of the script. Drop them when you want the full log for debugging.

---

## The normal flow

| Step | PowerShell | Takes | Produces |
|---|---|---|---|
| 1. Create the project | `& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/create_project.tcl` | ~30 s | `hw/vivado/build/lca_tiny_cnn.xpr` |
| 2. Build the bitstream | `& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/build_bitstream.tcl` | 2–5 min | `.bit` file and reports |
| 3. Program the board | `& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/program_board.tcl` | ~20 s | Design running on the Basys3 |

In Git Bash, replace `& $v` with `$v`.

- **Step 1** only needs to run again when files are added or removed, or after a fresh clone. It deletes and recreates `hw/vivado/build/`.
- **Step 2** after every RTL or XDC change.
- **Step 3** after every build, and after every power cycle (JTAG programming is lost when the board is switched off).

---

## Running the tests (regression)

`run_tests.tcl` runs every testbench in its list and prints a PASS/FAIL table. **Run it before every merge to `main`.**

```powershell
& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/run_tests.tcl                  # every test
& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/run_tests.tcl -tclargs seg7    # names containing "seg7"
```

### What it does

```
for each test in the list:
  fresh folder hw/vivado/build/tests/<name>/ ─► copy mem/*.mem in ─► xvlog (compile) ─► xelab (build) ─► xsim (run)
  read the output: "TEST PASSED"? "TEST FAILED"? nothing?
then: print the table, exit code 0 (all PASS) or 1 (anything else)
```

- Calls the simulator directly, so it **doesn't need the Vivado project or the GUI**. Works on a fresh clone. About 5 s per test.
- Each test runs in its own clean folder (deleted and recreated every run), so old results never leak into new ones.
- The `.mem` files are copied into that folder, which is why `$readmemh("test_images.mem", ...)` works with a bare file name.
- Each test compiles **only its own files**, so a broken file in one person's module can't break everyone else's tests.

### Reading the table

```
TEST                 RESULT         TIME(s)  DETAIL
------------------------------------------------------------------------------------------
U8_btn_debounce      PASS               4.3
U9_seg7_mux          PASS               4.5
U6_argmax3           NO RESULT          4.5  testbench did not print TEST PASSED / TEST FAILED
------------------------------------------------------------------------------------------
2 of 3 passed. Logs: .../hw/vivado/build/tests/<test>/run.log
```

| Result | Meaning | What to do |
|---|---|---|
| `PASS` | The testbench printed `TEST PASSED` | Nothing |
| `FAIL` | It printed `TEST FAILED: <n> errors` | Open `run.log`: the `MISMATCH` lines show the first 10 failures (expected vs actual) |
| `NO RESULT` | It finished (`$finish`) without printing a verdict | The testbench doesn't check anything yet: make it self-checking (rules below) |
| `TIMEOUT` | No `$finish` within 100 ms of simulated time | The testbench forgot `$finish`, or the design hangs (FSM stuck, `done` never arrives) |
| `COMPILE ERROR` | `xvlog` failed: syntax error | DETAIL shows the first `ERROR` line |
| `ELAB ERROR` | `xelab` failed: usually a module not found, or port names that don't match | Add the missing file to the test's line, or fix the port names |

**Only `PASS` counts as passing.** A testbench that prints nothing must never look green.

### Rules every testbench must follow

For `run_tests.tcl` to judge a testbench, it must:

1. **check its own outputs**: compare actual against expected and count errors;
2. **print exactly** `TEST PASSED` or `TEST FAILED: <n> errors` at the start of a line, as the last verdict;
3. **call `$finish`** at the end;
4. have **file name = module name** (`tb_seg7_mux.v` holds `module tb_seg7_mux`), because the script uses the file name as the top module.

Also useful: print the first 10 mismatches with index, expected and actual. Recommended: one `check N <what>  OK` line per check, so the log doubles as evidence for the verification report.

Minimal example:

```verilog
integer errors = 0;
// ... after each comparison:
if (actual !== expected) begin
    errors = errors + 1;
    if (errors <= 10) $display("MISMATCH %0d: index %0d expected %h actual %h", errors, i, expected, actual);
end
// ... at the end:
if (errors == 0) $display("TEST PASSED");
else             $display("TEST FAILED: %0d errors", errors);
$finish;
```

### Adding a test

One line in the `tests` list at the top of `run_tests.tcl`, paths relative to `hw/`:

```tcl
set tests {
    ...
    {U1_mac   tb/conv/tb_mac.v   {rtl/cnn/conv/mac.v}}
    #  name     testbench          every RTL file the testbench uses, including sub-modules
}
```

- **name:** shows in the table. Start with the test ID from the verification plan (U1, I3, …) when there is one.
- **RTL list:** every module the testbench instantiates, *and their sub-modules*. Missing one gives `ELAB ERROR: module not found`. System tests (`tb_cnn_core`) need almost every file.
- Add the line **in the same commit as the testbench**.
- Headers (`cnn_params.vh`, `tb_utils.vh`) don't go in the list: `hw/rtl/include/` and `hw/tb/common/` are already include folders.

### Where the output goes

```
hw/vivado/build/tests/<name>/      (ignored by git)
├── run.log        compile + elaborate + simulation output: read this when a test fails
├── run_sim.tcl    "run 100 ms / quit"
├── *.mem          copies of mem/*.mem
└── xsim.dir/      simulator internals
```

To look at **waveforms**, run the testbench in the XSim GUI instead (see "Using the GUI instead" below, or compile with `xelab ... -debug typical` and open `xsim <snapshot> -gui`).

### Known limitations

- The production tests copy `mem/*.mem` and `mem/golden/*.mem` into each test folder. If `mem/` changes, re-run `python hw/tools/export_golden.py` first, or the golden comparisons fail.
- The test list is maintained by hand. It could switch to finding `hw/tb/**/tb_*.v` automatically.
- Post-synthesis simulation is a different flow and isn't covered.

---

## Choosing the top module

`create_project.tcl` uses **`top_basys3`** (the real design, with the CNN core) unless told otherwise:

```powershell
& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/create_project.tcl                                  # top_basys3, real CNN core
& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/create_project.tcl -tclargs top_basys3 USE_STUB=1   # board side only, CNN replaced by a stub
& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/create_project.tcl -tclargs bringup_top             # switches → LEDs board test
```

**`build_bitstream.tcl` and `program_board.tcl` have no top of their own.** They use whatever top the project was last created with. To switch tops, rerun `create_project.tcl` with the top you want. That deletes `hw/vivado/build/`, including the previous `.bit` file, so archive anything you still need first (`build_bitstream.tcl` already archives the reports, see below).

To check which top the current project has:

- the last line `create_project.tcl` printed: `Project created: ... (top = top_basys3 )`. Nothing after the top name means `USE_STUB = 0`;
- or open `lca_tiny_cnn.xpr` in the GUI: the top is shown in bold in the Sources pane;
- or look at the bitstream name: `lca_tiny_cnn.runs/impl_1/<top>.bit`.

The real design (`USE_STUB = 0`) needs `mem/test_images.mem`, `test_labels.mem`, the four weight/bias files and `quant_params.txt`. `create_project.tcl` stops with `Missing model memory: ...` if one is missing. It also runs `python` to turn `quant_params.txt` into a Verilog header (`hw/tools/prepare_quant_params.py`, standard library only, so any Python 3 works). If `python` isn't on PATH, point it at one first: `$env:CNN_PYTHON = "<repo>\.venv\Scripts\python.exe"`.

---

## Where things end up

| What | Path |
|---|---|
| Project (open in the GUI) | `hw/vivado/build/lca_tiny_cnn.xpr` |
| Bitstream | `hw/vivado/build/lca_tiny_cnn.runs/impl_1/<top>.bit` |
| Utilization report (LUT/FF/BRAM/DSP) | `hw/vivado/build/reports/<top>_utilization.txt` |
| Timing report (WNS, Fmax) | `hw/vivado/build/reports/<top>_timing.txt` |
| Synthesis / implementation logs | `hw/vivado/build/lca_tiny_cnn.runs/synth_1/runme.log`, `impl_1/runme.log` |

All of `hw/vivado/build/` is in `.gitignore`, and the next `create_project.tcl` deletes it. So at the end of every run, `build_bitstream.tcl` also **archives the reports in git**:

| What | Path |
|---|---|
| Archive of one build | `report/builds/Bnn_<commit>/` (build number counts up, `<commit>` = the commit that was built) |
| In that folder | `build_info.txt` (commit, top, generic, WNS/TNS/WHS, LUT/FF/BRAM/DSP), `utilization.txt`, `utilization_hier.txt` (per module), `timing.txt`, `critical_paths.txt` (10 worst paths), `drc.txt`, `synth_warnings.txt` |
| Log of all builds | `report/implementation_log.md`: paste the row the script prints at the end, and write what changed |
| Board results per build | `report/board_test_log.md` |

If `hw/` or `mem/` had uncommitted changes, the folder name ends in **`_dirty`**: that build can't be reproduced from git. Commit first, then build.

The `.bit` file is not archived (it's 2 MB per build). Copy the final one into `report/` by hand for the deliverables.

How to read these reports (every field of utilization, timing, `check_timing`, synthesis warnings and DRC, and the synthesis checks): [study-material/reading_vivado_reports.pdf](../../study-material/reading_vivado_reports.pdf).

---

## Using the GUI instead

1. Run step 1 once (or `source hw/vivado/create_project.tcl` from the Vivado Tcl Console).
2. Open `hw/vivado/build/lca_tiny_cnn.xpr`.
3. **Generate Bitstream**, then **Open Hardware Manager → Open Target → Auto Connect → Program Device**.

Use forward slashes in the Tcl Console: `source C:/path/to/lca-tiny-cnn-basys3/hw/vivado/create_project.tcl`.

---

## Checking results

```powershell
# Did timing pass? WNS must be >= 0
Select-String -Path hw/vivado/build/reports/*_timing.txt -Pattern "WNS\(ns\)" -Context 0,2

# Warnings from the last build
Select-String -Path hw/vivado/build/lca_tiny_cnn.runs/*/runme.log -Pattern "^(CRITICAL WARNING|WARNING|ERROR)"
```

`build_bitstream.tcl` also prints the bitstream path and the worst negative slack at the end.

---

## Board connection

- Plug the micro-USB cable into the **PROG / UART** port and switch the board on. That cable is the JTAG link; no other cable is needed.
- The JP1 jumper position doesn't matter for programming from Vivado.
- Success looks like: `End of startup status: HIGH` and `Programmed xc7a35t_0 with ...`. The green DONE LED on the board lights.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `vivado.bat` not recognized | Use the full path or set `$v` as above |
| `No xc7a35t found on the cable` / no hardware target | Board off, or a charge-only USB cable: try another cable. Check Device Manager for "USB Serial Converter A/B". If missing, run the `install_drivers` script in Vivado's `cable_drivers` folder as administrator, then replug |
| `No bitstream at ...` | Run `build_bitstream.tcl` first |
| Build produced `bringup_top.bit` (or a stub build) instead of the real `top_basys3.bit` | The project was last created with another top. Rerun `create_project.tcl` without `-tclargs` (default `top_basys3`), then `build_bitstream.tcl` |
| Board shows `rt` on (almost) every image, or `build_bitstream.tcl` stops with "needs the quant config" | The top was changed to `top_basys3` in the GUI on a project created for another top, so the quant config is missing and the conv synthesizes with `S1 = -1`. **Don't change the top in the GUI.** Rerun `create_project.tcl`, then build. Check the synthesis log says `Parameter S1 bound to: 9` |
| `Missing model memory: mem/<name>` | A `.mem` file the real core needs isn't in `mem/`. Restore it from the repository, or build the board side only with `-tclargs top_basys3 USE_STUB=1` |
| Timing report shows negative WNS | Timing failed at 100 MHz. Don't rely on the board result. See `critical_paths.txt` in the build archive and §10 of `study-material/reading_vivado_reports.pdf` |
| `Synthesis failed` / `Implementation failed` | Open the `runme.log` path it prints and search for `ERROR` |
| `[Common 17-69] ... locked` or the project is open elsewhere | Close the Vivado GUI before running a batch script on the same project |
| New `.v` file not in the project | Rerun step 1 (it adds the whole `hw/rtl/` tree) |
| Strange errors after a Vivado crash | Delete `hw/vivado/build/` and rerun step 1 |
