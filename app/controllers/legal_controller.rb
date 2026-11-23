# MKT-03: Shadetree's legal and trust pages (LegalDocument), each with its effective date and
# change history; earlier versions stay readable.
class LegalController < ApplicationController
  public_page!
  layout "marketing"

  def index
    @documents = LegalDocument::ALL.values
  end

  def show
    @document = LegalDocument.find(params[:slug])
    @version = params[:version] ? @document.version(params[:version]) : @document.current
    raise ActiveRecord::RecordNotFound unless @version
  end
end
