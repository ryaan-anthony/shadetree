# CLI-06: uploaded client lists are personal data. An upload left at the mapping step for
# ABANDONED_AFTER is deleted with its file; finished imports keep only their counts and the rows
# that didn't go in (their file is removed when they finish), and lose those rows too once undo
# is no longer possible. An import whose job was lost is started again.
class PruneClientImportsJob < ApplicationJob
  queue_as :default

  ABANDONED_AFTER = 2.days

  def perform
    Tenancy.across_businesses(reason: "pruning abandoned client imports") do
      ClientImport.where(status: "mapping", updated_at: ...ABANDONED_AFTER.ago).find_each do |import|
        import.file.purge
        import.destroy!
      end
      ClientImport.where(status: %w[finished failed undone], finished_at: ...ClientImport::UNDO_WINDOW.ago).where.not(problems: []).update_all(problems: [])
      # Running with no progress for an hour: its job was lost. Both jobs carry on where they stopped.
      ClientImport.where(status: %w[queued importing], updated_at: ...1.hour.ago).find_each { ClientImportJob.perform_later(_1.id, _1.business_id) }
      ClientImport.where(status: "undoing", updated_at: ...1.hour.ago).find_each { ClientImportUndoJob.perform_later(_1.id, _1.business_id) }
    end
  end
end
