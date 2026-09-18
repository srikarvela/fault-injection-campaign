# fault-injection-campaign (D1) master Makefile
#
#   make build      compile both DUT variants (Icarus): baseline + hardened
#   make campaign   run the full sweep for both variants -> results/*/results.csv
#   make heatmaps   render docs/heatmap_<variant>.svg from the results
#   make all        build + campaign + heatmaps
#   make demo       one visible instruction-skip bypass on the baseline DUT
#   make clean
#
# Prototype flow is Icarus (force/release is trivial); the guide's next step is
# a Verilator port once the sweep is large enough for Icarus to hurt.

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
IVFLAGS   = -g2012 -Wno-timescale
DUT       = rtl/secure_check.sv
TB        = tb/tb_fault.sv

.PHONY: all build campaign heatmaps demo clean
all: build campaign heatmaps

build: build/dut_baseline.vvp build/dut_hardened.vvp
build/dut_baseline.vvp: $(DUT) $(TB)
	@mkdir -p build
	$(IVERILOG) $(IVFLAGS) -Ptb_fault.HARDEN_P=0 -o $@ $(DUT) $(TB)
build/dut_hardened.vvp: $(DUT) $(TB)
	@mkdir -p build
	$(IVERILOG) $(IVFLAGS) -Ptb_fault.HARDEN_P=1 -o $@ $(DUT) $(TB)

campaign: build
	$(PYTHON) campaign/run_campaign.py both

heatmaps:
	$(PYTHON) campaign/heatmap.py baseline hardened

demo: build/dut_baseline.vvp
	@echo "no fault (correct refusal):"; $(VVP) -N build/dut_baseline.vvp +ftype=none | grep RESULT
	@echo "single instruction skip -> tampered image BOOTS:"; \
	 $(VVP) -N build/dut_baseline.vvp +ftype=skip +fcycle=3 +ftarget=ir | grep RESULT

clean:
	rm -rf build __pycache__ campaign/__pycache__
