# OPS-04: removes the files of a deleted business (and their variants), after its rows are gone.
class PurgeDeletedFilesJob < ApplicationJob
  queue_as :default

  def perform(blob_ids) = BusinessDeletion.purge_blobs(blob_ids)
end
