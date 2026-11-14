class Users::UnlocksController < Devise::UnlocksController
  layout "marketing"
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_user_unlock_path, alert: "Too many requests. Try again in a few minutes." }
end
