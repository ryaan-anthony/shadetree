# A non-guessable identifier for links clients open without signing in (quotes, invoices,
# booking). 24 random base58 characters (about 140 bits); never derived from the record id.
#
#   class Quote < ApplicationRecord
#     include HasPublicToken   # needs a unique string column `public_token`
#   end
#
#   quote.public_token                   # => "pXk3…"
#   Quote.find_by_public_token!(token)   # raises ActiveRecord::RecordNotFound when unknown
#
# Staff URLs keep integer ids, scoped to the current business (PLT-06).
module HasPublicToken
  extend ActiveSupport::Concern

  LENGTH = 24

  included do
    has_secure_token :public_token, length: LENGTH
  end

  class_methods do
    def find_by_public_token!(token)
      raise ActiveRecord::RecordNotFound unless token.is_a?(String) && token.length == LENGTH

      find_by!(public_token: token)
    end
  end
end
