class ContactController < ApplicationController
  layout 'marketing'

  def index
    # Display the contact form
  end

  def create
    # Handle form submission
    @name = params[:name]
    @email = params[:email]
    @company = params[:company]
    @phone = params[:phone]
    @message = params[:message]

    # Here you would typically send an email or save to database
    # For now, we'll just redirect with a success message
    redirect_to contact_path, notice: 'Thank you for your message! We\'ll get back to you soon.'
  end
end
