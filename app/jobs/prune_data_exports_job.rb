# INS-02: removes full-export zips once their download link expires (the log entry stays), and
# marks builds that stopped (a deploy) as failed.
class PruneDataExportsJob < ApplicationJob
  queue_as :default

  def perform
    Tenancy.across_businesses(reason: "removing expired data exports") do
      DataExport.where(status: "ready", expires_at: ..Time.current).find_each(&:expire!)
      DataExport.where(status: "building", updated_at: ...DataExport::STALE_AFTER.ago).find_each(&:give_up_if_stale!)
    end
  end
end
