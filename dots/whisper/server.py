import json
import os
import subprocess
import time

import numpy as np
import torch
from fastapi import FastAPI, Form, Request, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor, pipeline

MODEL_ID = os.environ.get("WHISPER_MODEL_ID", "openai/whisper-large-v3")
SR = 16000

processor = AutoProcessor.from_pretrained(MODEL_ID)
model = AutoModelForSpeechSeq2Seq.from_pretrained(
    MODEL_ID,
    dtype=torch.float16,
    low_cpu_mem_usage=True,
    use_safetensors=True,
    attn_implementation="sdpa",
).to("cuda").eval()
asr = pipeline(
    "automatic-speech-recognition",
    model=model,
    tokenizer=processor.tokenizer,
    feature_extractor=processor.feature_extractor,
    chunk_length_s=30,
    batch_size=1,
    dtype=torch.float16,
    device="cuda",
)


def decode(raw: bytes) -> np.ndarray:
    process = subprocess.run(
        [
            "ffmpeg",
            "-nostdin",
            "-loglevel",
            "quiet",
            "-i",
            "pipe:0",
            "-f",
            "f32le",
            "-ac",
            "1",
            "-ar",
            str(SR),
            "pipe:1",
        ],
        input=raw,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    return np.frombuffer(process.stdout, dtype=np.float32)


def transcribe(audio: np.ndarray, language: str | None = None) -> str:
    if audio.size < SR // 20:
        return ""
    generate_kwargs = {"task": "transcribe"}
    if language:
        generate_kwargs["language"] = language
    result = asr(audio, generate_kwargs=generate_kwargs)
    return result["text"].strip()


app = FastAPI()


@app.get("/health")
def health():
    return {"ok": True, "model": MODEL_ID}


@app.get("/v1/models")
def models():
    return {
        "object": "list",
        "data": [{"id": MODEL_ID, "object": "model", "owned_by": "openai"}],
    }


@app.post("/v1/audio/transcriptions")
async def transcription(
    file: UploadFile,
    response_format: str = Form(default="json"),
    requested_model: str = Form(default=MODEL_ID, alias="model"),
    language: str | None = Form(default=None),
):
    del requested_model
    text = transcribe(decode(await file.read()), language)
    if response_format == "text":
        return PlainTextResponse(text)
    return JSONResponse({"text": text})


@app.post("/v1/chat/completions")
async def chat(req: Request):
    body = await req.json()
    messages = body.get("messages") or []
    content = ""
    for message in reversed(messages):
        if message.get("role") == "user":
            content = message.get("content") or ""
            break
    requested_model = body.get("model") or MODEL_ID
    created = int(time.time())
    if body.get("stream"):

        def generate():
            chunk = {
                "id": "chatcmpl-noop",
                "object": "chat.completion.chunk",
                "created": created,
                "model": requested_model,
                "choices": [
                    {
                        "index": 0,
                        "delta": {"role": "assistant", "content": content},
                        "finish_reason": None,
                    }
                ],
            }
            yield f"data: {json.dumps(chunk)}\n\n"
            done = {
                "id": "chatcmpl-noop",
                "object": "chat.completion.chunk",
                "created": created,
                "model": requested_model,
                "choices": [
                    {"index": 0, "delta": {}, "finish_reason": "stop"}
                ],
            }
            yield f"data: {json.dumps(done)}\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(generate(), media_type="text/event-stream")
    return JSONResponse(
        {
            "id": "chatcmpl-noop",
            "object": "chat.completion",
            "created": created,
            "model": requested_model,
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": content},
                    "finish_reason": "stop",
                }
            ],
            "usage": {
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
            },
        }
    )
