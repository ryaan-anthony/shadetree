require "test_helper"

# PLT-09: /up/backup tells the external uptime check when backups have stopped.
class BackupHealthEndpointTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir
    @file = File.join(@dir, "last_success")
    @previous = ENV["BACKUP_STATUS_FILE"]
    ENV["BACKUP_STATUS_FILE"] = @file
  end

  teardown do
    ENV["BACKUP_STATUS_FILE"] = @previous
    FileUtils.rm_rf(@dir)
  end

  test "503 until a backup has been taken, saying nothing more" do
    get backup_health_check_path
    assert_response :service_unavailable
    assert_equal "stale", response.body
  end

  test "ok after a recent backup" do
    FileUtils.touch(@file)
    get backup_health_check_path
    assert_response :success
    assert_equal "ok", response.body
  end

  test "503 once the last backup is older than BACKUP_MAX_AGE_HOURS" do
    FileUtils.touch(@file, mtime: 27.hours.ago.to_time)
    get backup_health_check_path
    assert_response :service_unavailable

    with_env("BACKUP_MAX_AGE_HOURS" => "48") do
      get backup_health_check_path
      assert_response :success
    end
  end

  private
    def with_env(values)
      previous = values.keys.index_with { ENV[_1] }
      values.each { ENV[_1] = _2 }
      yield
    ensure
      previous.each { ENV[_1] = _2 }
    end
end
