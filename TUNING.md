# Measured on the Framework 13 (Ryzen 5 7640U / Radeon 760M), Arch/Omarchy

Answers the BRIEF's "verify before choosing anything". Date: 2026-08-25.

## Memory: the 4 GB BIOS carve-out is NOT the ceiling

    Vulkan0: AMD Radeon 760M Graphics (RADV PHOENIX) (18025 MiB, 17126 MiB free)

18,025 MiB = 4096 (BIOS UMA carve-out, "Gaming") + 13,929 (GTT). llama.cpp/Vulkan
treats VRAM+GTT as one pool.

- `mem_info_vram_total` = 4096 MiB   (BIOS; Framework BIOS 3.09 offers only Auto/Gaming, no manual size)
- `mem_info_gtt_total`  = 13929 MiB  (kernel: ttm.pages_limit, raisable via amdgpu.gttsize)

**Leave the BIOS on Gaming.** Auto would free ~3.4 GiB of system RAM but shrink the
GPU-addressable pool. Nothing on the shortlist needs the extra system RAM.
If a model >17.6 GiB must be fully resident, raise GTT on the kernel cmdline —
not in the BIOS.

## Backend: Vulkan wins prefill, barely wins decode

Qwen3-4B-Instruct-2507 Q4_K_M, llama-bench b10630, 3 reps, AC power.

| Config | pp512 | pp2048 | tg128 |
|---|---|---|---|
| Vulkan GPU (-ngl 99)      | 504.36 | 446.55 | 29.16 |
| CPU portable AVX2 (-dev none) | 97.19 | 83.70 | 20.12 |
| CPU -march=native AVX-512 | 101.15 | 86.14 | 20.19 |

- **Prefill: GPU ~5x faster.** Compute-bound; the 8 RDNA3 CUs matter.
- **Decode: GPU only 1.44x faster.** Bandwidth-bound — same LPDDR5x either way.

Prefill is the metric that matters for agent work: opencode-style prompts are
9-12k tokens and are re-sent every turn, so TTFT ~= prompt_tokens / prefill_rate.

## -march=native is not worth it

+4.1% prefill, +0.3% decode over the portable build, despite AVX-512 verifiably
compiled in (10,755 zmm instructions in libggml-cpu.so). ggml already does runtime
CPU feature dispatch. **Use the distro packages; don't maintain a source build.**

## Harness trap

`-ngl 0` is NOT a CPU baseline when the Vulkan backend is registered — ggml still
offloads large prefill matmuls, giving a fake 328 t/s "CPU" prefill number.
Use `-dev none`.

## Install used

Root-free, pending pacman: prebuilt b10630 Vulkan at ~/.local/opt/llama-b10630-vulkan/.
Preferred once root is available:

    sudo pacman -S --needed llama-cpp ggml-vulkan ggml-cpu vulkan-tools radeontop

## Model residency (measured, peak VRAM+GTT under load)

| Model | Config | Peak | Result |
|---|---|---|---|
| Qwen3-4B Q4_K_M | -ngl 99 | (small) | OK  pp512 504 / pp2048 447 / tg128 29.2 |
| gpt-oss-20b MXFP4 | -ngl 99 -fa 1 -ctk/v q8_0 | 12390 MiB | OK  pp2048 341 / pp9216 286 / tg128 27.6 |
| Qwen3-Coder-30B Q4_K_M | -ngl 99, f16 KV | 18012 MiB | OOM |
| Qwen3-Coder-30B Q4_K_M | -ngl 99, q8_0 KV | 17046 MiB | OOM |
| Qwen3-Coder-30B Q4_K_M | -ncmoe 12 / 24 | 17679 / 17864 | OOM |
| Qwen3-Coder-30B Q4_K_M | -ngl 36 | 17141 MiB | OOM |
| Qwen3-Coder-30B Q4_K_M | -ngl 24 | 18011 MiB | **GPU device lost (core dump)** |

Error in all OOM cases: `radv/amdgpu: Not enough memory for command submission.`

### Partial offload does NOT work on this UMA iGPU

Counter-intuitive and important: lowering `-ngl` did **not** reduce GPU memory.
`-ngl 24` peaked HIGHER (18011) than `-ngl 36` (17141), and hung the GPU.
llama.cpp reports `uma: 1` — host memory is GPU-visible, so layers "kept on CPU"
still occupy the same pool, while adding transfer overhead.

