# Benchmarks

This is a standalone package that benchmarks `Decimal128` using
[ordo-one/benchmark](https://github.com/ordo-one/benchmark).
It depends on `DecimalCore` by path and with the `Macros` trait disabled,
so it builds without swift-syntax and doesn't change the main package.

## Running

```sh
cd Benchmarks
swift package benchmark
```

To compare two states of the library, store a baseline and compare against it:

```sh
swift package --allow-writing-to-package-directory benchmark \
  baseline update before
# ...change the library...
swift package benchmark baseline compare before
```

`--filter` takes a regular expression that must match the whole benchmark name,
e.g. `--filter 'Divide.*'`.

## Operands

Each benchmark runs over a fixed pool of 65536 operands generated from a
seeded generator, so every run with the same Swift toolchain uses the same
values:

- *Everyday* operands have two decimal places, with 1 to 8 digits
  (`0.01` through `999999.99`); half of them are negative.
- *Wide* operands, in rows marked `(wide)`, have 1 to 34 significant digits and
  exponents from -30 through 10; half of them are negative.

The pools are a fixed synthetic distribution. Cycling through many operands,
rather than repeating one, makes the measured code take its branches with a
varied mix; with pools of a few thousand operands, branch predictors were seen
to learn the sequence, making data-dependent operations such as division and
comparison measure considerably faster. The operations are independent of
each other, so the results measure throughput rather than the latency of a
dependent chain.

The `Foundation` rows run the same everyday operands through
`Foundation.Decimal` for comparison.

## Reading the results

Each benchmark iteration processes the next 4096 operands of the pool, so the
reported wall clock and instruction counts are for **4096 operations**. Divide
them by 4096 for per-operation figures with sub-nanosecond resolution. Keeping
iterations this short makes the median robust against preemption on machines
that aren't otherwise idle.
`Scripts/summarize.py` does this for results exported with
`--format histogramPercentiles`:

```sh
swift package --allow-writing-to-directory /tmp/results benchmark \
  --format histogramPercentiles --path /tmp/results/before
# ...change the library and export to /tmp/results/after...
python3 Scripts/summarize.py /tmp/results/before /tmp/results/after
```

It prints the median nanoseconds and instructions per operation and, given two
directories, the change between them.

The `Loop overhead` row measures the loop and passing an operand to `blackHole`
alone, as a rough reference for the measurement overhead included in the other
rows.

On Linux, instruction counts need access to hardware performance counters (see
`perf_event_paranoid`); without it, only wall clock is reported.
