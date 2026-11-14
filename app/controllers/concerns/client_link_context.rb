# Client-facing pages reached by a secret link (quotes, invoices, booking). The token is the
# only credential: look the record up across businesses, then act as its business for the
# rest of the request. See HasPublicToken (PLT-08) and ADR 0014.
#
#   class Client::QuotesController < ApplicationController
#     include ClientLinkContext
#     def show = @quote = find_by_client_link!(Quote, params[:token])
#   end
module ClientLinkContext
  extend ActiveSupport::Concern

  private

  def find_by_client_link!(model, token)
    record = Tenancy.across_businesses(reason: "client link #{model.name}") do
      model.find_by!(public_token: token.to_s)
    end
    Current.business = record.business
    @business = record.business
    record
  end
end
