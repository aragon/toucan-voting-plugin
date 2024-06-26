# LayerZero imported code

Unfortunately, OSx has a hardcoded dependency on solidity 0.8.17, whereas LayerZero is ^0.8.17.

This incompatability means we must copy all layer zero code into a local file and change the pragma to match.