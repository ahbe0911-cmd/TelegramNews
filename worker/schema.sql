CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY,
  update_id INTEGER NOT NULL,
  edited_at INTEGER NOT NULL,
  date INTEGER NOT NULL,
  title TEXT NOT NULL,
  text TEXT NOT NULL,
  html TEXT NOT NULL,
  url TEXT NOT NULL,
  search TEXT NOT NULL,
  important INTEGER NOT NULL DEFAULT 0,
  photo_id TEXT
);
CREATE INDEX IF NOT EXISTS posts_important_idx ON posts(important, id DESC);
