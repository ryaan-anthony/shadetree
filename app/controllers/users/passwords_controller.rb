class Users::PasswordsController < Devise::PasswordsController
  layout "marketing"
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_user_password_path, alert: "Too many reset requests. Try again in a few minutes." }
end
