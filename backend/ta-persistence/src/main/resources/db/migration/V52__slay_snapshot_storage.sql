-- SlayHuud look snapshots move to object storage (Cloudflare R2). New ones
-- keep only their key here; older ones stay in the snapshot column.
ALTER TABLE slay_looks ADD COLUMN snapshot_key TEXT;
