# Meshy Credit Ledger

Every credit-consuming Meshy operation is recorded here **before** it is run, and updated after.
No generation task may be created that does not appear in this table.

**Running total spent by this session: 0 credits.**

Standing rules (owner-set):
- One approval covers **one operation**. Approving Remesh does not approve Rigging; approving
  Rigging does not approve Animation; a retry needs a new approval.
- Silence is not approval. Only an explicit "approved" / "approve" / "ok generate" / "ตกลง" /
  "อนุมัติ" counts.
- Zero-credit work (local inspection, prompt drafting, integration, tests, renders, docs, and
  reading the free animation library) needs no approval.

| # | Date | Asset | Operation | Endpoint | Est. credits | Actual | Outcome | Accepted? | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-09-18 | Baby standing (`baby_standing_v01`) | Remesh, `target_polycount 8000`, `topology quad`, `glb` | `POST /openapi/v1/remesh` | unpublished (ceiling **10**) | — | **APPROVED, NOT RUN — BLOCKED** | — | Owner approved 2026-09-18, max 10 credits, one operation. **Not executed:** `MESHY_API_KEY` is absent from this shell, `zsh -l` and `bash -l`, so no call can be made. `input_task_id` also still unresolved (needs the zero-credit list call, which needs the key). Ready to run: `tools/meshy_find_task.sh 0918083052` then `tools/meshy_remesh.sh <id>`. |

## Known costs, from the API docs

| Operation | Cost |
|---|---|
| Remesh | **not published** — the response carries `consumed_credits`, so the true figure is only knowable after the first run |
| Rigging | **5 credits**, and **includes Walking + Running clips** |
| Animation, per action | **3 credits** (1–10 actions per request, 3 each) |
| Animation library listing | **free** |

The unpublished remesh cost is the reason operation #1 carries a **maximum authorised** figure
rather than an estimate — see the approval request.
