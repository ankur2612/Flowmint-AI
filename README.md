<div align="center">

<img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="96" alt="FLOWMINT AI logo" />

# FLOWMINT AI

### One AI. Every Financial Action.

Talk to your money in plain words. FLOWMINT understands the request, prepares the right financial workflow, and **you approve every payment through PayPal**.

<br/>

![Flutter](https://img.shields.io/badge/Flutter-3.41-0070E0?style=for-the-badge&logo=flutter&logoColor=white)
![Gemini](https://img.shields.io/badge/Gemini-Firebase_AI_Logic-003087?style=for-the-badge&logo=googlegemini&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-Spark_(free)-009CDE?style=for-the-badge&logo=firebase&logoColor=white)
![PayPal](https://img.shields.io/badge/PayPal-Sandbox-003087?style=for-the-badge&logo=paypal&logoColor=white)
![Cost](https://img.shields.io/badge/Running_cost-₹0-0B2545?style=for-the-badge)

<sub>Built for the <b>PayPal AI Hackathon 2026</b></sub>

</div>

---

## ✨ What it does

> 💬 *"Split my dinner bill of ₹2,400 between four people."*<br/>
> 💬 *"Find a laptop under ₹60,000 for programming."*<br/>
> 💬 *"How much am I spending on subscriptions?"*

**Type, speak 🎙️ or attach a photo or PDF 📎.** Gemini identifies the intent, extracts the details and hands you a ready-to-review action. It never makes a payment on its own.

## 🧩 Six workflows, one assistant

| | Module | Highlights |
|:-:|---|---|
| ✂️ | **SmartSplit** | Equal or custom splits · tax, tip & discount · bill scanning (camera, photo, PDF) · settlement tracking · PayPal.me requests |
| 🛍️ | **AI Shopping Agent** | Natural-language search · budget-aware AI picks from real catalogue data · compare · cart · PayPal checkout |
| 📄 | **SmartQuotes** | Guided 5-step editor · AI-drafted quotations · tax & discount · Unpaid → Pending → Paid milestones · PDF export |
| 🔁 | **Subscriptions** | Fill from an invoice photo or PDF · monthly & yearly spend · category breakdown · renewal tracking |
| ↩️ | **Refund Assistant** | Receipt extraction · policy analysis · drafted requests · PayPal refunds for FLOWMINT orders |
| 💚 | **ImpactGiving** | Campaign discovery · donation checkout · verified "raised via FLOWMINT" progress |

> 🏷️ The Shopping Agent and ImpactGiving include a clearly labelled **demo catalogue** (15 sample products, 3 sample campaigns) so they can be explored before real merchants and organisations are onboarded. Demo items can never be paid for.

## 🛡️ Security by design

| Control | How |
|---|---|
| **User approval** | The AI only prepares actions; every payment goes through a review screen and PayPal's own approval page. |
| **Server-side pricing** | The backend prices orders from Firestore; amounts sent by the app are ignored. |
| **Verified payments** | *Paid* is set only after PayPal confirms the capture, never from a WebView redirect. |
| **No double charges** | Idempotency keys (a reused key with a different cart is rejected), a `CAPTURE_PENDING` lock, and PayPal-Request-Id on every call. |
| **Ownership** | Every record lives under the signed-in user's ID; Firestore rules make payment records backend-write-only. |
| **Secrets** | The PayPal secret lives only in the backend's git-ignored `functions/.secret.local`, never in the app or the repo. |
| **Documents** | Photos and PDFs are read in memory by Gemini and are never uploaded or stored. |

### ⏱️ Rate limiting

| Scope | Limit | Enforced by |
|---|---|---|
| PayPal order creation | 5 / min / user | Backend (Firestore transaction) |
| PayPal capture | 5 / min / user | Backend |
| PayPal refund | 3 / min / user | Backend |
| PayPal cancel | 10 / min / user | Backend |
| Gemini requests | 12 / min | App (plus the Firebase AI Logic per-user limit, set in the console) |
| Document size | 7 MB, images & PDF only | App |

## 🏗️ Architecture

```
┌──────────────── Flutter app · Riverpod · GoRouter · Material 3 ────────────────┐
│  Assistant ─► Gemini (structured JSON) ─► intent ─► module draft ─► user review  │
│  Firebase Auth · Cloud Firestore · Cloud Messaging · Firebase AI Logic         │
└───────────────────────────────────────┬────────────────────────────────────────┘
                                        │ callable functions
                        ┌───────────────▼───────────────┐
                        │  Python payment backend       │──► PayPal Orders · Capture ·
                        │  create · capture · refund ·  │    Refunds · Webhooks (Sandbox)
                        │  cancel · webhook             │
                        └───────────────────────────────┘
```

```
lib/
├─ app/          theme · router · navigation shell
├─ core/         payments · Gemini service · document picker · shared widgets
└─ features/     assistant · home · activity · profile · auth
                 smart_split · shopping · smart_quotes · subscriptions · refund · impact_giving
functions/       PayPal backend (Python) + unit tests
```

## 🚀 Getting started (free plan, no card)

**You need:** Flutter 3.41+, the Android SDK, Python 3.11, the Firebase CLI, a Firebase project on **Spark**, and a PayPal Developer **sandbox** app.

### 1 · Firebase
1. Register Android package `ai.flowmint.flowmint_ai` with your SHA-1 and put `google-services.json` in `android/app/` *(git-ignored)*.
2. Enable **Authentication** (Email/Password, Google), create **Firestore**, and set up **Firebase AI Logic → Gemini Developer API**.
3. **App Check → APIs → Firebase AI Logic → Unenforce** (sideloaded APKs cannot pass Play Integrity), and set the **AI Logic per-user rate limit** (about 10 / min).
4. Deploy the rules: `firebase deploy --only firestore`

### 2 · Run the app
```bash
flutter pub get
flutter run
```
Gemini model: **`gemini-3.5-flash-lite`** (free tier; verified for JSON, image and PDF input), with automatic fallback to `gemini-flash-lite-latest`.

### 3 · PayPal Sandbox (runs locally, no billing)
1. Put your sandbox keys in **`functions/.secret.local`** *(git-ignored)*:
   ```
   PAYPAL_CLIENT_ID=<paste your sandbox Client ID>
   PAYPAL_CLIENT_SECRET=<paste your sandbox Secret>
   ```
2. Set up the backend once: `cd functions && python -m venv venv && venv\Scripts\pip install -r requirements.txt`
3. Start it: `firebase emulators:start --only functions`
4. Build the app against your laptop (phone on the same Wi-Fi):
   ```bash
   flutter build apk --debug --dart-define=FUNCTIONS_EMULATOR_HOST=<laptop Wi-Fi IP>
   ```
5. Pay with the sandbox **Personal** account from PayPal → Testing Tools → Sandbox Accounts.

> On a Blaze project the same backend deploys unchanged with `firebase functions:secrets:set` and `firebase deploy --only functions`.

## 🧪 Tests

```bash
flutter analyze                                      # static analysis
flutter test                                         # money maths, AI-response validation, small-screen layouts
cd functions && venv\Scripts\python -m unittest test_main   # rate limits, idempotency, webhook validation
```

## 👥 Team

<table>
  <tr>
    <td align="center" width="220"><b>Rajeev Tiwari</b><br/><sub>Co-creator</sub></td>
    <td align="center" width="220"><b>Manas Yadu</b><br/><sub>Co-creator</sub></td>
  </tr>
</table>

---

<div align="center">
<sub>FLOWMINT AI · Flutter · Firebase · Google Gemini · PayPal Sandbox · no real money moves</sub>
</div>
