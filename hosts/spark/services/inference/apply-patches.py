"""Apply the pinned MiaAI recipe while building the image, never at service startup."""

import pathlib
import py_compile
import shutil
import subprocess
import sys

package = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                       else '/usr/local/lib/python3.12/dist-packages/vllm')
files = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else '/opt/spark-recipe/files')
targets = {
    'ple_layer_patched.py': 'models/qwen3_8_flash_next/nvidia/ple_layer.py',
    'modelopt_patched.py': 'model_executor/layers/quantization/modelopt.py',
    'qsa_ops_patched.py': 'models/qwen3_8_flash_next/nvidia/ops/qsa.py',
    'qsa_nvidia_patched.py': 'models/qwen3_8_flash_next/nvidia/qsa.py',
    'mtp_patched.py': 'models/qwen3_8_flash_next/nvidia/mtp.py',
    'ple_offload/ple_offload_layer.py': 'model_executor/layers/ple_offload_layer.py',
    'ple_offload/connector.py': 'v1/ple_offload/connector.py',
    'ple_offload/worker.py': 'v1/ple_offload/worker.py',
    'ple_offload/protocol.py': 'v1/ple_offload/protocol.py',
}
for output, target in targets.items():
    relative = pathlib.Path(output)
    original = (files / relative.parent / 'orig' / relative.name
                if relative.parent.name == 'ple_offload'
                else files / (output + '.orig'))
    original.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(package / target, original)

for patch in ['ple_layer', 'modelopt_mxfp8', 'qsa_fp8_kv', 'mtp_draft_vocab', 'ple_offload']:
    subprocess.run([sys.executable, str(files / f'patch_{patch}.py')], check=True)

for output, target in targets.items():
    py_compile.compile(str(files / output), doraise=True)
    shutil.copyfile(files / output, package / target)
