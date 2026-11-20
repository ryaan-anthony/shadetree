# PLT-09: are backups being taken? The nightly backup on the VM (ops/backup/docker.sh) touches a
# status file in the storage volume once a complete set has been written; /up/backup answers 503
# when that file is missing or older than BACKUP_MAX_AGE_HOURS (default 26: a daily backup plus
# slack), for the external uptime check to watch. /up stays the plain boot check the deploy and
# the tunnel use, so a missed backup never takes the site down.
class BackupStatus
  DEFAULT_MAX_AGE_HOURS = 26

  def self.status_file = Pathname(ENV["BACKUP_STATUS_FILE"].presence || Rails.root.join("storage/backup/last_success"))

  def self.max_age = (ENV["BACKUP_MAX_AGE_HOURS"].presence&.then { Integer(_1, 10) } || DEFAULT_MAX_AGE_HOURS).hours

  def self.last_success_at
    status_file.mtime
  rescue SystemCallError
    nil
  end

  def self.fresh?(now: Time.current)
    last = last_success_at
    last.present? && last > now - max_age
  end
end
