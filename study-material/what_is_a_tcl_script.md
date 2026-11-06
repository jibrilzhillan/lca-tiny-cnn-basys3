# What Is a Tcl Script (and Why Our Vivado Project Uses One)

For team members who have only used the Vivado GUI. About 10 minutes to read.

---

## 1. The short answer

**Tcl** (pronounced "tickle") is a small scripting language. Vivado is built on it: **every button you click in the GUI runs a Tcl command underneath.** A Tcl script is just a text file (`.tcl`) with those commands written out, so Vivado can repeat them without you clicking.

You have already seen Tcl without noticing. Open the **Tcl Console** tab at the bottom of the Vivado window. Every time you click something, the matching command appears there:

```tcl
create_project lca_tiny_cnn ./build -part xc7a35tcpg236-1
add_files hw/rtl/cnn/conv/mac.v
launch_runs synth_1 -jobs 4
```

---

## 2. Why use a script instead of the GUI?

| Problem with clicking | How a script fixes it |
|---|---|
| A Vivado project folder (`.xpr`, `.runs/`, `.cache/`, `.sim/`) is hundreds of MB, full of absolute paths like `C:\Users\you\...`, and breaks on another PC | We commit only the small `.tcl` file. Each person runs it and gets an identical project on their own machine |
| Five people adding files by hand means someone always forgets one, or adds it to the wrong fileset | The script adds every file the same way, every time |
| "It works on my machine" | Same script, same part, same settings for everyone |
| Running 10 testbenches by hand takes 20 minutes of clicking | `run_tests.tcl` runs them all and prints PASS/FAIL in one go |
| Rebuilding the bitstream for the demo at 2 a.m. | One command, no clicks to forget |

That's why our repo has [`hw/vivado/`](../hw/vivado/) with scripts in it, and **not** a Vivado project.

---

## 3. Tcl syntax in 2 minutes

Tcl is simple: **every line is `command arg1 arg2 ...`**, separated by spaces.

```tcl
# A comment (must start the line)
set part xc7a35tcpg236-1          ;# set a variable; inline comments need ;#
puts "Target part is $part"       ;# $name reads a variable, puts prints

set n [llength {a b c}]           ;# [ ... ] runs a command and uses its result
puts "List has $n items"          ;# -> List has 3 items

foreach tb {tb_mac tb_argmax3} {  ;# loop over a list
    puts "Running $tb"
}

if {$n > 2} {                     ;# condition goes in { }
    puts "more than two"
}

proc square {x} {                 ;# define your own command (a function)
    return [expr {$x * $x}]       ;# expr does arithmetic
}
puts [square 5]                   ;# -> 25
```

The three brackets are the only tricky part:

| Brackets | Meaning | Example |
|---|---|---|
| `"..."` | Text, **with** `$variables` and `[commands]` filled in | `"Part is $part"` |
| `{...}` | Text taken **literally**, nothing filled in (used for code blocks and lists) | `{a b c}` |
| `[...]` | Run this command, put its result here | `[get_files *.v]` |

---

## 4. Vivado commands you'll actually see

| Command | What it does | GUI equivalent |
|---|---|---|
| `create_project name dir -part xc7a35tcpg236-1` | New project | File → Project → New |
| `add_files hw/rtl` | Add sources (a folder is added **recursively**) | Add Sources → Design sources |
| `add_files -fileset sim_1 hw/tb` | Add testbenches | Add Sources → Simulation sources |
| `add_files -fileset constrs_1 hw/constr/basys3.xdc` | Add constraints | Add Sources → Constraints |
| `set_property include_dirs ... [current_fileset]` | Where `` `include `` looks for headers | Settings → General → Verilog options |
| `set_property top top_basys3 [current_fileset]` | Choose the top module | Right-click → Set as Top |
| `launch_simulation` / `run all` / `close_sim` | Simulate | Run Simulation |
| `launch_runs synth_1` + `wait_on_run synth_1` | Synthesize | Run Synthesis |
| `launch_runs impl_1 -to_step write_bitstream` | Implement + bitstream | Generate Bitstream |
| `report_utilization -file util.txt` | LUT/FF/BRAM/DSP numbers to a file | Reports → Utilization |
| `report_timing_summary -file timing.txt` | Fmax / slack to a file | Reports → Timing Summary |

---

## 5. What our `create_project.tcl` will look like

A sketch. It is short; most of the work is pointing at the right folders.

```tcl
# hw/vivado/create_project.tcl
# Recreates the Vivado project from the sources in git.