**Rule for this machine: a model either fits at `-ngl 99` or you don't run it on
the GPU at all.** Do not tune `-ngl` downward; do not rely on `-ncmoe`.

Practical ceiling at the stock 13.9 GiB GTT: **~12-13 GiB of weights.**
GPU recovered fine from the device-lost (no kernel reset logged).

## Runtime headroom is large — nominal pool size is NOT usable weight size

| Model | Weights | Peak | Result |
|---|---|---|---|
| gpt-oss-20b MXFP4 | 11,540 MiB | 12,390 | OK, stable |
| GLM-4.7-Flash Q4_K_M | 17,295 MiB | 18,015 | **device lost (core dump)** |
| Qwen3-Coder-30B Q4_K_M | 17,766 MiB | 18,012 | OOM |

730 MiB of nominal headroom is NOT enough. Two separate GPU device-losses came
from running near the pool limit. Budget several GiB of slack above the weights.

## ttm.pages_limit CANNOT be raised at runtime (usefully)

Writing /sys/module/ttm/parameters/pages_limit succeeds and the file reads back
the new value, but `mem_info_gtt_total` and the Vulkan heap sizes do NOT change --
amdgpu computes its GTT size at module load. Raising the ceiling requires a
kernel cmdline change + reboot. There is no zero-reboot validation path.

## pacman vs upstream prebuilt: identical performance

Qwen3-4B, -ngl 99 -fa 1 -ctk/v q8_0: pacman build pp2048 426.43 / tg128 28.89
vs prebuilt b10630 pp2048 446.55 (f16 KV) / tg128 29.16. Use the distro packages.

## POST-REBOOT (GTT 19456 MiB, pool 23552 MiB) — 2026-08-26

Kernel cmdline `amdgpu.gttsize=19456 ttm.pages_limit=4980736` applied cleanly.
llama.cpp reports `Vulkan0: ... (23552 MiB, 22970 MiB free)`. The 30B now loads.

### Fair comparison, both at d16384 (equal KV depth)

| | Qwen3-Coder-30B A3B | gpt-oss-20b MXFP4 |
|---|---|---|
| pp2048       | 84.01  | **192.15** |
| pp9216       | 68.64  | **169.49** |
| tg128        | 19.10  | **23.19**  |
| weights      | 17.35 GiB | **11.27 GiB** |
| peak (16k)   | 20074 MiB | 12390 MiB |
| OS free, steady @16k | 8.7 GiB | **~14 GiB** |
| TTFT on 9.2k prompt  | ~134 s | **~54 s** |

**gpt-oss-20b wins on every axis, 2.5x on prefill.** Old sweep's capability proxy
rates them near-equal (eff. params 9.5B vs 8.5B), so the 30B buys little for the cost.

**Recommendation: gpt-oss-20b is the default for both general and agentic use.**
Keep the 30B for batch/offline coding only. NOT settled here: code QUALITY —
the 30B is code-tuned, gpt-oss-20b is general. Judge that by use, not by these numbers.

Keep the raised GTT regardless: it is a cap, not a reservation (idle GTT use ~60 MiB).

### Estimation error worth remembering

Predicted OS-free at 16k was ~10.4 GiB; actual steady state is 8.7 GiB and the
LOAD TRANSIENT dips to 7.4 GiB (32k dips to 3.9 GiB). Arithmetic from GTT ceiling
vs visible RAM ignores page-cache pressure from reading the GGUF and transient
allocation during load. Measure steady state AND the transient; do not extrapolate.

### Arch package caveat

`/usr/bin/llama-bench` prints `warning: asserts enabled, performance may be affected`.
Arch's llama-cpp ships with assertions on — likely part of the ~5% prefill gap vs the
upstream prebuilt. Not chased; a source build without asserts may recover a few percent.

### llama-bench flags

No `-c`. Use `-d/--n-depth` to simulate a filled KV cache. Also has `-fitt/--fit-target`
to auto-fit a model to device memory with a margin.

## Serving: tool calls + prompt cache (gpt-oss-20b @131k, port 8090)

Agent-shaped probe, ~10k-token system prompt with one tool schema:

| | wall | prompt_tokens | tool call |
|---|---|---|---|
| cold   | 35.68 s | 9944 | `list_files {"path":"."}` |
| warm 1 |  1.97 s | 9945 | `list_files {"path":"src"}` |
| warm 2 |  2.04 s | 9945 | `list_files {"path":"docs"}` |

