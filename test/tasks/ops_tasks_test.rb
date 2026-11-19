require "test_helper"
require "rake"

# OPS-01: the command-line tasks, and that every way of building a database gets the audit
# log's append-only triggers.
class OpsTasksTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup { Rails.application.load_tasks unless Rake::Task.task_defined?("ops:grant") }

  def run_task(name, **env)
    env.each { ENV[_1.to_s] = _2 }
    out = StringIO.new
    $stdout, old = out, $stdout
    Rake::Task[name].reenable
    Rake::Task[name].invoke
    out.string
  ensure
    $stdout = old
    env.each_key { ENV.delete(_1.to_s) }
  end

  test "ops:grant is recorded as from the command line, once" do
    user = users(:two)
    assert_match "is an operator", run_task("ops:grant", EMAIL: user.email)
    assert Operator.for(user)
    entry = AuditEntry.find_by!(action: "operator.granted")
    assert_equal [ "command line", nil, user ], [ entry.operator_email, entry.operator_user, entry.target_user ]
    assert_match "already an operator", run_task("ops:grant", EMAIL: user.email)
    assert_equal 1, AuditEntry.where(action: "operator.granted").count
  end

  test "ops:reset_two_factor clears a locked-out operator's setup, with a reason" do
    operator = Operator.grant!(users(:one))
    operator.update!(otp_secret: Totp.random_secret, otp_started_at: Time.current, otp_enabled_at: Time.current, locked_until: 1.hour.from_now)
    assert_enqueued_email_with OperatorMailer, :two_factor_reset, params: { user: users(:one) } do
      run_task("ops:reset_two_factor", EMAIL: users(:one).email, REASON: "lost phone")
    end
    operator.reload
    assert_not operator.two_factor?
    assert_not operator.locked?
    assert_equal "lost phone", AuditEntry.find_by!(action: "operator.two_factor_reset").reason
  end

  test "a fresh database built with db:prepare has the append-only triggers" do
    base = URI(ENV.fetch("DATABASE_URL", "postgres:///shadetree_test"))
    name = "shadetree_trigger_check_#{SecureRandom.hex(4)}"
    url = base.dup.tap { _1.path = "/#{name}" }.to_s
    env = { "RAILS_ENV" => "test", "DATABASE_URL" => url, "PARALLEL_WORKERS" => "1" }
    output = IO.popen(env, [ "bin/rails", "db:prepare" ], err: [ :child, :out ], chdir: Rails.root, &:read)
    assert $?.success?, output
    conn = PG.connect(url)
    triggers = conn.exec("SELECT tgname FROM pg_trigger WHERE tgrelid = 'audit_entries'::regclass AND NOT tgisinternal ORDER BY tgname").values.flatten
    assert_equal %w[audit_entries_no_truncate audit_entries_no_update], triggers
  ensure
    conn&.close
    if name
      admin = PG.connect(base.dup.tap { _1.path = "/postgres" }.to_s)
      admin.exec("DROP DATABASE IF EXISTS #{name} WITH (FORCE)")
      admin.close
    end
  end
end
