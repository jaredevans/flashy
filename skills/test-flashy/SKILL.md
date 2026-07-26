---
name: test-flashy
description: Test that the Flashy plugin is working by triggering Stop and Notification events with flash-themed humor
user-invocable: true
---

You are testing the Flashy plugin, which flashes the terminal background when Claude finishes a turn.

**Step 1 — Trigger a Stop event (1 flash)**

Say exactly this and nothing else — do not add any other text, explanation, or follow-up:

> ⚡ Why did the flashlight go to school? Because it wanted to be a little *brighter*.
>
> (You should have just seen 1 flash. That was a **Stop event** — I finished my turn.)

Then STOP. Do not continue. Wait for the user to respond.

**Step 2 — After the user responds, present the quiz**

Regardless of what they said, say exactly this and nothing else:

> ⚡⚡ Excellent. The flash dimension grows stronger.
>
> *"You have been chosen by the Flash. But first, you must answer..."*
>
> (You should see a double-flash soon - keep your eyes on the terminal for a few moments after the next question appears!)

Then immediately use `AskUserQuestion` with this question:

- question: "What is the speed of light in a dark-mode terminal?"
- header: "Flash quiz"
- options:
  - label: "E=mc², obviously", description: "Mass times the speed of light squared"
  - label: "GPU speed", description: "However fast my GPU renders it"
  - label: "Doesn't matter", description: "I just mass-approve tool calls anyway"

Then STOP. Do not continue. Wait for the user to respond.

**Step 3 — After the user picks, deliver the final verdict**

Regardless of their choice, say exactly this and nothing else:

> ⚡⚡⚡ *The terminal flickers. A voice echoes:*
>
> "Correct. You are worthy of the flash."
>
> That was a **Notification** event — I was blocked on your answer, and Flashy double-flashed a few seconds later to say so.)
>
> Want to see the idle path? Step away from your terminal for a minute — Claude Code will notice and fire a **Notification** event (2 pulses).
>
> Flashy is working! 🔦

**Step 4 — Only if the user asks about the remaining events**

Flashy also hooks `StopFailure` (3 pulses, turn died on an API error) and `TeammateIdle` (2 pulses). Neither can be triggered on demand, but the flash itself can be checked directly:

```bash
./hooks/flash.sh error
./hooks/flash.sh idle
```
