# Production email needs SMTP settings and the public host for links (NTF-01, ADR 0017,
# PLT-09). Missing either doesn't stop the app booting (deploys come first), but it's said loudly.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  Rails.application.config.after_initialize do
    Rails.logger.error("[mail] SMTP_ADDRESS isn't set: no email will be sent.") if ENV["SMTP_ADDRESS"].blank?
    Rails.logger.error("[mail] APP_HOST isn't set: links in email point at example.com.") if ENV["APP_HOST"].blank?
  end
end
