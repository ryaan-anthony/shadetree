# PLT-10: a failure no retry_on/discard_on handles reaches Rails.error here, whichever adapter
# runs the job (Solid Queue reports it too; Rails.error reports each exception once).
# Observability::ErrorContext adds the job class, id and business. ApplicationJob and the mail
# delivery jobs (which inherit from Action Mailer's job instead) include it.
module ReportsUnhandledErrors
  def perform_now
    super
  rescue => error
    Rails.error.report(error, handled: false, source: "application.active_job")
    raise
  end
end
