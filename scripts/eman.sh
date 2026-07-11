#!/bin/bash

set -e

help() {
    cat <<EOF

Welcome to use the Docker Workspace for AOC.
You can type 'eman' anywhere in the container to see this message.

Available commands:

  eman help                      : show this help message

  eman c-compiler-version        : print the version of default C compiler and the version of GNU Make
  eman c-compiler-example        : compile and run the C/C++ example(s)
  
  eman systemc-example           : compile and run the SystemC example(s)
  
  eman verilator-version         : print the version of the first found Verilator
  eman verilator-example         : compile and run the Verilator example(s)
  
  eman uv-ersion                 : print uv, uvx version
  
  eman python-version            : print Python version

  eman check-all                 : check all tools and packages versions
EOF
}

c_compiler_version() {
    echo "[C Compiler Version]"
    gcc --version | head -n 1
    echo "[Make Version]"
    make --version | head -n 1
}

c_compiler_example() {
    echo "[C Compiler Example]"
    local TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT
    
    # Create main.c
    cat > "$TMPDIR/main.c" << 'CEOF'
#include <stdio.h>

int main() {
    int arr[2][3][4] = {
        {
            {1, 2, 3, 4}, 
            {5, 6, 7, 8}, 
            {9, 10, 11, 12}
        },
        {
            {13, 14, 15, 16}, 
            {17, 18, 19, 20}, 
            {21, 22, 23, 24}
        }
    };
    
    int *ptr = (int*)arr;
    
    printf("-----  print out  ----- \n");
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 3; j++) {
            for (int k = 0; k < 4; k++) {
                int idx = i*12 + j*4 + k;
                printf("addr: %p , value: %d\n", &arr[idx], *(ptr + idx));
            }
        }
    }
}
CEOF

    # Compile and run
    cd "$TMPDIR"
    gcc -Wall -Wextra -O2 -o main main.c
    ./main
}

systemc_example() {
    echo "[SystemC Example]"
    local TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT
    
    # Create main.c
    cat > "$TMPDIR/main.cpp" << 'SYSCEOF'
#include <systemc>
int sc_main(int argc, char* argv[]) { return 0; }
SYSCEOF

    # Compile and run
    cd "$TMPDIR"
    g++ -std=c++17 main.cpp -o main -I. -I${SYSTEMC_HOME}/include \
        -L${SYSTEMC_HOME}/lib-linux64 \
        -Wl,-rpath,${SYSTEMC_HOME}/lib-linux64 \
        -lsystemc -lm
    ./main
}

check_verilator() {
    echo "[Verilator Version]"
    if ! command -v verilator >/dev/null 2>&1; then
        echo "Verilator not found!"
        exit 1
    fi
    verilator --version
}

verilator_example() {
    echo "[Verilator Example]"
    local TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT
    
    # Create Counter.v
    cat > "$TMPDIR/Counter.v" << 'VEOF'
module Counter(
    input clk,
    input rst,
    input [8:0] max,
    output reg [8:0] out
);
    reg [8:0] cnt;

    always @(posedge clk, posedge rst) begin
        if (rst) cnt <= max;
        else if (cnt == 0) cnt <= max;
        else cnt <= cnt - 1;
    end

    always @(*) out = cnt;

endmodule
VEOF

    # Create testbench.cc
    cat > "$TMPDIR/testbench.cc" << 'CPPEOF'
#include <iostream>

#include "VCounter.h"
#include "verilated_vcd_c.h"

int main() {
  Verilated::traceEverOn(true);
  VerilatedVcdC* fp = new VerilatedVcdC();

  auto dut = new VCounter;
  dut->trace(fp, 0);
  fp->open("wave.vcd");

  int clk = 0;
  const int maxclk = 10;

  dut->rst = 1;
  dut->max = 9;
  dut->clk = 1;
  dut->eval();
  fp->dump(clk++);

  dut->rst = 0;
  while (clk < maxclk << 1) {
    // falling edge
    dut->clk = 0;
    dut->eval();
    fp->dump(clk++);

    // rising edge
    dut->clk = 1;
    dut->eval();
    fp->dump(clk++);
    std::cout << "count: " << dut->out << std::endl;
  }

  fp->close();
  dut->final();
  delete dut;
  return 0;
}
CPPEOF

    # Compile and run
    cd "$TMPDIR"
    verilator -Wall --cc --exe --build --trace Counter.v testbench.cc
    ./obj_dir/VCounter
}

uv_version() {
    echo "[uv Version]"
    if ! command -v uv >/dev/null 2>&1; then
        echo "uv not found!"
        exit 1
    fi
    uv --version

    echo "[uvx Version]"
    if ! command -v uvx >/dev/null 2>&1; then
        echo "uvx not found!"
        exit 1
    fi
    uvx --version
}

python_version() {
    echo "[Python Version]"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Python3 not found!"
        exit 1
    fi
    python3 --version
    echo "[Pip Version]"
    if ! command -v pip3 >/dev/null 2>&1; then
        echo "Pip3 not found!"
        exit 1
    fi
    pip3 --version
}

check_all() {
    local FAILED=false

    echo "=== Environment Check - All Tools ==="
    echo ""
    (c_compiler_version) || FAILED=true
    echo ""
    (check_verilator) || FAILED=true
    echo ""
    (uv_version) || FAILED=true
    echo ""
    (python_version) || FAILED=true
    echo ""
    echo "=== Compilation Check - C , SystemC, Verilator ==="
    echo ""
    (c_compiler_example) || FAILED=true
    echo ""
    (systemc_example) || FAILED=true
    echo ""
    (verilator_example) || FAILED=true
    echo ""
    echo "=== All checks completed ==="
    echo ""

    if [ "$FAILED" = "false" ]; then
        echo "Environment setup complete!"
    fi
}


# === Main Dispatcher ===
case "$1" in
    help|"")
        help
        ;;
    c-compiler-version)
        c_compiler_version
        ;;
    c-compiler-example)
        c_compiler_example
        ;;
    systemc-example)
        systemc_example
        ;;
    verilator-version)
        check_verilator
        ;;
    verilator-example)
        verilator_example
        ;;
    uv-version)
        uv_version
        ;;
    python-version)
        python_version
        ;;
    check-all)
        check_all
        ;;
    *)
        echo "Unknown command: $1"
        help
        exit 1
        ;;
esac
