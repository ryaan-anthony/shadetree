# CLI-06: runs a client import in the background, inside its business.
class ClientImportJob < ApplicationJob
  queue_as :default

  # Ids, not the record: an import is found inside its business.
  def perform(import_id, business_id)
    business = Business.find(business_id)
    Tenancy.with_business(business) do
      import = ClientImport.find(import_id)
      import.run! if import.queued?
    end
  end
end