**18x speedup; steady-state turn cost ~2 s.** Tool calls emit correctly with correct
arguments both cold and warm. This is the number that makes local agent use viable —
the 35 s cold prefill is paid once per session, not per message.

Launch flags that matter: `-np 1` (slots divide the KV budget) and `--cache-reuse 256`.

## Context sizing, gpt-oss-20b (measured steady state)

| ctx | total GPU | OS free |
|---|---|---|
| 32768  | 12944 MiB | 14.8 GiB |
| 65536  | 13444 MiB | 14.2 GiB |
| 131072 | 14389 MiB | **13.7 GiB** |

KV is cheap on this model — 32k->131k costs only 1.4 GiB. Run it at full 131k.

## Vision: gemma-4-12B-it-QAT works, but needs --jinja

Peak 9766 MiB @8k ctx. Without `--jinja` llama.cpp aborts:
`terminate called ... what(): this custom template is not supported, try using --jinja`
(that abort is what produced the third coredump and the Omarchy crash notification).

Accuracy on a controlled test image: read all four text strings verbatim, identified
all four colours correctly, counted three shapes correctly. Works over the HTTP API
too (35.8 s, 344 completion tokens).

**gemma-4 is a THINKING model.** Reasoning lands in `reasoning_content`, the answer in
`content`. At `max_tokens=300` it returned `finish_reason: length` with `content: ''`
— indistinguishable from a broken server. Needs `max_tokens >= 1000`.

## The three previously-untested models (2026-08-26) — none displace the defaults

Same controlled test image as the gemma-4 run (four text strings, three red circles).

| Model | Peak | Wall | Result |
|---|---|---|---|
| gemma-4-12B-it-QAT (incumbent) | 9766 MiB | ~36 s | all text verbatim, 3 circles, colours right |
| GLM-4.6V-Flash Q4_K_M | 9823 MiB | 34 s | text correct — but ALSO a thinking model (`<think>`) |
| Bonsai-27B **Q1_0** | 7071 MiB | 53 s | **misread "GTT" as "GT"** — slower AND wrong |

NOTE: the table above is a SINGLE trial per model. Single trials are NOT sufficient to
rank models — see the 3-trial results immediately below, which overturned the
conclusion I first drew from it.

### 3-trial comparison — ALL THREE PASS

Three distinct tasks per model (varied input, since --temp 0 makes repeats identical):
T1 transcribe 4 strings + count 3 circles; T2 targeted extraction ("what follows GTT =");
T3 a second, unseen image (invoice number, money, ISO date, 2 squares + 1 triangle).

| Model | T1 | T2 | T3 | Peak | Wall/query |
|---|---|---|---|---|---|
| gemma-4-12B-it-QAT | PASS | PASS | PASS | 9766 MiB | ~36 s |
| GLM-4.6V-Flash Q4_K_M | PASS | PASS | PASS | 9823 MiB | ~34 s |
| Bonsai-27B **Q1_0** | PASS | PASS | PASS | 7071 MiB | ~53 s |

**Accuracy does not separate them on these tasks.** Bonsai's single-trial "GT" slip was
a label typo — it read the VALUE (19456 MiB) correctly then and on targeted extraction.
Q1_0 is not obviously broken here, contrary to my first call.

**All three are thinking models** (`<channel|>`, `</think>` markers in raw output), so the
~35 s per-query cost is inherent to this class, not a gemma-4 quirk. Budget
`max_tokens >= 1000` for any of them.

**Choose on footprint/speed, not accuracy:** gemma-4 and GLM-4.6V are near-identical
(~9.8 GiB, ~35 s); Bonsai is 2.7 GiB smaller but ~50% slower. `gemma-4-12B-it-QAT` stays
gemma-4 by default — an arbitrary tie-break between it and GLM-4.6V, not a measured win.

**Method note:** one trial is not evidence. Vary the input rather than repeating at
--temp 0, which just reproduces the same output.

### Qwen3-14B Q4_K_M (text) — slowest of everything tested

Peak 11568 MiB. At d16384: **pp2048 61.94, tg128 6.70** — 3.1x slower prefill and
3.5x slower decode than gpt-oss-20b, and it is a thinking model on top (prior Debian
sweep: 3.05x think ratio, 249 s TTFT at 32k). Two independent measurements agree.
No reason to run it here.
