# Copyright 2026
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Seyyid Hikmet Celik <seyyid4091@gmail.com>

import sys
import time
import argparse
import pexpect
import signal

def signal_handler(sig, frame):
    raise KeyboardInterrupt

def run_gdb(gdb_exec, elf_file, gdb_args, cmd, timeout):
    full_cmd = f'{gdb_exec} -ex "set pagination off" -ex "set confirm off" {elf_file} {gdb_args}'
    
    child = pexpect.spawn(full_cmd, encoding='utf-8')
    child.logfile = sys.stdout
    
    signal.signal(signal.SIGINT, signal_handler)

    try:
        child.expect_exact('(gdb) ', timeout=30)

        #child.sendline('set pagination off')
        #child.expect_exact('(gdb) ', timeout=5)

        child.sendline(cmd)
        
        if timeout <= 0:
            while child.isalive():
                time.sleep(0.1)
        else:
            end = time.time() + (timeout / 1000.0)
            while time.time() < end:
                if not child.isalive():
                    break
                time.sleep(0.01)

    except (KeyboardInterrupt, pexpect.TIMEOUT):
        pass
    except Exception as e:
        print(f"\nError: {e}")
    finally:
        if child.isalive():
            child.sendintr()
            try:
                child.expect_exact('(gdb) ', timeout=2)
                child.sendline('quit')
            except:
                child.close(force=True)
        else:
            child.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    
    parser.add_argument("--gdb-exec", 
                        default="/home/shc/projects/cheshire-linux-nvdla/riscv-toolchain-custom/_install/bin/riscv64-unknown-linux-gnu-gdb")
    
    parser.add_argument("--elf-file", 
                        default="/home/shc/projects/cheshire-linux-nvdla/riscv-linux-port/vmlinux")
    
    parser.add_argument("--args", 
                        default='-ex "target remote :3333"')
    
    parser.add_argument("--command", 
                        default="continue")
    
    parser.add_argument("--timeout", 
                        type=int,
                        default=0)

    args = parser.parse_args()

    run_gdb(args.gdb_exec, args.elf_file, args.args, args.command, args.timeout)
