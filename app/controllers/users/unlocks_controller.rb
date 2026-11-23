class Users::UnlocksController < Devise::UnlocksController
  public_page! # the link in the unlock email (#378)
  # OPS-03: what support may do while viewing as a member
  impersonation :blocked # account settings
  layout "marketing"
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_user_unlock_path, alert: "Too many requests. Try again in a few minutes." }
end
