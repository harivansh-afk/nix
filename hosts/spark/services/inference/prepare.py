"""Prepare a pinned image and checkpoint without consuming GPU memory."""

import json
import pathlib
import shutil
import subprocess
import sys

GIB = 1024 ** 3


def missing_files(directory, manifest):
    return {name: size for name, size in manifest.items()
            if not (directory / name).is_file()
            or (directory / name).stat().st_size != size}


def packed_complete(directory):
    tables = list(directory.glob('*.packed_u8'))
    if not tables:
        return False
    try:
        return all(table.stat().st_size == (
            (meta := json.loads(table.with_suffix('.packed_u8.json').read_text()))['total_rows']
            * meta['row_width']) for table in tables)
    except (OSError, ValueError, KeyError):
        return False


def required_space(missing, image_exists, packed_exists):
    # Conservative allowances for image extraction/build and the packed PLE table.
    return sum(missing.values()) + (0 if image_exists else 35 * GIB) + (
        0 if packed_exists else 28 * GIB) + 20 * GIB


def main(config_path):
    config = json.loads(pathlib.Path(config_path).read_text())
    state = pathlib.Path(config['stateDir'])
    model = state / 'models' / config['modelRevision']
    packed = state / 'ple' / config['modelRevision']
    manifest = json.loads(pathlib.Path(config['manifest']).read_text())
    model.mkdir(parents=True, exist_ok=True)
    packed.mkdir(parents=True, exist_ok=True)
    (state / 'cache').mkdir(exist_ok=True)
    image_exists = subprocess.run(
        ['podman', 'image', 'exists', config['image']], check=False).returncode == 0
    missing = missing_files(model, manifest)
    required = required_space(missing, image_exists, packed_complete(packed))
    available = shutil.disk_usage(state).free
    print(f'Preparation needs {required / GIB:.1f} GiB free, including a 20 GiB floor; '
          f'{available / GIB:.1f} GiB available.', flush=True)
    if available < required:
        raise SystemExit('Insufficient disk space. No image pull or model download started.')
    if not image_exists:
        subprocess.run(['podman', 'build', '--network=none', '--pull=missing',
                        '--build-arg', 'BASE_IMAGE=' + config['baseImage'],
                        '--tag', config['image'], config['imageContext']], check=True)
    if missing:
        from huggingface_hub import snapshot_download
        snapshot_download(repo_id=config['modelId'], revision=config['modelRevision'],
                          local_dir=model, allow_patterns=list(manifest), max_workers=4)
    if missing_files(model, manifest):
        raise SystemExit('Checkpoint is incomplete or has incorrect file sizes.')
    # A missing metadata file can be left by interruption after the atomic table rename.
    if not packed_complete(packed):
        for table in packed.glob('*.packed_u8'):
            table.unlink()
        subprocess.run([
            'podman', 'run', '--rm', '--network=none', '--memory=6g', '--memory-swap=6g',
            '--cpus=8', '--volume', f'{model}:/model:ro',
            '--volume', f'{packed}:/packed', '--entrypoint', 'python3', config['image'],
            '/opt/spark-recipe/files/build_ple_packed_table.py', '/model', '/packed',
        ], check=True)
    if not packed_complete(packed):
        raise SystemExit('Packed PLE table is incomplete.')
    print('Pinned image, checkpoint, and packed PLE table are ready.', flush=True)


if __name__ == '__main__':
    main(sys.argv[1])
