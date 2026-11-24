# OPS-06: no-result help searches are kept 90 days. Runs daily (config/recurring.yml).
class PruneHelpSearchMissesJob < ApplicationJob
  queue_as :default

  def perform = HelpSearchMiss.prune!
end
