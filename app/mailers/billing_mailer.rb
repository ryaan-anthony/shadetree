# BIL-05: telling a business's Owners about its plan: a trial about to end, and a move to Free
# (trial over, subscription ended, renewal unpaid after the grace period, comp ended). One email
# per Owner. Stripe sends receipts and failed-payment emails itself.
class BillingMailer < ApplicationMailer
  # Queued once the surrounding transaction (the business's lock) commits, never before.
  def self.notify_owners(business, action, **)
    users = business.business_users.active.owners.includes(:user).map(&:user).reject(&:deleted?)
    ActiveRecord.after_all_transactions_commit do
      users.each { with(business:, user: _1, **).public_send(action).deliver_later }
    end
  end

  def trial_ending
    @business, @user, @days_left = params.values_at(:business, :user, :days_left)
    return if @business.billing_status != "trialing" # subscribed since it was queued

    @plan = @business.trial_plan
    mail to: @user.email, subject: "Your #{@plan.name} trial for #{@business.name} ends in #{@days_left} #{"day".pluralize(@days_left)}"
  end

  def moved_to_free
    @business, @user, @from_plan, @reason = params.values_at(:business, :user, :from_plan, :reason)
    @free = Plan.default!
    mail to: @user.email, subject: "#{@business.name} is now on #{@free.name}"
  end
end
