# A stand-in document for client link tests until real documents (quotes, invoices) exist.
module ClientLinkDocumentHelpers
  class TestDocument < ApplicationRecord
    self.table_name = "client_link_test_documents"
    include BusinessOwned

    def client_link_partial = "client_links/documents/test_document"
    def client_link_expires_at = 30.days.from_now
  end

  VIEW_PATH = File.expand_path("views", __dir__)

  def create_test_document_table
    ActiveRecord::Base.connection.create_table :client_link_test_documents, temporary: true do |t|
      t.references :business, null: false
      t.string :uid, null: false
      t.string :title
    end
    TestDocument.reset_column_information
    ActionController::Base.prepend_view_path(VIEW_PATH) unless ActionController::Base.view_paths.map(&:to_s).include?(VIEW_PATH)
  end

  def create_test_document(business, title: "Spring cleanup")
    as_business(business) { TestDocument.create!(title:) }
  end
end
