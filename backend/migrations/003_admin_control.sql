CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS config_versions (
 id TEXT PRIMARY KEY, domain TEXT NOT NULL, target_id TEXT NOT NULL,
 version INTEGER NOT NULL, payload TEXT NOT NULL, checksum TEXT NOT NULL,
 actor TEXT NOT NULL, published_at TEXT NOT NULL,
 UNIQUE(domain,target_id,version)
);
CREATE TABLE IF NOT EXISTS change_sets (
 id TEXT PRIMARY KEY, domain TEXT NOT NULL, target_id TEXT NOT NULL,
 payload TEXT NOT NULL, draft_version INTEGER NOT NULL, status TEXT NOT NULL,
 actor TEXT NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS change_previews (
 id TEXT PRIMARY KEY, change_id TEXT NOT NULL, actor TEXT NOT NULL,
 draft_version INTEGER NOT NULL, payload_hash TEXT NOT NULL,
 base_revision INTEGER NOT NULL, expires_at TEXT NOT NULL, result TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS admin_audit (
 id TEXT PRIMARY KEY, actor TEXT NOT NULL, role TEXT NOT NULL, operation TEXT NOT NULL,
 entity_id TEXT NOT NULL, before_redacted TEXT NOT NULL, after_redacted TEXT NOT NULL,
 reason TEXT NOT NULL, occurred_at TEXT NOT NULL, request_id TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS correction_cases (
 id TEXT PRIMARY KEY, payload TEXT NOT NULL, actor TEXT NOT NULL, status TEXT NOT NULL,
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS permission_grants (
 username TEXT NOT NULL REFERENCES accounts(username), permission TEXT NOT NULL,
 issuer TEXT NOT NULL, granted_at TEXT NOT NULL, PRIMARY KEY(username,permission)
);
CREATE TABLE IF NOT EXISTS admin_jobs (
 id TEXT PRIMARY KEY, type TEXT NOT NULL, status TEXT NOT NULL, actor TEXT NOT NULL,
 created_at TEXT NOT NULL, result TEXT NOT NULL
);
INSERT OR IGNORE INTO schema_migrations VALUES(3, CURRENT_TIMESTAMP);
