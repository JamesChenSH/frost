# FoundationDB, RocksDB Simulation Tester (FRoST)

FoundationDB is one of the progenitors of deterministic simulation testing (DST). Here we evaluate DST as implemented by FoundationDB against a similar DST implementation by TigerBeetleDB, and evaluate DST on other key-value databases such as RocksDB, Cassandra and Valkey.

## Current development specifications

This repository uses the latest stable build of Zig 0.14.0, using [Zig Version Manager (ZVM)](https://www.zvm.app/).

After installing ZVM, to download and use the latest stable build, `0.14.0`, run:

```bash
zvm i 0.14.0 | zvm install 0.14.0
zvm use 0.14.0
```

## TODOs

- [x] Initialize development environment
- [ ] (IN PROGRESS: JOHN) Port TigerBeetle VOPR to this repository, run standalone on FoundationDB
- [ ] Evaluate FoundationDB simulator standalone
- [ ] Evaluate YCSB with/without TigerBeetle VOPR on FoundationDB
- [ ] Evaluate TigerBeetle VOPR on RocksDB
- [ ] Evaluate YCSB with/without TigerBeetle VOPR on RocksDB
- [ ] [Optional] Evaluate TigerBeetle VOPR on Cassandra
- [ ] [Optional] Evaluate YCSB with/without TigerBeetle VOPR on Cassandra
- [ ] [Optional] Evaluate TigerBeetle VOPR on Valkey
- [ ] [Optional] Evaluate YCSB with/without TigerBeetle VOPR on Valkey
- [ ] **DEADLINE: APR. 18** Final Report
- [ ] **DEADLINE: APR. 18** Final Presentation @9:30 (15 min)
