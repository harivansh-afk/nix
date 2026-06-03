import os, json, time, subprocess, numpy as np, torch
from fastapi import FastAPI, UploadFile, Form, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
from transformers import AutoModel, AutoProcessor

MODEL_ID = os.environ.get("PARAKEET_MODEL_ID", "nvidia/parakeet-tdt-0.6b-v3")
SR = 16000
proc = AutoProcessor.from_pretrained(MODEL_ID, trust_remote_code=True)
model = AutoModel.from_pretrained(MODEL_ID, trust_remote_code=True, dtype=torch.float16).to("cuda").eval()

def decode(raw: bytes) -> np.ndarray:
    # Decode any container/codec to 16k mono f32 via ffmpeg
    p = subprocess.run(["ffmpeg","-nostdin","-loglevel","quiet","-i","pipe:0",
                        "-f","f32le","-ac","1","-ar",str(SR),"pipe:1"],
                       input=raw, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return np.frombuffer(p.stdout, dtype=np.float32)

def transcribe(audio: np.ndarray) -> str:
    if audio is None or audio.size < SR // 20:  # <50ms of audio
        return ""
    inp = proc(audio, sampling_rate=SR, return_tensors="pt")
    inp = {k: (v.to("cuda").half() if v.dtype==torch.float32 else v.to("cuda")) for k,v in inp.items()}
    with torch.no_grad():
        out = model.generate(**inp)
    txt = proc.batch_decode(out.sequences)
    return (txt[0] if txt else "").replace("<blank>", "").strip()

app = FastAPI()
@app.get("/health")
def health(): return {"ok": True, "model": MODEL_ID}
@app.get("/v1/models")
def models():
    # OpenAI-compatible model list (clients probe this to populate the picker).
    return {"object": "list", "data": [{"id": MODEL_ID, "object": "model", "owned_by": "parakeet"}]}
@app.post("/v1/audio/transcriptions")
async def tr(file: UploadFile, response_format: str = Form(default="json"), model: str = Form(default=MODEL_ID)):
    text = transcribe(decode(await file.read()))
    if response_format == "text": return PlainTextResponse(text)
    return JSONResponse({"text": text})

@app.post("/v1/chat/completions")
async def chat(req: Request):
    # No-op "cleanup": clients (e.g. OpenWhispr text cleanup) POST the transcript
    # as the user message expecting a polished version back. This is an ASR box,
    # not an LLM, so return the transcript unchanged instead of 404ing.
    body = await req.json()
    msgs = body.get("messages") or []
    content = ""
    for m in reversed(msgs):
        if m.get("role") == "user":
            content = m.get("content") or ""
            break
    mdl = body.get("model") or MODEL_ID
    created = int(time.time())
    if body.get("stream"):
        def gen():
            chunk = {"id": "chatcmpl-noop", "object": "chat.completion.chunk", "created": created,
                     "model": mdl, "choices": [{"index": 0, "delta": {"role": "assistant", "content": content}, "finish_reason": None}]}
            yield f"data: {json.dumps(chunk)}\n\n"
            done = {"id": "chatcmpl-noop", "object": "chat.completion.chunk", "created": created,
                    "model": mdl, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
            yield f"data: {json.dumps(done)}\n\n"
            yield "data: [DONE]\n\n"
        return StreamingResponse(gen(), media_type="text/event-stream")
    return JSONResponse({
        "id": "chatcmpl-noop", "object": "chat.completion", "created": created, "model": mdl,
        "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    })
