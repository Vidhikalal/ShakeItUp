// micStreamToBackend.js
import * as Haptics from "expo-haptics";

export async function streamMicToBackend({
  wsUrl,
  pcmFrameEmitter, // function that calls (pcm16ArrayBuffer) repeatedly
  sampleRate = 16000,
}) {
  const ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    ws.send(JSON.stringify({ type: "config", sampleRate }));
  };

  ws.onmessage = async (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === "pulse") {
      // Low latency: vibrate immediately when server detects a beat
      if (msg.style === "heavy")
        await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
      else if (msg.style === "medium")
        await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      else await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    }
  };

  ws.onerror = (err) => console.warn("WS error", err);
  ws.onclose = () => console.warn("WS closed");

  // Your mic module should call this callback ~20–50 times/sec with PCM16 mono bytes
  pcmFrameEmitter((pcm16ArrayBuffer) => {
    if (ws.readyState !== 1) return;

    // Convert ArrayBuffer -> base64
    const u8 = new Uint8Array(pcm16ArrayBuffer);
    let binary = "";
    for (let i = 0; i < u8.length; i++) binary += String.fromCharCode(u8[i]);
    const b64 = global.btoa(binary);

    ws.send(JSON.stringify({ type: "chunk", pcm16_base64: b64 }));
  });

  return () => ws.close();
}
