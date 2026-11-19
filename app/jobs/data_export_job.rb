# INS-02: builds a full-account export in the background, inside its business.
class DataExportJob < ApplicationJob
  queue_as :default

  def perform(export_id, business_id)
    Tenancy.with_business(Business.find(business_id)) do
      export = DataExport.find(export_id)
      export.build! if export.building?
    end
  end
end
