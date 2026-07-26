# Synapse — Pitch Slide Brief

**Purpose:** Feed this entire file to a slide / presentation AI. It is the single narrative source for a Synapse pitch deck.

**Suggested output:** 6–8 slides (max 10). Dark charcoal + teal. Sparse. One job per slide.

**Do not invent** features, accuracy %, clinical validation, or claim fatigue detection.

---

## Instruction to the slide AI

Read this Synapse brief as source of truth. Build a calm dark charcoal + teal deck (6–8 slides).

**Origin:** a room of hackers grinding — we forget our health while locking in; health directly drives productivity.

**Product:** consumer healthcare for people who need to lock in — three surfaces:
1. Phone + Watch — in-session pacing + PVT honesty check
2. Conversational voice recap — life context / health↔focus patterns
3. Web dashboard — fine-grained deep dive (Focus timeline: fade score, HR, phase, per-channel signals, pacing report)

Be honest that deep pattern intelligence is early but the loop, voice check-in, and dashboard exist. No fatigue-detection claims, no purple AI aesthetics, no red alarms.

**Motifs:** dashed baseline ring · teal → sand → amber warmth · RT delta numbers · voice orb · dashboard timeline as the “microscope.”

**Brand on title:** “Synapse” must be hero-level — not a tiny nav label.

---

## Core thesis

Your health directly impacts your productivity. Synapse is consumer healthcare for people who need to lock in and focus — it paces you in the moment, then starts capturing the patterns that explain why some blocks soar and others fall apart.

| Pillar | Meaning |
| --- | --- |
| In-session | Pace before you crash |
| Voice recap | Context after every block |
| Dashboard | Fine-grained deep dive |
| Phone + Watch | No extra hardware |

---

## 1. The idea in one breath

Synapse is an iPhone + Apple Watch companion for people who live in deep work — hackers, builders, students, founders — and keep treating their body as an afterthought. It looks like a Pomodoro timer so it’s instantly usable. Underneath, it is healthcare for focus:

- During a block it learns your physiological baseline and nudges a break when you drift
- Across blocks it starts to recognize patterns — times of day, habits, recovery — that affect how well you can lock in
- A conversational voice agent runs the post-session recap so the system doesn’t only see sensors; it hears what you did, how you slept, how you feel
- When you want to go deeper, a web dashboard shows fine-grained session data — epoch-by-epoch fade score, heart rate, phase, and per-channel signal breakdown — not just the phone’s summary card

### One-liner

> Consumer healthcare for people who need to lock in — phone + Watch pace you against your own baseline, a voice recap captures context, and a web dashboard lets you dig into the fine-grained physiology of every block.

### Category

| Is | Is not |
| --- | --- |
| Consumer healthcare — cognitive pacing + personal health↔productivity insight | A dumb timer with a glow |
| | A hospital platform |
| | A diagnostic claim |
| | “AI that knows your brain is tired” |

### Three surfaces

| Surface | Job |
| --- | --- |
| **Phone + Watch** | In-block pacing HUD, break nudge, PVT-B, pattern tips. The companion you live in while locking in. |
| **Voice recap** | Conversational check-in after the block — context sensors can’t see (sleep, stress, what you were building, did the nudge match). |
| **Web dashboard** | Deep dive: live Focus timeline, epoch-level fade / HR / phase, channel panels, pacing report. |

### Why this is healthcare, not another productivity app

Productivity apps tell you to try harder. Synapse treats the body as the constraint. Lock-in is the job; health is the system that makes the job possible. Sensing and patterns exist so you stop guessing why yesterday worked and today didn’t.

---

## 2. Where the idea came from

It started in a room full of hackers. Everyone grinding — startups, side projects, all-nighters, another push before the deadline. Looking around, the thought was simple: **we need to be more aware of our own health.**

We’re so busy creating that we forget the thing that actually decides whether any of it sticks. Health isn’t separate from productivity. It is upstream of it. If you’re locking in for hours and ignoring sleep, stress, recovery, and the moment your body is asking for a pause, you don’t get more output — you borrow it from tomorrow.

