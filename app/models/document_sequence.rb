# The counter row behind DocumentNumber. Read-only from application code; use
# business.next_document_number(kind) to take a number.
class DocumentSequence < ApplicationRecord
  belongs_to :business

  def readonly? = persisted?
end
