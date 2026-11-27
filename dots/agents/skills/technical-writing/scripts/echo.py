import argparse
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request


def request_completion(prompt, api_key):
    payload = {
        "model": "echo",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 4096,
    }
    request = urllib.request.Request(
        "https://api.slashy.com/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=600) as response:
        return json.load(response)


def save_completion(response, output_dir):
    (output_dir / "response.json").write_text(json.dumps(response, indent=2) + "\n")
    choice = response["choices"][0]
    content = choice["message"]["content"]
    if not isinstance(content, str) or not content.strip():
        raise ValueError("Echo returned no prose; inspect response.json")
    if choice.get("finish_reason") != "stop":
        (output_dir / "partial.md").write_text(content)
        raise ValueError("Echo did not finish normally; inspect partial.md")
    (output_dir / "draft.md").write_text(content.rstrip() + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    api_key = os.environ.get("SLASHY_API_KEY")
    if not api_key:
        parser.error("SLASHY_API_KEY is required")
    prompt = args.prompt.read_text()
    if not prompt.strip():
        parser.error("The prompt is empty")
    args.output_dir.mkdir(parents=True, exist_ok=False, mode=0o700)
    (args.output_dir / "prompt.md").write_text(prompt)
    try:
        response = request_completion(prompt, api_key)
    except urllib.error.HTTPError as error:
        retry_after = error.headers.get("Retry-After", "unspecified")
        raise RuntimeError(
            f"Echo HTTP {error.code}; Retry-After: {retry_after}"
        ) from None
    save_completion(response, args.output_dir)
    print(args.output_dir / "draft.md")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, IndexError, RuntimeError) as error:
        print(f"Echo request failed: {error}", file=sys.stderr)
        sys.exit(1)
