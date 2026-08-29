import asyncio
import base64
import json
import os
import subprocess
import threading
import time

import numpy as np
import torch
from fastapi import FastAPI, Form, Request, UploadFile, WebSocket
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
from starlette.websockets import WebSocketDisconnect
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


# One model, one GPU: serialize batch and streaming passes.
MODEL_LOCK = threading.Lock()


def transcribe(audio: np.ndarray, language: str | None = None) -> str:
    if audio.size < SR // 20:
        return ""
    generate_kwargs = {"task": "transcribe"}
    if language:
        generate_kwargs["language"] = language
    with MODEL_LOCK:
        result = asr(audio, generate_kwargs=generate_kwargs)
    return result["text"].strip()


def transcribe_segments(
    audio: np.ndarray, language: str | None = None
) -> list[dict]:
    """One streaming pass: whisper segments as {"words": [...], "end": secs}.

    Segment timestamps come from whisper's own timestamp tokens and are
    essentially free; word-level timestamps are NOT (they force attention
    outputs, which disables the SDPA fast path and is an order of magnitude
    slower - measured on this stack).
    """
    if audio.size < SR // 20:
        return []
    generate_kwargs = {"task": "transcribe"}
    if language:
        generate_kwargs["language"] = language
    with MODEL_LOCK:
        result = asr(
            audio, return_timestamps=True, generate_kwargs=generate_kwargs
        )
    return [
        {"words": chunk["text"].split(), "end": chunk["timestamp"][1]}
        for chunk in result.get("chunks") or []
        if chunk["text"].strip()
    ]


# Warm CUDA kernels at startup so the first real request doesn't pay init.
warmup_started = time.monotonic()
transcribe(np.zeros(SR, dtype=np.float32), "en")
print(f"warmup: {time.monotonic() - warmup_started:.1f}s", flush=True)


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


# Streaming transcription: transcribe WHILE the client is still recording, so
# only a short unconfirmed tail is left to do when it stops. The client
# streams 16 kHz mono s16le PCM; whisper re-runs over the growing window
# back-to-back and words are locked in once two consecutive passes agree on
# them (LocalAgreement-2, after ufal/whisper_streaming). Confirmed audio is
# trimmed off the window at segment boundaries, which bounds per-pass cost on
# long recordings and keeps the final post-commit pass short.
#
# Wire protocol: OpenAI Realtime transcription shapes.
#   client -> {"type": "input_audio_buffer.append", "audio": <base64 pcm>}
#   client -> {"type": "input_audio_buffer.commit"}
#   server -> {"type": "conversation.item.input_audio_transcription.delta",
#              "delta": <newly confirmed words>}
#   server -> {"type": "conversation.item.input_audio_transcription.completed",
#              "transcript": <authoritative full text>}
DELTA_EVENT = "conversation.item.input_audio_transcription.delta"
COMPLETED_EVENT = "conversation.item.input_audio_transcription.completed"
STREAM_MIN_NEW_S = 1.0  # don't re-run a pass for less than this much new audio
STREAM_TRIM_S = 8.0  # start trimming confirmed audio past this window size
STREAM_FORCE_TRIM_S = 25.0  # never let the window exceed one 30s chunk


def _norm(word: str) -> str:
    return word.strip(".,!?;:\"'").lower()


