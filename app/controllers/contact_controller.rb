# MKT-02: the contact form. Messages are kept and emailed to the team (ContactMessage); bots
# are kept out by PLT-13's guards (hidden field, form token, a rate limit per network).
class ContactController < ApplicationController
  public_page!
  layout "marketing"
  ATTEMPTS = { limit: 5, within: 10.minutes }.freeze

  def index
    @message = ContactMessage.new
  end

  def create
    return redirect_to(contact_sent_path) if honeypot_filled? # bots see the usual page

    @message = ContactMessage.new(message_params.merge(ip_address: request.remote_ip, user_agent: request.user_agent.to_s.first(255)))
    problem = AbuseProtection::PROBLEMS[form_guard_problem("contact")]
    problem ||= "We've had a lot of messages from your network. Try again in a few minutes." if too_many_attempts?("contact", **ATTEMPTS)
    @message.errors.add(:base, problem) if problem
    return render(:index, status: :unprocessable_content) if problem || !@message.valid?

    redirect_to contact_sent_path, flash: { emailed: @message.submit! }
  end

  def sent; end

  private

  def message_params = params.expect(contact_message: %i[name email business_name industry body])
end
