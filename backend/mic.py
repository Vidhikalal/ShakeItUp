import asyncio, base64, json, time
import numpy as np
import sounddevice as sd
import websockets

WS_URL = "ws://127.0.0.1:8000/ws/mic"
SAMPLE_RATE = 16000
CHUNK_MS = 40  # 25 chunks/sec
CHANNELS = 1

def pcm16_base64_from_float32(x: np.ndarray) -> str:
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype(np.int16)
    return base64.b64encode(pcm.tobytes()).decode("ascii")

async def run():
    print("Connecting to:", WS_URL)
    async with websockets.connect(WS_URL, ping_interval=20) as ws:
        await ws.send(json.dumps({"type": "config", "sampleRate": SAMPLE_RATE}))
        print("Sent config")

        # Task: receive pulses
        async def receiver():
            async for msg in ws:
                try:
                    data = json.loads(msg)
                except:
                    continue
                if data.get("type") == "pulse":
                    print(f"PULSE {data.get('style')} at {data.get('atMs')}")
                elif data.get("type") == "ok":
                    print("Server OK:", data)

        recv_task = asyncio.create_task(receiver())

        # Stream mic audio
        frames_per_chunk = int(SAMPLE_RATE * (CHUNK_MS / 1000.0))

        loop = asyncio.get_running_loop()

        def callback(indata, frames, t, status):
            if status:
                # e.g., input overflow
                pass
            # indata shape: (frames, channels) float32
            mono = indata[:, 0] if indata.ndim > 1 else indata
            b64 = pcm16_base64_from_float32(mono)
            # send from audio thread -> event loop
            loop.call_soon_threadsafe(asyncio.create_task,
                                      ws.send(json.dumps({"type": "chunk", "pcm16_base64": b64})))

        print("Starting mic. Make noise or play music near the mic…")
        with sd.InputStream(samplerate=SAMPLE_RATE, channels=CHANNELS,
                            dtype="float32", blocksize=frames_per_chunk,
                            callback=callback):
            while True:
                await asyncio.sleep(1)

        await recv_task

if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("Stopped.")
