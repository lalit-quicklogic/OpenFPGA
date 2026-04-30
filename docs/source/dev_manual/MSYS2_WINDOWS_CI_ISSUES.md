# MSYS2/MinGW64 Windows CI — Known Issues & Status Tracker

**Target**: Enable regression tests on Windows (MSYS2 MinGW64) matching the
Linux CI regression suite, for upstream PR to [lnis-uofu/OpenFPGA#2382](https://github.com/lnis-uofu/OpenFPGA/issues/2382).

**Branch**: `openfpga-msys2-ci-build` on `lalit-quicklogic/OpenFPGA`

---

## Build Issues (All Resolved)

| # | Issue | Root Cause | Fix | Status |
|---|-------|-----------|-----|--------|
| B1 | CaDiCaL `getc_unlocked`/`putc_unlocked` missing | POSIX functions not available on MinGW | `-DWIN32` in `ARCHFLAGS` | ✅ Fixed |
| B2 | ABC linker "Argument list too long" | Windows command-line length limit exceeded | Response file `@abc_link.rsp` for LD | ✅ Fixed |
| B3 | `-ldl` / `-lrt` not found | These libraries don't exist on Windows | `-DWITH_ABC=OFF` (matches MSVC CI) | ✅ Fixed |
| B4 | `struct timespec` / `-fpermissive` errors in VTR ABC | ABC code not compatible with MinGW | `-DWITH_ABC=OFF` eliminates VTR's ABC | ✅ Fixed |
| B5 | `FlexLexer.h` not found | MSYS2 `flex` installs to `/usr/include/` but MinGW compiler searches `/mingw64/include/` | Copy `FlexLexer.h` to `/mingw64/include/` | ✅ Fixed |
| B6 | yosys-slang PE/COFF export limit | Windows PE/COFF format limits exports to 65535; slang shared library exceeds this | `if(NOT WIN32)` guard in CMakeLists.txt | ✅ Fixed |
| B7 | `yosys-config` is a bash script, CMake can't execute | `FindYosys.cmake` uses `execute_process(COMMAND yosys-config ...)` which fails on Windows | `sed` patch to prefix `bash` | ✅ Fixed |
| B8 | argparse `otherthings` eating values | Stray positional args after `--` keys consumed by argparse | Merge fix in `run_fpga_flow.py` `__main__` | ✅ Fixed |

## Regression Test Issues

### R1 — Artifact `build/` prefix stripped by `upload-artifact@v4` ✅ FIXED

**Symptom**: `find: '/d/a/OpenFPGA/OpenFPGA/build': No such file or directory`
in every regression test. All tool binaries missing.

**Root Cause**: `actions/upload-artifact@v4` computes the least common ancestor
(LCA) of all specified paths and strips it. Since every upload path started with
`build/` (`build/openfpga/`, `build/yosys/`, `build/vtr-verilog-to-routing/...`),
the LCA was `build/`, so files were stored **without** the `build/` prefix.
When `download-artifact@v4` extracted to the workspace root, the `build/`
directory was never created.

The Linux CI doesn't hit this because its upload also includes root-level paths
(`openfpga_flow`, `openfpga.sh`), making the LCA the workspace root and
preserving `build/`.

**Fix**: Specify `path: build` in `download-artifact` steps to restore the
expected directory layout.

### R2 — Yosys binary not found (`FileNotFoundError`) 🔍 INVESTIGATING

**Symptom**: `FileNotFoundError: [WinError 2] The system cannot find the file
specified` when `run_fpga_flow.py` tries to execute yosys (first tool in the
`yosys_vpr` flow).

**Suspected Causes**:
- Yosys may have failed to build silently under `make -k` (the `-k` flag
  continues past errors; the build job still reports success)
- The yosys binary may be at an unexpected path after `make install`
- The `.exe` extension handling may be incomplete

**Diagnostics Added**:
- `run_command()` in `run_fpga_flow.py` now logs the exact executable path and
  lists the parent directory if the binary is not found
- `basic_reg_test_win.sh` prints a binary presence check before running tasks
- CI "Verify artifact layout" step checks for specific binaries with sizes

**Next Steps**: Wait for next CI run diagnostics to confirm exact missing file.

### R3 — iverilog verification fails on Windows 🚧 WORKAROUND APPLIED

**Symptom**: `Preprocessor failed with 1 errors` when iverilog tries to compile
the generated Verilog netlists.

**Root Cause**: OpenFPGA's `write_fabric_verilog` generates Verilog files
containing `` `include `` directives with file paths. These paths are derived
from `OPENFPGA_PATH`, which on MSYS2 is an MSYS2-virtual path
(e.g., `/d/a/OpenFPGA/OpenFPGA/openfpga_flow/...`).

The MSYS2 automatic path translation (`/d/a/...` → `D:\a\...`) only applies
to **command-line arguments** passed through the MSYS2 shell. It does **not**
translate paths embedded inside generated files.  When the OpenFPGA binary
(a native MinGW executable) writes a path like `/d/a/OpenFPGA/...` into a
Verilog file, iverilog (also a native binary) reads it literally and cannot
resolve the MSYS2-virtual path.

**Example** — generated `fabric_netlists.v`:
```verilog
`include "/d/a/OpenFPGA/OpenFPGA/openfpga_flow/openfpga_cell_library/verilog/dff.v"
```
iverilog preprocessor cannot open `/d/a/...` on native Windows → failure.

**Workaround**: Skip `run_netlists_verification()` on `sys.platform == "win32"`
in `run_fpga_flow.py`. The fabric generation and bitstream flow still execute
correctly; only the post-flow simulation verification step is skipped.

**Proper Fix** (future): Normalize paths to native Windows format
(`D:/a/OpenFPGA/...`) in OpenFPGA's C++ code when generating Verilog output.
This is a cross-cutting concern across multiple source files that construct
include paths for generated Verilog.

### R4 — `ps: unknown option -- o` warnings ⚠️ COSMETIC

**Symptom**: `openfpga.sh` sources shell functions that call `ps -o` which is
not supported by the MSYS2 `ps` command.

**Impact**: Harmless warning messages in CI logs. No functional impact.

### R5 — `os.path.islink("latest")` on Windows ⚠️ FIXED

**Symptom**: `run_fpga_task.py` called `os.path.islink("latest")` which could
raise exceptions on Windows where symlinks behave differently.

**Fix**: Changed to `os.path.islink` guard (already applied).

### R6 — Absolute path prefix `/` on Windows 🔧 FIXED

**Symptom**: `run_fpga_task.py` prepends `/` to task paths on all platforms,
which on Windows resolves to the drive root (e.g., `C:\`).

**Fix**: Added `sys.platform == "win32"` guard to use `os.path.abspath()` only.

## Architecture Decisions

### Why `-DWITH_ABC=OFF`?

Both the existing MSVC CI (`win_build`) and the Aurora2 Windows build use
`-DWITH_ABC=OFF`. VTR's bundled ABC has extensive POSIX dependencies
(`-ldl`, `-lrt`, `fork()`, `getrusage()`) that are not available on Windows.
Yosys builds its own ABC copy with the `msys2-64` / patched-`gcc` config that
handles these portability issues.

### Why `-DOPENFPGA_WITH_SWIG=OFF`?

SWIG-generated Python bindings have build issues on MinGW. Both MSVC CI and
Aurora2 disable this. The core OpenFPGA functionality is not affected.

### Why skip yosys-slang on Windows?

The slang shared library exceeds the PE/COFF 65535 exported-symbol limit.
This is a fundamental limitation of the Windows executable format. yosys-slang
provides SystemVerilog support via the `read_slang` command, which is not
required for the core regression tests.

## Reference: Aurora2 Approach

Aurora2 (QuickLogic's fork) uses a **hotfix overlay** system for Windows builds:
- `CONFIG=msys2-64` equivalent for Yosys Makefile
- `WITH_ABC=OFF`, `OPENFPGA_WITH_SWIG=OFF`
- Does **not** run OpenFPGA regression tests on Windows — only basic batch
  commands like `aurora --batch --cmd "list_devices"`
- Uses `EXE = .exe` and Windows-specific linker flags

---

*Last updated: 2026-04-30*
