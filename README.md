# Bootloader Project

## Overview
This project extends a bootloader with the capability to display the contents of sectors on a disk image. The bootloader interacts with the user to read and display multiple sectors from the disk, providing both hexadecimal and ASCII representations of the data.

## Features

### User Interaction
- The bootloader prompts the user to enter the starting sector number and the number of sectors to read.
- After displaying the specified sectors, the user can input another sector number to continue reading.

### Display
- Each line of the display includes the offset into the sector.
- Hexadecimal values of the sector's data are shown.
- Corresponding ASCII character values for the bytes are displayed next to the hexadecimal values.
- The display pauses every 16 lines, waiting for a key press before continuing to the next set of lines.

### Input Handling
- The bootloader reads up to a 4-digit sector number from the keyboard.
- Handles user input dynamically, allowing for flexible reading and display of disk sectors.

## Project Structure

- `bootasm.S`: Assembly source file for the first stage of the bootloader.
- `bootasm2.S`: Assembly source file for the second stage of the bootloader.
- `Makefile`: Build script for compiling and linking the bootloader and creating the disk image.

## Building the Project

1. Ensure you have an `i386-elf` toolchain installed. If not, set your `TOOLPREFIX` environment variable accordingly.
2. Run the `make` command to build the bootloader and create the disk image.

```bash
make
```

## Running the Bootloader

1. The project uses QEMU for emulation. Ensure QEMU is installed and available in your PATH.
2. Run the bootloader in QEMU:

```bash
make qemu
```

3. To run QEMU with GDB for debugging:

```bash
make qemu-gdb
```

## Makefile Overview

The Makefile includes:
- Toolchain setup and detection.
- Rules for compiling assembly files into object files.
- Linking rules to create bootloader binaries.
- Commands to create and manipulate the disk image.
- Clean target to remove generated files.

### Key Makefile Targets

- `xv6.img`: Creates a disk image with the bootloader.
- `bootblock`: Compiles and links the first stage of the bootloader.
- `bootblock2`: Compiles and links the second stage of the bootloader.
- `clean`: Cleans up generated files.
