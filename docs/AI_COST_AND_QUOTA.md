# AI Cost and Quota

All policy is backend-configurable. Plan policy supports `standard_daily_seconds`, `standard_monthly_tokens`, `live_monthly_seconds`, `live_session_max_seconds`, daily/monthly provider budgets, trial Live seconds/days, child-profile limit, and future rollover. Current launch hypotheses are defaults, not mobile constants.

“60 minutes/day” is total assisted learning, not Gemini Live. Premium Live is monthly pooled allowance stored in seconds: current hypotheses are 18,000 seconds for Premium and 36,000 for Premium Plus. Rollover defaults off.

`QuotaDO` atomically reserves Live time before credential minting and finalizes actual usage idempotently. Parallel sessions see reservations when computing remaining time, preventing pooled-quota bypass. D1 mirrors finalized monthly use for entitlement views and recovery.

Usage schema records provider/model/tier, text input/output tokens, audio input/output seconds, session seconds, Live seconds consumed, and estimated provider cost. It excludes raw audio and does not require long transcripts.

Fallback policy is Live exhausted/unhealthy → Standard; Standard exhausted/unhealthy → local. Parent surfaces may show learning time and remaining Live time; child surfaces never show tokens or provider cost.

