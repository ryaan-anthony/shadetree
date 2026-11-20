# PLT-09: the checks of the restore drill (ops/backup/docker.sh restore-drill), run by
# `bin/rails backup:verify_restore` in the app's own image against the scratch databases and
# storage a backup set was restored into. Nothing here writes.
#
# - the restored database has the schema (schema_migrations has rows) and at least the rows the
#   backup counted just before its dump (`expected`, from the set's counts file);
# - the newest uploaded files (up to FILES) are in storage, with the size their blob records.
class RestoreCheck
  FILES = 200
  COUNTED = %w[users businesses clients active_storage_blobs].freeze

  Result = Data.define(:lines, :failures) do
    def ok = failures.empty?
  end

  # The counts the backup records (ops/backup/backup.sh writes the same queries' results).
  def self.counts = COUNTED.index_with { ActiveRecord::Base.connection.select_value(Arel::Table.new(_1).project(Arel.star.count)).to_i }

  def initialize(expected: {})
    @expected = expected.transform_values { Integer(_1.to_s, 10) }
    @lines = []
    @failures = []
  end

  def call
    migrations = ActiveRecord::Base.connection.select_value("SELECT count(*) FROM schema_migrations").to_i
    check(migrations.positive?, "schema: #{migrations} migrations recorded")
    self.class.counts.each do |table, count|
      want = @expected[table]
      check(want.nil? || count >= want, "#{table}: #{count}#{" (the backup counted #{want})" if want}")
    end
    check_files
    Result.new(lines: @lines, failures: @failures)
  end

  private
    def check(ok, line)
      @lines << "#{ok ? "ok  " : "FAIL"} #{line}"
      @failures << line unless ok
    end

    def check_files
      service = ActiveStorage::Blob.service # local disk: the storage volume (ADR 0023)
      blobs = ActiveStorage::Blob.where(service_name: service.name).order(id: :desc).limit(FILES).to_a
      missing = blobs.reject { |blob| File.size?(service.path_for(blob.key)) == blob.byte_size }
      check(missing.empty?, "files: #{blobs.size - missing.size} of the newest #{blobs.size} uploads are in storage with their size")
    end
end
