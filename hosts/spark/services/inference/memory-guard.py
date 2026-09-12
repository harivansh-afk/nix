"""Watch host memory: NVIDIA unified-memory allocations can escape cgroup accounting."""

import pathlib
import subprocess
import sys
import time

GIB_KB = 1024 ** 2


def memory():
    return {line.split(':')[0]: int(line.split()[1])
            for line in pathlib.Path('/proc/meminfo').read_text().splitlines()}


def pressured(mem):
    return mem['MemAvailable'] < 10 * GIB_KB or (
        mem['MemFree'] < 3 * GIB_KB and mem['MemAvailable'] < 14 * GIB_KB)


def main(mode):
    if mode == 'preflight':
        available = memory()['MemAvailable'] / GIB_KB
        if available < 98:
            raise SystemExit(f'vLLM needs at least 98 GiB MemAvailable before launch; '
                             f'currently {available:.1f} GiB. Free memory and retry.')
        return
    if mode != 'watch':
        raise SystemExit('Expected preflight or watch')
    consecutive = 0
    while True:
        mem = memory()
        consecutive = consecutive + 1 if pressured(mem) else 0
        if consecutive >= 5:
            print(f'Stopping vLLM: MemAvailable={mem["MemAvailable"] / GIB_KB:.1f} GiB, '
                  f'MemFree={mem["MemFree"] / GIB_KB:.1f} GiB for five samples.', flush=True)
            subprocess.run(['systemctl', '--no-block', 'stop', 'podman-vllm.service'], check=True)
            return
        time.sleep(1)


if __name__ == '__main__':
    main(sys.argv[1])