class StreamingSession:
    """Incremental transcription state for one streaming connection.

    Not thread-safe: the caller must not append() while a step()/finalize()
    pass is in flight.
    """

    def __init__(self, language: str | None):
        self.language = language
        self.window = np.zeros(0, dtype=np.float32)  # audio not yet trimmed
        self.covered = 0.0  # seconds of window covered by the last pass
        self.history: list[str] = []  # confirmed words trimmed off the window
        self.confirmed: list[str] = []  # confirmed words still in the window
        self.prev: list[str] = []  # previous pass hypothesis for the window
        self.segments: list[dict] = []  # segments of the previous pass

    @property
    def duration(self) -> float:
        return self.window.size / SR

    @property
    def pending(self) -> float:
        """Seconds of audio not yet covered by a pass."""
        return self.duration - self.covered

    def append(self, pcm: bytes) -> None:
        samples = np.frombuffer(pcm, dtype=np.int16)
        self.window = np.concatenate(
            [self.window, samples.astype(np.float32) / 32768.0]
        )

    def step(self) -> str:
        """Run one pass over the window; return newly confirmed words."""
        self.covered = self.duration
        self.segments = transcribe_segments(self.window, self.language)
        words = [w for segment in self.segments for w in segment["words"]]

        # LocalAgreement-2: confirm the longest common prefix of the two most
        # recent hypotheses (case/punctuation-insensitive; latest wins).
        agree = 0
        for ours, theirs in zip(self.prev, words):
            if _norm(ours) != _norm(theirs):
                break
            agree += 1
        delta = ""
        if agree > len(self.confirmed):
            delta = " ".join(words[len(self.confirmed) : agree])
            self.confirmed = words[:agree]
        self.prev = words

        self._trim()
        return delta

    def finalize(self) -> str:
        """Transcribe only the unconfirmed tail; return the full transcript."""
        cut = self._confirmed_cut()
        if cut:
            self._cut(*cut)
        segments = transcribe_segments(self.window, self.language)
        tail = [w for segment in segments for w in segment["words"]]
        return " ".join(self.history + tail)

    def _confirmed_cut(self) -> tuple[float, int] | None:
        """Latest segment boundary with every word before it confirmed."""
        cut = None
        count = 0
        for segment in self.segments:
            count += len(segment["words"])
            if count > len(self.confirmed):
                break
            if segment["end"] is not None:
                cut = (float(segment["end"]), count)
        return cut

    def _trim(self) -> None:
        if self.duration <= STREAM_TRIM_S:
            return
        cut = self._confirmed_cut()
        if self.duration > STREAM_FORCE_TRIM_S:
            # Agreement has stalled (noise, music, no pauses). Bank the stale
            # hypothesis up to the last timestamped segment rather than let
            # the window exceed a single 30s whisper chunk.
            boundaries = [
                (float(segment["end"]), count)
                for count, segment in self._counted_segments()
                if segment["end"] is not None
            ]
            if boundaries:
                cut = boundaries[-1]
                self.confirmed = self.prev[: cut[1]]
        if cut and cut[0] >= 1.0:
            self._cut(*cut)

    def _counted_segments(self):
        count = 0
        for segment in self.segments:
            count += len(segment["words"])
            yield count, segment

    def _cut(self, seconds: float, words: int) -> None:
        """Drop the first `seconds` of audio and its `words` off the window."""
        self.window = self.window[int(seconds * SR) :]
        self.covered = max(0.0, self.covered - seconds)
        self.history += self.confirmed[:words]
        self.confirmed = self.confirmed[words:]
        self.prev = self.prev[words:]
        self.segments = []  # stale after a cut; refreshed by the next pass


@app.websocket("/v1/realtime")
async def realtime(ws: WebSocket):
    await ws.accept()
    session = StreamingSession(ws.query_params.get("language") or None)

    pcm_chunks: list[bytes] = []
    committed = asyncio.Event()
    disconnected = asyncio.Event()

    async def receive():
        try:
            while not committed.is_set():
                message = json.loads(await ws.receive_text())
                kind = message.get("type")
                if kind == "input_audio_buffer.append":
                    pcm_chunks.append(base64.b64decode(message.get("audio") or ""))
                elif kind == "input_audio_buffer.commit":
                    committed.set()
        except WebSocketDisconnect:
            disconnected.set()

    receiver = asyncio.create_task(receive())
    try:
        while not disconnected.is_set():
            while pcm_chunks:
                session.append(pcm_chunks.pop(0))

            if committed.is_set() and not pcm_chunks:
                transcript = await asyncio.to_thread(session.finalize)
                await ws.send_json(
                    {"type": COMPLETED_EVENT, "transcript": transcript}
                )
                await ws.close()
                return
            if session.pending < STREAM_MIN_NEW_S:
                await asyncio.sleep(0.05)
                continue

            delta = await asyncio.to_thread(session.step)
            if delta:
                await ws.send_json({"type": DELTA_EVENT, "delta": delta})
    finally:
        receiver.cancel()
