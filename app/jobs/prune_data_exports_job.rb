# INS-02: removes full-export zips once their download link expires (the log entry stays).
class PruneDataExportsJob < ApplicationJob
  queue_as :default

  def perform
    Tenancy.across_businesses(reason: "removing expired data exports") do
      DataExport.where(status: "ready", expires_at: ..Time.current).find_each(&:expire!)
    end
  end
end
