-- Learning progress: counts only (which lesson, which step, stars). No
-- answers, no transcripts, no timings per attempt. Kept for the life of the
-- child profile; deleted with it (ON DELETE CASCADE).

CREATE TABLE IF NOT EXISTS learning_progress (
  child_id      TEXT NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
  lesson_id     TEXT NOT NULL,
  step_index    INTEGER NOT NULL DEFAULT 0,
  completed_at  INTEGER,                             -- unix ms; NULL while in progress
  stars         INTEGER NOT NULL DEFAULT 0,
  updated_at    INTEGER NOT NULL,
  PRIMARY KEY (child_id, lesson_id)
);
CREATE INDEX IF NOT EXISTS learning_progress_child ON learning_progress (child_id, updated_at);