# Repo root = two folders up from this script, so it works from any directory
set root  [file normalize [file join [file dirname [info script]] .. ..]]
set build [file join $root hw vivado build]

create_project lca_tiny_cnn $build -part xc7a35tcpg236-1 -force

# Design sources: the whole rtl/ tree (add_files on a folder is recursive)
add_files [file join $root hw rtl]
set_property include_dirs [file join $root hw rtl include] [get_filesets sources_1]

# .mem files: added once here, so $readmemh only needs the bare file name
add_files [glob [file join $root mem *.mem]]

# Testbenches
add_files -fileset sim_1 [file join $root hw tb]
set_property include_dirs [list [file join $root hw rtl include] [file join $root hw tb common]] [get_filesets sim_1]

# Constraints
add_files -fileset constrs_1 [file join $root hw constr basys3.xdc]

set_property top top_basys3 [get_filesets sources_1]
puts "Project created in $build"
```

Things worth noticing:
- **No absolute paths.** `info script` finds where the script itself is, so it works on every teammate's PC.
- **New `.v` files need no script edit**, because the whole folder is added.
- **`-force`** lets you rerun it to throw away a broken project and start clean.
- The generated project lands in `hw/vivado/build/`, which must be in `.gitignore`.

---

## 6. How to run a script

**From inside the Vivado GUI:** in the Tcl Console, type

```tcl
cd C:/path/to/lca-tiny-cnn-basys3
source hw/vivado/create_project.tcl
```

Use forward slashes `/` in Tcl paths, even on Windows (a backslash is an escape character in Tcl).

**From a terminal, without opening the GUI ("batch mode"):**

```powershell
F:\Xilinx\2026.1\Vivado\bin\vivado.bat -mode batch -source hw/vivado/create_project.tcl
```

Batch mode is what `run_tests.tcl` is for: run every testbench, print a PASS/FAIL table, exit. The team rule is to run it before every merge to `main`.

After `create_project.tcl` has run once, open `hw/vivado/build/lca_tiny_cnn.xpr` in the GUI and work normally. The script is for (re)creating the project, not a replacement for the GUI.

---

## 7. Learning trick: let Vivado write the Tcl for you

You don't need to memorise commands.

1. **Watch the Tcl Console** while you click. Copy the commands you need.
2. **Read the journal file.** Vivado writes every command of a session to `vivado.jou` in the folder you started it from. Open it in VS Code after a GUI session.
3. **Ask for help on any command:** type `help add_files` or `add_files -help` in the Tcl Console.
4. **`write_project_tcl my_project.tcl`** dumps a whole existing project as a script. The result is long and full of extras, but useful to see how a setting is spelled.

---

## 8. Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Backslashes in paths (`C:\Users\...`) | "no such file", odd characters in the path | Use `/` or `[file join ...]` |
| Relative path in `$readmemh` (`"../../mem/x.mem"`) | Memory reads as all `X` in simulation, no error | Add the `.mem` files to the project and use the bare name |
| Forgetting `wait_on_run` after `launch_runs` | Script continues before synthesis finishes; reports are empty | Always pair `launch_runs` with `wait_on_run` |
| `# comment` after a command on the same line | Strange "wrong # args" errors | Use `;# comment` |
| Committing the `build/` folder | Huge commits, merge conflicts on `.xpr` | Keep it in `.gitignore`, commit only `.tcl` |

---

## Further reading

- Xilinx **UG894**: *Vivado Design Suite User Guide: Using Tcl Scripting*
- Xilinx **UG835**: *Vivado Design Suite Tcl Command Reference Guide* (every command and its options)
- Tcl tutorial: https://www.tcl.tk/man/tcl/tutorial/tcltutorial.html
