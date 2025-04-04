# FoundationDB, RocksDB Simulation Tester (FRoST)

FoundationDB is one of the progenitors of deterministic simulation testing (DST). Here we evaluate DST as implemented by FoundationDB against a similar DST implementation by TigerBeetleDB, and evaluate DST on other key-value databases such as RocksDB, Cassandra and Valkey.

## Current development specifications

This repository uses the latest stable build of Zig 0.14.0, using [Zig Version Manager (ZVM)](https://www.zvm.app/).

After installing ZVM, to download and use the latest stable build, `0.14.0`, run:

```bash
zvm i 0.14.0 | zvm install 0.14.0
zvm use 0.14.0
```

## Architecture

The architecture of FRoST is roughly defined by the diagram below:

![FRoST Architecture](./docs/assets/architecture.svg)

## TODOs

- [x] Initialize development environment
- [ ] (IN PROGRESS: JOHN) Scratch standalone simulator based on TigerBeetle VOPR, PoC implementation
- [ ] (IN PROGRESS: SHAOHONG) Evaluate FoundationDB simulator standalone: https://github.com/apple/foundationdb/tree/main/tests/TestRunner
- [ ] (IN PROGRESS: SHAOHONG) Evaluate RocksDB simulator standalone: https://github.com/facebook/rocksdb/wiki/Stress-test
- [ ] (IN PROGRESS: SHAOHONG) Evaluate Cassandra simulator standalone: https://cassandra.apache.org/doc/stable/cassandra/tools/cassandra_stress.html
- [ ] Evaluate YCSB with/without TigerBeetle VOPR on FoundationDB
- [ ] Evaluate TigerBeetle VOPR on RocksDB
- [ ] Evaluate YCSB with/without TigerBeetle VOPR on RocksDB
- [ ] [Optional] Evaluate TigerBeetle VOPR on Cassandra
- [ ] [Optional] Evaluate YCSB with/without TigerBeetle VOPR on Cassandra
- [ ] [Optional] Evaluate TigerBeetle VOPR on Valkey
- [ ] [Optional] Evaluate YCSB with/without TigerBeetle VOPR on Valkey
- [ ] **DEADLINE: APR. 18** Final Report
- [ ] **DEADLINE: APR. 18** Final Presentation @9:30 (15 min)
