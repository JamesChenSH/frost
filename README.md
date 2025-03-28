# FoundationDB, RocksDB Simulation Tester (FRoST)

FoundationDB is one of the progenitors of deterministic simulation testing (DST). Here we evaluate DST as implemented by FoundationDB against a similar DST implementation by TigerBeetleDB, and evaluate DST on other key-value databases such as RocksDB, Cassandra and Valkey.

## Current development specifications

This repository uses the nightly build of Zig, using [Zig Version Manager (ZVM)](https://www.zvm.app/).

After installing ZVM, to download and use the latest stable build, `0.14.0`, run:

```bash
zvm i 0.14.0 | zvm install 0.14.0
zvm use 0.14.0
```
