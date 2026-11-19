class Users::PasswordsController < Devise::PasswordsController
  # OPS-03: what support may do while viewing as a member
  impersonation :blocked # account settings
  layout "marketing"
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_user_password_path, alert: "Too many reset requests. Try again in a few minutes." }

  # A reset signs out every browser (Devise checks the password's salt); end their sessions in
  # the list too, before this browser is signed in (ACC-06).
  def update
    super do |user|
      user.user_sessions.active.update_all(revoked_at: Time.current) if user.errors.empty?
    end
  end
end
