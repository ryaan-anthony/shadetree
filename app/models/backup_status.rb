# PLT-09: are backups being taken, and do they restore? Every night the VM's timer
# (ops/backup/docker.sh nightly) takes a backup set, touching storage/backup/last_success once it
# is complete, then restores it into scratch databases and checks it (the restore drill), touching
# storage/backup/last_drill when that passes. /up/backup answers 503 when the backup is missing or
# older than BACKUP_MAX_AGE_HOURS (default 26: a day plus slack), or no drill has passed since it,
# for the external uptime check.
# /up stays the plain boot check the deploy and the tunnel use, so a missed backup never takes the
# site down.
class BackupStatus
  DEFAULT_MAX_AGE_HOURS = 26

  def self.dir = Pathname(ENV["BACKUP_STATUS_DIR"].presence || Rails.root.join("storage/backup"))

  def self.max_age = (ENV["BACKUP_MAX_AGE_HOURS"].presence&.then { Integer(_1, 10) } || DEFAULT_MAX_AGE_HOURS).hours

  # "ok", "stale" (no backup within max_age) or "untested" (no drill has passed since the latest
  # backup: the nightly drill failed, or a restore's backup hasn't been drilled yet).
  def self.state(now: Time.current)
    backup, drill = mtime("last_success"), mtime("last_drill")
    if backup.nil? || backup <= now - max_age then "stale"
    elsif drill.nil? || drill < backup then "untested"
    else "ok"
    end
  end

  def self.mtime(name)
    dir.join(name).mtime
  rescue SystemCallError
    nil
  end
end
