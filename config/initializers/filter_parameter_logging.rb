# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Client details (CLI-01): names, phones, contact values, addresses, notes and access codes.
  :phone, :display_name, :company_name, :address, :city, :region, :postal_code, :notes, :tag_list,
  /\Aclient\.contact_methods_attributes\.\d+\.value\z/,
  # Search boxes (CLI-02 client search is by name, phone or address).
  /\Aq\z/,
  # Sending a quote (QTE-04): the client's address and the owner's note.
  /\Aquote_send\.(to|cc|subject|message)\z/,
  # Answering a quote (QTE-05): the signer's name, their email and their message or note.
  /\Aquote_response\.(signer_name|email|message)\z/,
  # The public request form (CLI-03): everything the person types.
  /\Arequest_submission\.(name|address_line\d|region|description)\z/,
  # The request inbox (CLI-04): what staff log and their internal notes.
  /\Aservice_request\.(description|timing)\z/, /\Aservice_request_note\.body\z/,
  # The contact form (MKT-02): everything the person types.
  /\Acontact_message\.(name|business_name|body)\z/
]
