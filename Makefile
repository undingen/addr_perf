build:
	luajit LuaJIT/dynasm/dynasm.lua -D `uname -m` -o addr_perf.gen.c addr_perf.dasc
	gcc -g -O3 -o addr_perf *.c

PERF:=perf stat -ddd -e branch-misses
TIMES:=5000

perf: build
	$(PERF) ./addr_perf $(TIMES) abs_0
	$(PERF) ./addr_perf $(TIMES) abs_1M
	$(PERF) ./addr_perf $(TIMES) abs_1G
	$(PERF) ./addr_perf $(TIMES) abs_near
	$(PERF) ./addr_perf $(TIMES) rel_near