| | |
| --- | --- |
| **The observation** | A room of people whose identity is focus — and almost no tooling that treats their physiology as part of the craft. |
| **The belief** | Health directly impacts the ability to lock in. Care for that loop and you protect both the person and the work. |
| **The product** | Meet them where they already are — a focus block — then add pacing, measurement, voice context, patterns over time, and a dashboard for the deep dive. |

### Why a Pomodoro surface

Builders already know the ritual. Synapse doesn’t invent a new behavior from scratch — it hijacks a familiar one and makes it health-aware. The timer is the door. The body and the pattern engine are the product.

---

## 3. Who it’s for

**Primary:** people who **really need to lock in** — hackers, founders, students, knowledge workers in deep-work mode — who are busy enough that health slips, and whose output quietly depends on the thing they’re ignoring.

They don’t need another streak counter. They need a companion that respects the craft of focus and the biology underneath it.

**Same mechanism, higher stakes:** people with energy-limiting conditions (long COVID / ME-CFS, post-concussion return-to-work), where overrunning a limit can cost days, not just an afternoon. Synapse stays a wellness companion and a nudge — never a diagnosis — but this is why “just take a break when you feel tired” is not a universal answer.

### Jobs to be done

| Job | Today’s workaround | Why it fails |
| --- | --- | --- |
| Stop before the crash while locking in | Gut feel / fixed Pomodoro | Gut is late; clocks ignore your body today |
| Understand what in my health affects focus | Memory, notes, vibes | No structured link between sessions and context |
| Learn my productive windows | Guessing / calendar myths | No measured fade / RT history by time of day |
| Capture why a block went well or badly | Nothing, or a journal you’ll skip | Friction; voice recap is the low-friction capture |
| See the fine-grained physiology | Phone summary only | Need a dashboard microscope |

---

## 4. The problem

High-agency people optimize projects, not physiology. The culture of building rewards ignoring the body until it bills you. Timers help you sit still; they don’t tell you when you’re drifting, and they don’t accumulate the story of what makes you sharp on Tuesday and useless on Thursday.

| Lens | Pain |
| --- | --- |
| **In the moment** | You keep going past the useful edge. A false break costs ~90 seconds. A missed one costs the afternoon. |
| **Across days** | You don’t know whether mornings beat afternoons, or whether short sleep / coffee / stress is the real variable — because nobody captured it with the session. |
| **Category gap** | Productivity apps ignore the body. Health apps ignore the focus block. Synapse sits in the join: healthcare for people whose job is to lock in. |

---

## 5. The solution (two timescales)

Synapse is one companion with two jobs: protect the current block, and get smarter about you across blocks. Everything dismissible. Nothing that lectures harder than it listens.

### Product loop

```
PVT-B → Baseline → Focus → Break → PVT-B → Voice recap → Patterns
```

Measure → learn baseline → work → break → measure again → talk it through → patterns that compound. Dashboard available anytime to scrub the fine grain.

### In-session HUD states (exact copy)

| State | On screen | Color | Meaning |
| --- | --- | --- | --- |
| Calibrating | “Learning your baseline · N%” + dashed ring | Cool teal | Learning you for this block |
| Steady | “Steady” | Teal `#59B7AD` | Inside your band — keep locking in |
| Warning | “Easing off” · “Drifting from your baseline” | Sand `#D9B36B` | Finish the thought; a break is coming |
| Break | “Break suggested” | Amber `#ED8F4D` | Pause now costs less than pushing through |

Escalation is by warmth (teal → sand → amber). **No reds. No alarm aesthetics.** Never say “fading” on slides — the screen says “Easing off.”

### What we measure in a block (honest claim)

**Never claim we detect fatigue.** Output is a wellness nudge — “take a break” — not a diagnosis. We watch cheap physiological proxies against your own baseline and flag when they move together.

