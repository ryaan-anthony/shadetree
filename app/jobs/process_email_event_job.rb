# NTF-05: applies a stored late bounce or complaint (EmailEvent#process!), as the business that
# sent the email (enqueued inside its tenancy). Processing is once-only, so a retry is safe.
class ProcessEmailEventJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(event_id) = EmailEvent.find_by(id: event_id)&.process!
end
