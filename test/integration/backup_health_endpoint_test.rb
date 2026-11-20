require "test_helper"

# PLT-09: /up/backup tells the external uptime check when backups, or their nightly restore
# drill, have stopped.
class BackupHealthEndpointTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir
    @previous = %w[BACKUP_STATUS_DIR BACKUP_MAX_AGE_HOURS].index_with { ENV[_1] }
    ENV["BACKUP_STATUS_DIR"] = @dir
  end

  teardown do
    @previous.each { ENV[_1] = _2 }
    FileUtils.rm_rf(@dir)
  end

  test "503 stale until a backup has been taken, saying nothing more" do
    get backup_health_check_path
    assert_response :service_unavailable
    assert_equal "stale", response.body
  end

  test "503 untested after a backup whose drill hasn't passed, ok once it has" do
    touch "last_success"
    get backup_health_check_path
    assert_response :service_unavailable
    assert_equal "untested", response.body

    touch "last_drill"
    get backup_health_check_path
    assert_response :success
    assert_equal "ok", response.body
  end

  test "stale once the backup is older than BACKUP_MAX_AGE_HOURS" do
    touch "last_success", 27.hours.ago
    touch "last_drill", 27.hours.ago
    get backup_health_check_path
    assert_equal "stale", response.body

    ENV["BACKUP_MAX_AGE_HOURS"] = "48"
    get backup_health_check_path
    assert_equal "ok", response.body
  end

  test "untested when the last passing drill is older than the latest backup" do
    touch "last_drill", 2.hours.ago
    touch "last_success", 1.hour.ago
    get backup_health_check_path
    assert_response :service_unavailable
    assert_equal "untested", response.body
  end

  private
    def touch(name, at = Time.current) = FileUtils.touch(File.join(@dir, name), mtime: at.to_time)
end
