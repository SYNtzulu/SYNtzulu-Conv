#!/bin/bash

# Check if the application name is passed
if [ -z "$1" ]; then
    echo "Usage: $0 <application_name>"
    exit 1
fi
app="$1"

# Path to the address file
ADDRESS_FILE="src/$1/address.txt"

# Check if address file exists
if [ ! -f "$ADDRESS_FILE" ]; then
    echo "Error: address file '$ADDRESS_FILE' not found."
    exit 1
fi

# Read ADDRESS into an array
mapfile -t ADDRESS < "$ADDRESS_FILE"

# Ensure ADDRESS are loaded
if [ "${#ADDRESS[@]}" -lt 1 ]; then
    echo "Error: Not enough ADDRESS in '$ADDRESS_FILE'."
    exit 1
fi

# Bulk erase flash
sudo iceprog -b

# Generate binary file
cp src/"$app"/samples.txt .
gcc bin_gen.c
sudo ./a.out
rm samples.txt

# Write flash using loaded ADDRESS
sudo iceprog -o 1048576 -n to_flash/sample.bin    # write samples

# Read flash
rm from_flash/*
sudo iceprog -o 1048576 -R 32768 read.s # read samples
xxd read.s >> from_flash/read_s.txt # binary to hex conversion
sudo rm read.s

# Optional: Read entire flash
sudo iceprog -o 1048576 -R 65536 read.output # read whole flash
xxd read.output >> from_flash/read.txt # binary to hex conversion
sudo rm read.output

