# Arawwala Motors - Customization

This repository contains the tailored self-hosted WhatsApp AI bot environment for **Arawwala Motors**. It builds upon the core `BuildStart-io` self-hosted architecture with several bespoke features specifically requested by the client.

## High-Level Customizations

### 1. Dark Theme & UI Modifications
- Implemented a persistent **Dark/Light Theme Toggle**.
- The toggle was seamlessly integrated into both the mobile header and desktop sidebar navigation of the dashboard (`DashboardLayout.tsx`).

### 2. AI Handover / Escalation Protocol
- Added an **Escalation Notification System** to the Chatbot settings tab.
- **How it works:** If a customer asks a question that the AI cannot answer using the provided Product Catalog or FAQs, the AI is instructed to output an `<ESCALATE/>` tag. The `process-message` edge function intercepts this tag and automatically sends a WhatsApp alert to the designated business owner's phone number, prompting them to take over the chat manually.

### 3. Expanded Location & Delivery Logic
- Renamed the "Delivery" settings tab to **"Location & Delivery"**.
- Split a single text box into highly specific, AI-readable fields:
  - **Delivery Information** (timing, cutoffs, e.g., 16-hour island-wide delivery)
  - **Delivery Tracking Instructions**
  - **Store Location Information**
  - **Google Maps Link**
- **AI Integration:** The `ai-chat` Edge Function was updated to dynamically pull all of these separate fields and inject them perfectly into the AI's system prompt, enabling the bot to flawlessly answer tracking inquiries and direct walk-in customers to the physical store.

## Setup Instructions
Please refer to `GUIDE.md` for standard environment setup and container booting instructions.
