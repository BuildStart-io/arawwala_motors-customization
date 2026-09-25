# Voice Pipeline Fix Implementation

This document outlines the step-by-step root cause analysis and the correct implementation steps used to fix the voice messaging pipeline. 

## Background
The voice messaging pipeline was constantly failing to transcribe audio, returning the hardcoded fallback message:
> "I couldn't hear that clearly. Could you please resend it or type it out for me?"

Previous attempts focused solely on the missing `OPENROUTER_API_KEY` environment variable in the Supabase edge-runtime. While injecting the environment variable via `docker-compose.yml` was successfully achieved (allowing the code to pass the API key check), the transcription process was *still* failing silently.

## Root Cause Analysis
1. **The Hidden 404 Error:** 
   After bypassing the API key check, the script failed during the WAHA audio download step. Because the `console.error` and `console.log` statements inside `transcribe.ts` did *not* include the correlation ID (`corrId`) in their output, previous log searches (which grepped for the correlation ID) inadvertently hid the actual error.
   
   Once the raw, unfiltered logs were retrieved for the exact timestamp of the test, the following error was discovered:
   ```
   [Info] Downloading audio from: https://waha.[REDACTED]/api/.../download
   [Error] WAHA download failed (404): {"message":"Cannot GET /api/.../download","error":"Not Found","statusCode":404}
   ```
   The endpoint `/api/{session}/messages/{id}/download` was returning a `404 Not Found` because WAHA NOWEB does not expose this specific download endpoint for media.

2. **The Missing URL:**
   A deep inspection of the original WAHA webhook payload (retrieved directly from the `metadata->'raw'` field in the `conversations` table) revealed that WAHA *already provides a direct download URL* for the audio file:
   ```json
   "media": {
     "url": "https://waha.[REDACTED]/api/files/...oga",
     "filename": null,
     "mimetype": "audio/ogg; codecs=opus"
   }
   ```
   Instead of trying to construct an invalid download endpoint, the pipeline just needed to use the URL provided directly in the webhook payload.

## Correct Implementation Steps

1. **Extract Media URL from Webhook Payload (`index.ts`)**
   In the `process-message` edge function, the webhook payload is parsed. When a voice message is detected, the direct media URL is extracted and passed to the transcription service.
   ```typescript
   // supabase/functions/process-message/index.ts
   if (isVoice) {
     console.log(`[${corrId}] Detected voice message, attempting transcription...`);
     const mediaUrl = body?.payload?.media?.url || body?.media?.url;
     const transcription = await transcribeAudio(sessionApiKey, wahaMessageId, mediaUrl);
     // ...
   }
   ```

2. **Update Transcription Service (`transcribe.ts`)**
   The `transcribeAudio` function was updated to accept the `mediaUrl` as an optional parameter and prioritize it over the constructed URL.
   ```typescript
   // supabase/functions/process-message/transcribe.ts
   export async function transcribeAudio(sessionName: string, wahaMessageId: string, mediaUrl?: string): Promise<string | null> {
     // ...
     try {
       const wahaUrl = mediaUrl || `${WAHA_BASE}/api/${encodeURIComponent(sessionName)}/messages/${encodeURIComponent(wahaMessageId)}/download`;
       console.log(`Downloading audio from: ${wahaUrl}`);
       const res = await fetch(wahaUrl, {
         headers: { "X-Api-Key": WAHA_KEY, "Accept": "*/*" },
         // ...
       });
       // ...
   ```

3. **Deploy the Changes**
   - Both `index.ts` and `transcribe.ts` were securely transferred to the production server volume at `/root/supabase/supabase/docker/volumes/functions/process-message/`.
   - The Supabase Edge Functions container was completely restarted to apply the changes and ensure the environment variables (like `OPENROUTER_API_KEY`) were correctly loaded into the worker runtime:
     ```bash
     cd /root/supabase/supabase/docker && docker compose up -d --force-recreate functions
     ```

## Summary
The system now correctly bypasses the invalid download endpoint by using the direct media URL provided natively in the WAHA payload. The transcription audio is fetched successfully, passed to OpenRouter, and transcribed accurately.
