import { startRecording, stopRecording } from "expo-audio-stream";
import * as Haptics from "expo-haptics";
import { useEffect, useRef } from "react";

// Helper: ArrayBuffer -> base64 (works in RN)
function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i++)
    binary += String.fromCharCode(bytes[i]);
  return global.btoa(binary);
}

export function useMicStreamToWS(wsUrl) {
  const wsRef = useRef(null);

  useEffect(() => {
    return () => {
      try {
        wsRef.current?.close();
      } catch {}
    };
  }, []);

  const start = async () => {
    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      ws.send(JSON.stringify({ type: "config", sampleRate: 16000 }));
    };

    ws.onmessage = async (e) => {
      const msg = JSON.parse(e.data);
      if (msg.type === "pulse") {
        if (msg.style === "heavy")
          await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
        else if (msg.style === "medium")
          await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
        else await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      }
      console.log("PULSE RECEIVED", msg.style);
    };

    ws.onerror = (err) => console.warn("WS error", err);
    ws.onclose = () => console.warn("WS closed");

    // Start mic stream
    // expo-audio-stream provides PCM chunks (usually base64 or ArrayBuffer depending on config)
    await startRecording({
      sampleRate: 16000,
      channels: 1,
      encoding: "pcm16",
      interval: 40, // ms between chunks (lower = more real-time)
      onAudioStream: (audio) => {
        // Depending on library version, audio may be:
        // - { data: base64 } OR
        // - { data: ArrayBuffer }

        const pcmBase64 =
          typeof audio?.data === "string"
            ? audio.data
            : audio?.data instanceof ArrayBuffer
              ? arrayBufferToBase64(audio.data)
              : null;

        if (!pcmBase64) return;
        if (ws.readyState !== 1) return;

        ws.send(JSON.stringify({ type: "chunk", pcm16_base64: pcmBase64 }));
        console.log("MIC CHUNK SENT");
      },
    });
  };

  const stop = async () => {
    try {
      await stopRecording();
    } catch {}
    try {
      wsRef.current?.close();
    } catch {}
  };

  return { start, stop };
}
