# OPS-05: resolves "Waiting on you" support tickets nobody answered, telling the member. Runs
# daily (config/recurring.yml).
class ResolveStaleSupportTicketsJob < ApplicationJob
  queue_as :default

  def perform = SupportTicket.resolve_stale!
end
