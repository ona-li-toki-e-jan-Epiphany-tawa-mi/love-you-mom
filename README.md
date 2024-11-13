# love-you-mom

Tells your mom (or dad) that you love them.

Press ANY KEY to exit.

## How to build

Depdenencies:

- libc.
- zig 0.13.0 (other versions may work) - [https://ziglang.org](https://ziglang.org/)

There's a `flake.nix` you can use to generate a development enviroment with
`nix develop path:.`.

Then, run the following command(s):

```sh
zig build
```

You can append the following arguments for different optimizations:

- `-Doptimize=ReleaseSafe` - Faster.
- `-Doptimize=ReleaseFast` - Fasterer, no safety checks.
- `-Doptimize=ReleaseSmall` - Faster, smaller binaries, no safety checks.

The executable will appear in `zig-out/bin/`.

## How to run

Dependencies:

- libc.
- POSIX system.
- Terminal supporting ANSI codes and termios.

Then, run the following commands(s) to get started:

```sh
./zig-out/bin/love-you-mom --help
```
