# Alpine Linux System Install for C.H.I.P.

Setup your C.H.I.P. in FEL mode and connect it to your computer, then execute:

```
make clean docker
make flash
```

After flashing, Alpine linux will be running. Connect to your C.H.I.P. via serial and setup networking by typing:

```
setup-interfaces
```

Boot binaries compiled from:

* https://github.com/ntc-chip-revived/CHIP-u-boot/tree/production-mlc
* https://github.com/ntc-chip-revived/CHIP-mtd-utils/tree/by/1.5.2/next-mlc-debian
