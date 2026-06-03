import os, subprocess, numpy as np, torch
from fastapi import FastAPI, UploadFile, Form
from fastapi.responses import JSONResponse, PlainTextResponse
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
