# Performance difference of virtual memory addresses
# TLDR:
For optimal perf make sure (JIT) compiled code gets placed close to code of other  (e.g. C compiled) functions it calls.
Where close on amd64 likely means less than 2/4GB difference in addresses.
It seems usage of relative or absolute call instructions can also make some difference on some cpu designs.

# Longer text:
Performance changes depending on which address JIT compiled code gets written to.
It seems like the address difference between two functions is the cause.
On my Intel Alder Lake it seems if the address difference is 2/4GB it will be fast else slow.

I could reproduce this behaviour on the intel cpu but also on 3 different ARM64 cpus (Graviton2, RPi4, M1 Pro)
but the the bahaviour is everywhere a bit different. And the number of times the JIT calls the helper_funcs
seems to make a huge difference.

I wrote a small example which helped me confirm it:
* it JIT compiles a function which calls C functions ('helper_func*')
* helper functions verifies that in the first argument it's address is passed
* this makes sure that the relative and absolute instructions have to execute same number of instructions.
* all the JIT funcs called 'abs_*' use an absolute call instruction:
  1. amd64: `call rdi`
  2. arm64: `blr x0`
* all the JIT funcs called 'rel_*' use a IP relative call instruction:
   amd64: `call <helper_func>` can only address +-2GB
   arm64: `bl <helper_func>`   can only address +-128MB
* I over aligned all the code to make sure I'm not just measuring some alignment issues
* ARM64 version uses exact same number of instructions for rel and abs versions.
* Test programs runs all version twice to confirm perf difference stays the same between runs.
* 'jit code addr' is the addr the code got compiled to
* 'addr of helper_func0' is the addr of the C function which get's called from the JIT code
* 'addr diff in MB' is the difference in MB between the JITs compiled code addr and the helper func
* 'calls jit func makes' how many times should the JIT func call helper_func per? (default 5000)
* `mmap()` allows to pass an address hint if the hint is 0 the kernel decides what to use
  1. this is mostly an address which is far away from 'helper_func'
  2. this is example: "abs_0"
- for all the other examples we specify a hint


Investigation via 'perf record' shows a huge difference in `branch-misses` but also `L1-icache-loads`, `iTLB-load-misses`, `iTLB-loads` on
some CPUs which report this counts.

## Intel i9-12900K - Alder Lake (running on the performance cores)
       calls jit func makes: 5000
       addr of helper_func0:   0x5601480697f0
       jit code size: 160037
       RUN 0:
                     name        jit code addr       addr diff in MB time
                     abs_0       0x7f28850b9000             43152336 643us
                     abs_1M            0x100000             90182783 646us
                     abs_1G          0x40000000             90181760 643us
                     abs_8G         0x200000000             90174592 644us
                     abs_near    0x560148a60000                    9 161us
                     rel_near    0x560148f60000                   14 140us
                     rel_far     0x560188060000                 1023 143us

       RUN 1:
                     name        jit code addr       addr diff in MB time
                     abs_0       0x7f28850b9000             43152336 642us
                     abs_1M            0x100000             90182783 644us
                     abs_1G          0x40000000             90181760 643us
                     abs_8G         0x200000000             90174592 644us
                     abs_near    0x560148a60000                    9 162us
                     rel_near    0x560148f60000                   14 141us
                     rel_far     0x560188060000                 1023 146us



                 branch-misses  iTLB-load-misses
       abs_1G:   165.966.017    9.257.968
       abs_near:     238.122          219
       rel_near:       9.080           66


## Graviton2:
       calls jit func makes: 5000
       addr of helper_func0:   0xaaaac23110d0
       jit code size: 160040
       RUN 0:
                     name        jit code addr       addr diff in MB time
                     abs_0       0xffffa211d000             89476606 740us
                     abs_1M            0x100000            178957346 740us
                     abs_1G          0x40000000            178956323 740us
              abs_outside150M    0xaaaacb910000                  149 740us
              abs_outside300M    0xaaaad4f10000                  299 740us
              abs_outside600M    0xaaaae7b10000                  599 740us
                     abs_near    0xaaaac2d10000                    9 359us
                     rel_near    0xaaaac3210000                   14 445us

       RUN 1:
                     name        jit code addr       addr diff in MB time
                     abs_0       0xffffa211d000             89476606 740us
                     abs_1M            0x100000            178957346 740us
                     abs_1G          0x40000000            178956323 740us
              abs_outside150M    0xaaaacb910000                  149 740us
              abs_outside300M    0xaaaad4f10000                  299 740us
              abs_outside600M    0xaaaae7b10000                  599 740us
                     abs_near    0xaaaac2d10000                    9 360us
                     rel_near    0xaaaac3210000                   14 445us

                 branch-misses  L1-icache-loads L1-icache-load-misses iTLB-loads    iTLB-load-misses
        abs_1G:   158.087.365    2.699.434.935   100.434.669          2.507.726.551 34.711
        rel_near:     128.391    1.104.808.121   100.230.835            905.976.113 17.876


## RPi4:
       calls jit func makes: 5000
       addr of helper_func0:   0xaaaac1dae0d0
       jit code size: 160040
       RUN 0:
                     name        jit code addr       addr diff in MB time
                     abs_0       0xffffbb5ef000             89477016 1979us
                     abs_1M            0x100000            178957340 1976us
                     abs_1G          0x40000000            178956317 1976us
              abs_outside150M    0xaaaacb3a0000                  149 1976us
              abs_outside300M    0xaaaad49a0000                  299 1976us
              abs_outside600M    0xaaaae75a0000                  599 1976us
                     abs_near    0xaaaac27a0000                    9 1834us
                     rel_near    0xaaaac2ca0000                   14 1306us

       RUN 1:
                     name        jit code addr       addr diff in MB time
                     abs_0       0xffffbb5ef000             89477016 1976us
                     abs_1M            0x100000            178957340 1976us
                     abs_1G          0x40000000            178956317 1975us
              abs_outside150M    0xaaaacb3a0000                  149 1976us
              abs_outside300M    0xaaaad49a0000                  299 1976us
              abs_outside600M    0xaaaae75a0000                  599 1976us
                     abs_near    0xaaaac27a0000                    9 1857us
                     rel_near    0xaaaac2ca0000                   14 1315us


perf record:
                   branch-misses    L1-icache-loads   L1-icache-load-misses
       abs_1G:     200.400.435      4.704.634.583     100.969.622
       abs_near:   180.973.425      4.314.797.705     101.030.718
       rel_near:       205.237      1.610.071.312     100.559.260