| Proxy | Approx weight |
| --- | --- |
| Watch HR vs session baseline | ~45% |
| Face arousal (on-device) | ~40% |
| Wrist stillness / fidget (IMU 100 Hz) | ~15% |

Missing channels drop out; weights renormalise.

**Optional PVT-B bookend** (Basner, Mollicone & Dinges, 2011) — published brief psychomotor vigilance test:
- 60 s run
- ISI 1–4 s
- Lapse ≥ **355 ms** (not 500 — deliberate for the brief protocol)
- Anticipation floor **100 ms** (faster = false start)
- Recap leads with within-person RT delta (e.g. 280 → 340 ms, two lapses)
- Tuned to **over-nudge** on purpose — asymmetry of cost

---

## 6. The big bet — patterns over time

The memorable product isn’t only “it stopped me.” It’s: **Synapse starts to know what in your health and routine affects your ability to lock in.**

Maybe you’re sharper mid-morning. Maybe afternoons fade unless you break earlier. Maybe after certain habits the fade score or reaction check tells a different story. Long game: recognize patterns, highlight them, make them actionable.

### What’s already real (seed)

- Local session history → heuristic pattern tips on Hub / Recap (e.g. morning vs afternoon fade rates)
- Optional OpenAI polish for tip wording (not the voice path)
- ElevenLabs conversational agent with **reflect** mode — post-block talk-through + `submit_check_in` so context is captured in conversation, not a form
- Physiology + PVT delta on the recap card

### Vision (not fully shipped — say so)

- Richer longitudinal maps: time-of-day envelopes, recovery / sleep / stress tied to session quality
- “After X, your lock-in holds longer” style highlights — still wellness, never diagnosis
- Cross-session trends UI; longer pattern store
- HRV to separate “stressed” from “fading”

### Why the conversational agent exists

Sensors see the body. The voice recap hears the life around the body — sleep, caffeine, stress, what you were building, whether the nudge felt right. Physiology and PVT are the body; the talk-through is how you teach the system what the numbers meant.

| Pattern question | Inputs | User-facing highlight |
| --- | --- | --- |
| When am I sharpest? | Start hour + fade count + focused minutes | “You fade more after 14:00 — protect afternoons.” |
| Did this block cost me? | Pre/post PVT-B median + lapses | “280 → 340 ms, two lapses.” |
| What was going on in my life? | Voice reflect / check-in | Spoken context attached to the session |
| What should I try next? | History heuristics | Short coaching lines on Hub / Recap |
| Show me the fine grain | Session epochs in Firestore | Web dashboard timeline + channels |

---

## 7. Web dashboard — the deep dive

The phone is optimized for the ritual: calm HUD, break nudge, short recap. The **web dashboard** is for people who want to look deeper into their data. Live sessions stream from the phone (sole Firebase writer) into a Focus timeline with far more fine-grained detail than the mobile summary.

### What the dashboard shows

- **Focus timeline** — epoch stream with fade score, heart rate, phase ribbon (focus / easing / break), fade events in time
- **Signal panels** — per-channel breakdown (HR, arousal, motion), including when a channel dropped out or sat below the noise floor
- **Pacing report** — structured read of how the block unfolded
- Live Firestore + offline `/demo/focus` fail-safe

### Surface division

| Surface | Role |
| --- | --- |
| **Phone** | Act in the moment — start, sense, break, PVT, voice. Reaction check stays a phone-screen moment (dashboard deliberately does **not** render PVT). |
| **Voice** | Capture life context after the block |
| **Dashboard** | Inspect physiology at epoch resolution — evidence, not just a nudge |

**URLs:** https://synapse-clinical-hz.web.app · QR: https://synapse-clinical-hz.web.app/qr

**Pitch angle:** Phone = companion. Dashboard = microscope. Same session data; different jobs.

---

## 8. Market & competition

