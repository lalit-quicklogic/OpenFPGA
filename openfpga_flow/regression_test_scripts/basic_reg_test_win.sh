#!/bin/bash
# Windows (MSYS2) variant of basic_reg_test.sh
# Skips tests that depend on iverilog verification (end_flow_with_test),
# which requires Unix-style include paths in the generated Verilog netlists.

set -e
source openfpga.sh
###############################################
# OpenFPGA Shell with VPR8 — Windows subset
##############################################
echo -e "Basic regression tests (Windows)";

echo -e "=== Diagnostic: checking tool binaries ==="
for bin in build/openfpga/openfpga build/yosys/bin/yosys build/vtr-verilog-to-routing/vpr/vpr; do
  for ext in "" ".exe"; do
    p="${OPENFPGA_PATH}/${bin}${ext}"
    if [ -e "$p" ]; then
      echo "  FOUND: $p"
    else
      echo "  missing: $p"
    fi
  done
done
echo -e "============================================"

echo -e "Check if openfpgashell can execute commands with -x option"
OPENFPGA_SHELL_BIN="${OPENFPGA_PATH}/build/openfpga/openfpga"
if [ ! -e "${OPENFPGA_SHELL_BIN}" ] && [ -e "${OPENFPGA_SHELL_BIN}.exe" ]; then
  OPENFPGA_SHELL_BIN="${OPENFPGA_SHELL_BIN}.exe"
fi

if [ -z "${OPENFPGA_SHELL_BIN}" ] || [ ! -e "${OPENFPGA_SHELL_BIN}" ]; then
  echo "Error: Cannot locate openfpga executable under ${OPENFPGA_PATH}/build"
  ls -la "${OPENFPGA_PATH}/build/openfpga/" 2>/dev/null || echo "build/openfpga/ does not exist"
  exit 1
fi

${OPENFPGA_SHELL_BIN} -x "version; exit;"
if [ $? -ne 0 ]; then
  echo "Error: openfpgashell execution with -x option failed"
  exit 1
fi

# NOTE: vpr_standalone skipped — requires end_flow_with_test (iverilog)
# NOTE: source_command tests skipped — require end_flow_with_test (iverilog)
# NOTE: full_testbench tests skipped — require end_flow_with_test (iverilog)

echo -e "Testing preloading rr_graph"
run-task basic_tests/preload_rr_graph/preload_rr_graph_xml $@
run-task basic_tests/preload_rr_graph/preload_rr_graph_bin $@

echo -e "Testing preloading unique blocks"
run-task basic_tests/preload_unique_blocks/write_unique_blocks_full_flow $@
run-task basic_tests/preload_unique_blocks/read_unique_blocks_full_flow $@
run-task basic_tests/preload_unique_blocks/read_write_unique_blocks $@
run-task basic_tests/preload_unique_blocks/read_write_unique_blocks_bin $@
