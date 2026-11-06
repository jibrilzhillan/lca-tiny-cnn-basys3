# hw/ — FPGA design files

Everything that runs on (or simulates) the Basys3: RTL, testbenches, constraints, Python verification tools and the Vivado scripts. The training side lives in [`../sw/`](../sw/), and the `.mem` files that connect the two live in [`../mem/`](../mem/).

The decisions behind this layout are D13 and D14 in [../DESIGN_DECISIONS.md](../DESIGN_DECISIONS.md).

```
hw/
├── rtl/                          synthesizable Verilog
│   ├── include/
│   │   └── cnn_params.vh         every size and width (D22)
│   ├── lib/                      generic modules, not CNN-specific
│   │   ├── rom.v
│   │   ├── ram.v
│   │   └── btn_debounce.v
│   ├── cnn/                      the accelerator (no board-specific logic)
│   │   ├── cnn_core.v            engines, memories and controller wired together
│   │   ├── cnn_ctrl.v            FSM: conv → pool → FC → argmax, cycle counter
│   │   ├── conv/
│   │   │   ├── conv_engine.v
│   │   │   ├── address_generator.v
│   │   │   ├── mac.v             multiply-accumulate, mapped to a DSP48
│   │   │   └── relu_requant.v
│   │   └── classifier/
│   │       ├── maxpool_engine.v
│   │       ├── fc_engine.v
│   │       └── argmax3.v
│   └── board/                    Basys3-specific
│       ├── top_basys3.v          board top level
│       ├── seg7_mux.v
│       ├── result_display.v
│       ├── hex_to_7seg.v         hex digit → seven-segment pattern
│       ├── cnn_core_stub.v       stand-in for cnn_core (top_basys3 USE_STUB=1)
│       └── bringup_top.v         first board test: switches → LEDs and display
├── tb/                           self-checking testbenches, mirroring rtl/
│   ├── common/                   shared helpers, quantization test, mocks/ (fake engines for wiring tests)
│   ├── lib/                      tb_rom.v, tb_ram.v, tb_btn_debounce.v (U8)
│   ├── cnn/                      tb_cnn_ctrl.v (U7), tb_quant_config.v
│   ├── conv/                     tb_mac.v (U1), tb_relu_requant.v (U2), tb_conv_engine.v (U3, U10, I1),
│   │                             tb_conv_engine_directed.v (zero, all-255 and single-pixel images)
│   ├── classifier/               tb_maxpool_engine.v (U4), tb_fc_engine.v (U5), tb_argmax3.v (U6),
│   │                             generate_classifier_fixtures.py (their test vectors)
│   ├── board/                    tb_seg7_mux.v (U9), tb_result_display.v
│   └── system/                   tests with more than one module, see system/README.md
├── constr/
│   ├── basys3.xdc                pin and clock constraints (the one the project uses)
│   └── Basys-3-Master.xdc        Digilent's original, reference only
├── tools/                        Python (NumPy) verification tools
│   ├── int_model.py              integer golden model, bit-exact with the RTL
│   ├── export_golden.py          writes mem/golden/ for the 16 board images (D28)
│   ├── verify_export.py          re-checks mem/ and mem/golden/ with an independent model
│   ├── prepare_quant_params.py   turns mem/quant_params.txt into a Verilog header
│   ├── eval_test_set.py          test-set accuracy of the integer model
│   ├── gen_regression_vectors.py vectors for the many-image regression
│   └── run_regression.py         runs that regression (XSim or Icarus)
└── vivado/                       Tcl scripts
    ├── create_project.tcl        create the project in vivado/build/ (default top: top_basys3)
    ├── build_bitstream.tcl       synthesis → implementation → bitstream; reports archived in report/builds/
    ├── program_board.tcl         program the Basys3 over USB
    ├── run_tests.tcl             every testbench, PASS/FAIL table
    ├── synth_check.tcl           quick synthesis of one module (no project, no implementation)
    └── vivado-cmds.md            copy-paste commands, output paths, troubleshooting
```

Test IDs: **U** = unit test of one module, **I** = integration test of several modules, **R1** = many-image regression.

## Build and program (from the repo root)

```powershell
$v = "C:\path\to\Vivado\2026.1\bin\vivado.bat"
& $v -mode batch -nojournal -nolog -source hw/vivado/create_project.tcl                       # top = top_basys3, the real design (needs every mem/ file)
& $v -mode batch -nojournal -nolog -source hw/vivado/create_project.tcl -tclargs top_basys3 USE_STUB=1   # board side with cnn_core_stub
& $v -mode batch -nojournal -nolog -source hw/vivado/create_project.tcl -tclargs bringup_top  # switches → LEDs board test
& $v -mode batch -nojournal -nolog -source hw/vivado/build_bitstream.tcl                      # builds the project's top; archives reports in report/builds/Bnn_<commit>/
& $v -mode batch -nojournal -nolog -source hw/vivado/program_board.tcl                        # USB cable in, board on
& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/run_tests.tcl                   # all testbenches
& $v -mode batch -nojournal -nolog -notrace -source hw/vivado/synth_check.tcl -tclargs cnn_core   # quick synthesis of one module
```

Or open `hw/vivado/build/lca_tiny_cnn.xpr` in the Vivado GUI after the first script.

`run_tests.tcl` takes an optional filter: a group (`core`, `classifier`, `board`, `quant`, `production`) or part of a test name, for example `-tclargs classifier`.

## Where the memories are instantiated

The memories are instances of `rom.v` / `ram.v`, placed in the module that uses them:

| Instance | Module | Instantiated in | Init file (`../mem/`) |
|---|---|---|---|
| `image_rom` | `rom.v` | `cnn_core.v` | `test_images.mem` |
| `fmap_ram` | `ram.v` | `cnn_core.v` | — |
| `pool_ram` | `ram.v` | `cnn_core.v` | — |
| `conv_w_rom`, `conv_b_rom` | `rom.v` | `conv_engine.v` | `conv_weight.mem`, `conv_bias.mem` |
| `fc_w_rom`, `fc_b_rom` | `rom.v` | `fc_engine.v` | `fc_weight.mem`, `fc_bias.mem` |
| `label_rom` | `rom.v` | `top_basys3.v` | `test_labels.mem` |

## Rules

- **One module per file, file name = module name.** `conv_engine.v` holds `module conv_engine`. Its testbench is `tb_conv_engine.v`.
- **Every file starts with a short header:** file name and purpose.
- **Include headers by name only:** `` `include "cnn_params.vh" `` and, in testbenches, `` `include "tb_utils.vh" ``. The scripts set `hw/rtl/include` as the include directory for synthesis and simulation, and add `hw/tb/common` for simulation.
- **Never write relative paths in `$readmemh`.** XSim runs from a deep `.sim/` folder, so `../../mem/...` breaks. Pass the file name as a parameter; the Tcl scripts add the `.mem` files from [`../mem/`](../mem/).
- **Never hand-edit `.mem` files.** The weights come from the training export; `mem/golden/` comes from `tools/export_golden.py`.
- **Every testbench checks itself** and ends with exactly `TEST PASSED` or `TEST FAILED: <n> errors`; `run_tests.tcl` looks for that line.
- **Signals:** `snake_case`; active-low signals end in `_n`, single-cycle pulses in `_p`. Parameters are `UPPER_CASE` from `cnn_params.vh`.
- **Commit only sources and scripts.** The generated Vivado project goes in `vivado/build/`, which is in `.gitignore`.
- **New files are picked up automatically.** The Tcl scripts add sources with a recursive glob.
