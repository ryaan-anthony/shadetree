# CLI-06: removes the clients an import created (those with no documents yet), in the background.
class ClientImportUndoJob < ApplicationJob
  queue_as :default

  # Ids, not the record: an import is found inside its business.
  def perform(import_id, business_id)
    business = Business.find(business_id)
    Tenancy.with_business(business) do
      import = ClientImport.find(import_id)
      import.run_undo! if import.undoing?
    end
  end
end
