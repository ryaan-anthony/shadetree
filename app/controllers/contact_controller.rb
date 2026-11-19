class ContactController < ApplicationController
  layout "marketing"

  def index
    # Display the contact form
  end

  # MKT-02 builds the real form (and keeps what's sent); until then it's at least guarded like
  # the other public forms (PLT-13, AbuseProtection).
  def create
    notice = "Thank you for your message! We'll get back to you soon."
    return redirect_to(contact_path, notice:) if honeypot_filled?

    problem = AbuseProtection::PROBLEMS[form_guard_problem("contact")]
    problem ||= "We've had a lot of messages from your network. Try again in a few minutes." if too_many_attempts?("contact", limit: 5, within: 10.minutes)
    if problem
      flash.now[:alert] = problem
      return render(:index, status: :unprocessable_content)
    end

    redirect_to contact_path, notice:
  end
end
