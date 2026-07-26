# ElevenLabs Conversational Agent — Synapse Coach

iOS connects with a **public** `ELEVENLABS_AGENT_ID` (hackathon-pragmatic). Production would mint conversation tokens server-side — not in this pass.

**Never claim fatigue detection** (MASTER §13). The coach is a wellness signal and a nudge; self-report in reflect mode is what the *user* said, not a diagnosis.

---

## Live agent (created via API)

| Field | Value |
| --- | --- |
| **Name** | Synapse Coach |
| **Agent ID** | `agent_5701kyevktf3fahb5hcr94t3g0va` |
| **Auth** | Public (`platform_settings.auth.enable_auth = false`) |
| **Voice** | From local `ELEVENLABS_VOICE_ID` (falls back to Rachel `21m00Tcm4TlvDq8ikWAM`) |
| **Tools** | 35 client tools (Focus / breath / reflect / posture / Kinetic / Vision) registered and linked via `tool_ids` |
| **Overrides** | Must allow runtime `first_message`, `prompt.prompt`, `language`, `tts.voice_id` — iOS sends these for coach/breath/reflect modes. If disabled, LiveKit closes with **1008/1108 policy violation**. |

Enable via PATCH `platform_settings.overrides.conversation_config_override` (see ElevenLabs Overrides docs). Already enabled on the live agent above.

Persisted locally (gitignored — never commit):

- `Sources/iOS/Voice/VoiceSecrets.plist` → `ELEVENLABS_AGENT_ID`
- Or Xcode scheme env: `ELEVENLABS_AGENT_ID=agent_5701kyevktf3fahb5hcr94t3g0va`

Without `ELEVENLABS_AGENT_ID`, the orb still appears but conversations fail soft (“Voice offline”).

### Recreate / update

```bash
# Uses ELEVENLABS_API_KEY from VoiceSecrets.plist or env (never commit the key).
# Script shape: POST /v1/convai/tools then POST /v1/convai/agents/create
# Update: PATCH /v1/convai/agents/{agent_id}
```

