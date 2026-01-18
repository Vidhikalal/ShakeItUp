import cors from "cors";
import express from "express";
import { WebSocketServer } from "ws";

const app = express();
app.use(cors());
app.get("/health", (_, res) => res.json({ ok: true }));

const PORT = process.env.PORT || 8000;

const server = app.listen(PORT, "0.0.0.0", () => {
  const addr = server.address();
  console.log("LISTENING:", addr);
});

server.on("error", (err) => {
  console.error("LISTEN ERROR:", err);
});

/**
 * WS protocol:
 * Client -> { type:"config", sampleRate:16000 }
 * Client -> { type:"chunk", pcm16_base64:"..." }  // mono, signed 16-bit LE
 * Server -> { type:"pulse", style:"heavy|medium|light", atMs:<server time> }
 */

function pcm16Base64ToFloat32(b64) {
  const buf = Buffer.from(b64, "base64");
  const out = new Float32Array(buf.length / 2);
  for (let i = 0, j = 0; i < buf.length; i += 2, j++) {
    out[j] = buf.readInt16LE(i) / 32768;
  }
  return out;
}

// Simple, robust energy-peak detector (works well for beat-like vibration)
function makeDetector() {
  let ema = 0.02; // baseline RMS
  let varEma = 0.0001; // baseline variance
  let lastPulseAt = 0;

  const minGapMs = 120; // tactile clarity; prevents “buzz”
  const alpha = 0.06;

  return (samples, nowMs) => {
    let sum = 0;
    for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
    const rms = Math.sqrt(sum / Math.max(1, samples.length));

    const d = rms - ema;
    ema += alpha * d;
    varEma += alpha * (d * d - varEma);
    const std = Math.sqrt(Math.max(varEma, 1e-9));

    const thr = ema + 2.0 * std; // adaptive threshold
    if (nowMs - lastPulseAt < minGapMs) return null;
    if (rms <= thr) return null;

    lastPulseAt = nowMs;

    // Strength mapping (z-score-ish)
    const z = (rms - ema) / (std + 1e-6);
    const style = z > 3.5 ? "heavy" : z > 2.6 ? "medium" : "light";
    return { style };
  };
}

const wss = new WebSocketServer({ server, path: "/ws/mic" });

wss.on("connection", (ws) => {
  const detect = makeDetector();
  let sampleRate = 16000;

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      ws.send(JSON.stringify({ type: "error", error: "Invalid JSON" }));
      return;
    }

    if (msg.type === "config") {
      if (typeof msg.sampleRate === "number") sampleRate = msg.sampleRate;
      ws.send(JSON.stringify({ type: "ok", sampleRate }));
      return;
    }

    if (msg.type === "chunk") {
      if (!msg.pcm16_base64) return;
      const samples = pcm16Base64ToFloat32(msg.pcm16_base64);
      const nowMs = Date.now();
      const pulse = detect(samples, nowMs);
      if (pulse)
        ws.send(
          JSON.stringify({ type: "pulse", style: pulse.style, atMs: nowMs }),
        );
      return;
    }

    ws.send(JSON.stringify({ type: "error", error: "Unknown message type" }));
  });
});
