# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Client details (CLI-01): names, phones, contact values, addresses, notes and access codes.
  :phone, :display_name, :company_name, :address, :city, :postal_code, :notes, :tag_list,
  /\Aclient\.contact_methods_attributes\.\d+\.value\z/,
  # Search boxes (CLI-02 client search is by name, phone or address).
  /\Aq\z/
]