| | Timers / Focus apps | Health wearables | Synapse |
| --- | --- | --- | --- |
| Job | Sit still for N minutes | Log recovery / HR after the fact | Pace the lock-in + learn health↔focus |
| Hardware | Phone | Often dedicated band / ring | Phone + Watch you own |
| In-block interrupt | Clock only | Rarely | Yes — physiology vs your baseline |
| Context capture | None | Manual journaling | Voice recap after the block |
| Deep data | Almost none | Trends dashboards | Web Focus timeline · epoch / channel detail |
| Honesty check | Streaks | Trends alone | PVT-B on phone + pattern tips |

**Visible** validates paid HR-based pacing for long COVID (armband, mostly after-the-fact). Synapse’s wedge: no extra hardware, interrupt during the block, voice context, and a dashboard for the fine grain — not just yesterday’s log.

---

## 9. What’s real today

### Shipped

- Focus loop: setup → live HUD → break → recap
- Baseline learning + Steady / Easing off / Break suggested
- Watch HR + face + motion composite
- PVT-B bookend + delta-led recap
- Pattern tips from session history
- ElevenLabs orb: coach / breath / reflect check-in
- Web dashboard: live Focus timeline, signal panels, pacing report, `/demo/focus`
- Watch-only + camera modes; phone → Firestore writer

### Honest gaps

- Full “health factor → productivity” graph is early — tips + check-in are the seed
- HRV not in yet
- Cross-session trends UI still thin
- Never invent accuracy % or clinical validation

---

## 10. Brand & visual language

**Mood:** dark, calm, clinical-quiet — healthcare that respects deep work. Not neon productivity, not purple AI slop. Escalation by warmth, never red alarms.

| Token | Approx hex | Role |
| --- | --- | --- |
| Canvas top / mid | `#0B1216` / `#060A0E` | Cool charcoal backgrounds |
| Teal accent | `#59B7AD` | Brand, Steady, orb, CTAs |
| Sand | `#D9B36B` | Easing off |
| Amber | `#ED8F4D` | Break suggested |
| Muted / body | white ~38% / ~55% | Labels and copy |

### Do

- Hero “Synapse”; sparse slides; one job each
- Show both timescales: in-block pace + over-time patterns
- Show three surfaces: phone, voice, dashboard
- Dashed baseline ring + RT delta as motifs
- Voice orb as recap / coaching character
- Dashboard timeline as microscope visual

### Don’t

- Claim fatigue detection or clinical-grade AI
- Pretend the full pattern brain is finished
- Purple gradients, emoji, red panic UI
- Open as “just another Pomodoro”

---

## 11. Language kit

### Say

- “We looked at a room of people locking in and realized health isn’t optional for that craft — it decides the craft.”
- “In the moment we pace you against your own baseline. Over time we start highlighting what in your health and routine affects your focus.”
- “The voice recap is how you teach Synapse what the sensors can’t see.”
- “If you want the microscope, the web dashboard has the fine-grained timeline — fade score, HR, channels, epoch by epoch.”
- “We over-nudge on purpose. Ninety seconds vs the afternoon.”

### Never say

- we detect cognitive fatigue / AI knows your brain is tired
- clinically validated / clinical-grade / invented accuracy %
- diagnoses burnout
- implying the longitudinal pattern engine is fully shipped
- lapse threshold of 500 ms (ours is **355 ms**)
- “fading” as HUD copy (say **Easing off**)

---

## Suggested slide outline (optional — AI may compress)

1. **Title** — SYNAPSE · healthcare for people who lock in · dark teal wash
2. **Origin** — room of hackers · health upstream of productivity
3. **Problem** — timers ignore the body · no map of what affects focus
4. **Solution loop** — baseline → pace → break → measure → voice → patterns
5. **Three surfaces** — phone companion · voice context · dashboard microscope
6. **Patterns + honesty** — health↔focus over time · PVT delta · over-nudge
7. **Close** — one-liner · live demo / dashboard QR

---

*Narrative brief for creative / slide tools. Implementation SoT: `docs/MASTER.md`. Visual companion canvas: `synapse-shark-tank-brief.canvas.tsx`.*
