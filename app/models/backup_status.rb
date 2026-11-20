# PLT-09: are backups being taken, and do they restore? Every night the VM's timer
# (ops/backup/docker.sh nightly) takes a backup set, touching storage/backup/last_success once it
# is complete, then restores it into scratch databases and checks it (the restore drill), touching
# storage/backup/last_drill when that passes. /up/backup answers 503 when either is missing or
# older than BACKUP_MAX_AGE_HOURS (default 26: a day plus slack), for the external uptime check.
# /up stays the plain boot check the deploy and the tunnel use, so a missed backup never takes the
# site down.
class BackupStatus
  DEFAULT_MAX_AGE_HOURS = 26

  def self.dir = Pathname(ENV["BACKUP_STATUS_DIR"].presence || Rails.root.join("storage/backup"))

  def self.max_age = (ENV["BACKUP_MAX_AGE_HOURS"].presence&.then { Integer(_1, 10) } || DEFAULT_MAX_AGE_HOURS).hours

  # "ok", "stale" (no recent backup) or "untested" (a recent backup, but no recent drill that passed).
  def self.state(now: Time.current)
    if !recent?("last_success", now) then "stale"
    elsif !recent?("last_drill", now) then "untested"
    else "ok"
    end
  end

  def self.recent?(name, now)
    dir.join(name).mtime > now - max_age
  rescue SystemCallError
    false
  end
end