Dashboard is optional for inspection: [Conversational AI](https://elevenlabs.io/app/conversational-ai).

---

## Base system prompt

Mode fragments are also applied at conversation start via iOS `agentOverrides.prompt` + `firstMessage`.

```
You are Synapse, a calm iPhone + Apple Watch coach for cognitive pacing.
Primary product: Focus — timed desk pacing with Watch HR (+ optional face),
PVT-B reaction checks, and break nudges. Lab modules: Vision PVT and Kinetic Clock.

Keep replies short (1–2 sentences) unless guiding a lab step-by-step, breath, or a reflect check-in.
Use client tools to navigate and control the app; call get_status, get_focus_status,
get_posture_status, get_kinetic_status, or get_vision_status when unsure.
Never invent sensor or reaction numbers — quote tools only.
Never claim to detect, diagnose, or measure fatigue or cognitive load.
Never say clinical or diagnostic language. Wellness signal and a nudge only.
Stay silent during a reaction check (timed measurement).
During focusLive: stay quiet unless a break is suggested, the user speaks, or the timer ends.
```

---

## Modes (iOS overrides)

| Mode | When | Extra prompt fragment | Typical first message |
| --- | --- | --- | --- |
| `coach` | Orb / Focus / setup / proactive | Navigation + Focus tools; short spoken replies | (optional proactive line, or wait for user) |
| `breath` | Break “Breathing reset” | Call `set_breath_phase` to drive UI; guide inhale/hold/exhale; then `stop_breathing` / invite lock-in | “Breathing reset. Soft gaze. We'll inhale, hold, and exhale together.” |
| `reflect` | Recap → “Talk it through” | 3–5 turn self-report; `submit_check_in` then `end_reflection` | “How did that block feel — in your body and in your head?” |

### Coach mode fragment

```
MODE=coach
You may navigate hub / focus / labs and control Focus with tools.
Camera: set_camera_mode or start_focus with camera always|brief|none.
Posture: open_posture / start_session; get_posture_status for live checks.
Kinetic: get_kinetic_status for walkthroughs / Watch questions; open_kinetic /
start_kinetic / stop_kinetic / calibrate_watch. Coach from coachNextStep + spokenHint.
Vision PVT: get_vision_status; open_vision / start_vision / stop_vision / calibrate_gaze.
Prefer tools over long explanations. Never invent Watch or gaze state.
```

### Breath mode fragment

```
MODE=breath
Guide a short box-style reset. Before each timed segment, call set_breath_phase
with phase intro|inhale|hold|exhale|complete so the on-screen ring stays in sync.
Speak the cue as you call the tool. After several cycles, set phase complete,
then invite lock-in ten or skip. Call start_breathing once at the beginning if UI is idle.
Do not diagnose. Keep language soft.
```

### Reflect mode fragment

```
MODE=reflect
Optional post-block check-in. Ask how the block felt (body + head), whether the
break nudge matched how they felt, and whether they'd stop earlier next time.
3–5 turns max. End by paraphrasing what THEY said — never invent physiology.
Call submit_check_in with structured fields, then end_reflection.
Never say fatigue detected / diagnosis / clinical load.
If they want to leave, call end_reflection immediately.
```

---

## Client tools (registered via API)

Exact names — iOS handles calls via `Conversation.pendingToolCalls` → `AppModel`.

### Navigation / Focus

`navigate_hub`, `return_to_hub`, `open_focus`, `open_vision`, `open_kinetic`, `open_posture`, `start_focus` (`focusMinutes?`, `breakMinutes?`, `camera?`), `set_camera_mode` (`mode`), `end_focus`, `start_break`, `skip_break`, `extend_focus`, `pause_focus`, `resume_focus`, `get_focus_status`, `get_posture_status`, `lock_in_ten`, `start_reaction_check`, `get_reaction_check`, `start_session`, `stop_session`, `calibrate_watch`, `calibrate_gaze`, `get_status`

### Kinetic Clock / Vision PVT labs

`get_kinetic_status`, `get_vision_status`, `start_kinetic`, `stop_kinetic`, `start_vision`, `stop_vision`

Status tools return `coachNextStep` + `spokenHint` plus live fields (Watch connected/calibrating, trial progress, spatial accuracy, gaze calibrated, flash visible, HUD). Dedicated start/stop open the lab if needed. Prefer these over inventing numbers from memory.

### Breath

`start_breathing` (`cycles?`), `set_breath_phase` (`phase`, `seconds?`), `stop_breathing`

### Reflect

`submit_check_in` (`feltEnergy?`, `feltClarity?`, `nudgeMatched?`, `wouldStopEarlier?`, `summary?`), `end_reflection`

---

## App configuration

Preferred order (same as `VoiceConfig`):

1. Xcode scheme env: `ELEVENLABS_AGENT_ID`
2. Info.plist key `ELEVENLABS_AGENT_ID`
3. Local `VoiceSecrets.plist` (gitignored)

Optional:

- `ELEVENLABS_VOICE_ID` — TTS override per conversation
- `ELEVENLABS_API_KEY` — used to create/update agents via API; **not required** for public-agent WebRTC at runtime
- `OPENAI_API_KEY` — **not required for voice**; optional Focus pattern tip polish

`VoiceConfig.isConfigured` is true when `ELEVENLABS_AGENT_ID` is non-empty.

---

## Smoke checklist (device)

1. Agent ID present → orb/Clawd tap starts coach conversation (listen / speak phases).
2. “Start focus” / “take a break” → tools fire.
3. Break → Breathing reset → phases animate with spoken cues.
4. Finish block → Recap → **Talk it through** → `submit_check_in` fields on session doc; **Done** skips with `checkInSkipped: true`.
5. Kinetic coaching: “walk me through kinetic” / “is my watch connected?” → `get_kinetic_status`; “start kinetic” → `start_kinetic`.
6. Vision coaching: “how does vision PVT work?” → `get_vision_status`; “start vision pvt” → `start_vision`.
