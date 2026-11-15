namespace :clients do
  desc "Rebuild every client's search text (CLI-02), e.g. after a bulk import or data fix"
  task reindex_search: :environment do
    Tenancy.across_businesses(reason: "clients:reindex_search") do
      Client.unscoped.in_batches(of: 1_000) { |batch| Client.refresh_search_text(batch.ids) }
    end
    puts "Rebuilt search text for #{Client.unscoped.count} clients."
  end
end
