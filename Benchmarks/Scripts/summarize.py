"""Summarize benchmark results as median nanoseconds and instructions per
operation.

Each benchmark iteration processes a batch of operations (see `batchSize` in
DecimalBenchmarks.swift), so the per-iteration values that
`swift package benchmark --format histogramPercentiles` exports are divided by
the batch size.

Usage: python3 Scripts/summarize.py DIRECTORY [DIRECTORY]

With two directories, the second column pair is compared with the first.
"""

import glob
import os
import re
import sys

BATCH_SIZE = 4096
METRICS = ("wallClock", "instructions")


def load(directory):
    """Returns {benchmark name: {metric: median value per operation}}."""
    pattern = os.path.join(directory, "*.histogram.percentiles.tsv")
    paths = glob.glob(pattern)
    if not paths:
        sys.exit("No exported results in %s" % directory)
    results = {}
    for path in paths:
        match = re.match(
            r"(.+?)\.DecimalBenchmarks\.(.+)\.(\w+)\.histogram\.percentiles"
            r"\.tsv$",
            os.path.basename(path))
        if not match or match.group(3) not in METRICS:
            continue
        # Exported file names have underscores in place of spaces.
        name = match.group(2).replace("_", " ")
        metric = match.group(3)
        if metric in results.get(name, {}):
            sys.exit("More than one export of %s in %s (more than one "
                     "baseline?)" % (name, directory))
        with open(path) as file:
            header = next(file)
            if metric == "wallClock" and "(ns)" not in header:
                sys.exit("Expected wall clock in nanoseconds in %s" % path)
            for line in file:
                percentile, value = line.split("\t")
                if percentile == "50":
                    results.setdefault(name, {})[metric] = (
                        int(value) / BATCH_SIZE)
    return results


def cell(value, format):
    return format % value if value is not None else "-"


def change(before, after):
    if not before or after is None:
        return "-"
    return "%+.1f%%" % (100 * (after / before - 1))


def main(directories):
    data = [load(directory) for directory in directories]
    labels = [os.path.basename(d.rstrip("/")) for d in directories]
    header = ["Operation"]
    for label in labels:
        header += ["ns " + label, "instructions " + label]
    if len(data) == 2:
        header += ["change in ns", "change in instructions"]
    print("| " + " | ".join(header) + " |")
    print("|---" + "|---:" * (len(header) - 1) + "|")
    names = sorted(set().union(*data),
                   key=lambda n: (n.startswith("Foundation"), "(wide)" in n, n))
    for name in names:
        rows = [d.get(name, {}) for d in data]
        cells = [name]
        for row in rows:
            cells += [cell(row.get("wallClock"), "%.2f"),
                      cell(row.get("instructions"), "%.0f")]
        if len(rows) == 2:
            cells += [change(rows[0].get(m), rows[1].get(m)) for m in METRICS]
        print("| " + " | ".join(cells) + " |")


if __name__ == "__main__":
    if not 1 <= len(sys.argv) - 1 <= 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
