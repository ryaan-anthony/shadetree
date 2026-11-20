# The console's home (OPS-01): where to go next. OPS-02 adds the business directory.
class Ops::DashboardController < Ops::BaseController
  def index
    @recent = AuditEntry.newest_first.includes(:business, :target_user).limit(10)
    @append_only = AuditEntry.append_only?
    @open_messages = ContactMessage.not_spam.unhandled.count # MKT-02
  end
end
