require "test_helper"

# PLT-10: one JSON line per request, with request id, status, duration and business, and no
# passwords, tokens or client contact details anywhere in the log.
class StructuredLogsTest < ActionDispatch::IntegrationTest
  include ClientLinkDocumentHelpers

  setup do
    @config = Rails.configuration.x.observability
    @saved = @config.to_h.slice(:structured_logs, :slow_request_ms)
    @config.structured_logs = true
    @business = businesses(:one)
  end

  teardown { @saved.each { |key, value| @config[key] = value } }

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::TaggedLogging.logger(io).tap { _1.level = :info } # production's level
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  def json_lines(log, event)
    log.lines.filter_map { _1[/\{"event".*\}/] }.map { JSON.parse(_1) }.select { _1["event"] == event }
  end

  test "signing in logs one request line and neither the email nor the password" do
    log = capture_log { post user_session_path, params: { user: { email: users(:one).email, password: "password123" } } }

    assert_no_match "password123", log
    assert_no_match users(:one).email, log
    assert_no_match "Started POST", log # the client IP's line is gone
    line = json_lines(log, "request").sole
    assert_equal response.headers["X-Request-Id"], line["request_id"]
    assert_equal [ "POST", "/users/sign_in", "public", 303 ], line.values_at("method", "path", "area", "status")
    assert_kind_of Numeric, line["duration_ms"]
  end

  test "staff requests carry the business and client details stay out" do
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    client = { display_name: "Zelda Quartermaine", tag_list: "Weekly",
               contact_methods_attributes: { "0" => { kind: "email", value: "zelda.q@example.net" }, "1" => { kind: "phone", value: "(555) 019-8877" } },
               properties_attributes: { "0" => { address_line1: "77 Juniper Hollow", city: "Elkmoor", region: "WY", postal_code: "82001",
                                                 country: "US", access_notes: "Gate code 4321", billing: "1" } } }
    log = capture_log { post admin_clients_path, params: { client: } }

    [ "Zelda", "Quartermaine", "zelda.q", "019-8877", "Juniper", "Elkmoor", "\"WY\"", "82001", "4321" ].each { assert_no_match _1, log }
    line = json_lines(log, "request").sole
    assert_equal [ "staff", @business.id, users(:one).id ], line.values_at("area", "business_id", "user_id")
    assert_equal "Admin::ClientsController#create", line["controller"]
  end

  test "client link tokens are blanked in the path" do
    create_test_document_table
    link = as_business(@business) { ClientLink.issue!(create_test_document(@business), actions: %w[approve]) }
    log = capture_log { get client_link_path(link.token) }

    assert_no_match link.token, log
    line = json_lines(log, "request").sole
    assert_equal [ "/c/[FILTERED]", "client", @business.id, 200 ], line.values_at("path", "area", "business_id", "status")
  end

  test "with structured logs off only slow requests are logged, as warnings" do
    @config.structured_logs = false
    assert_empty json_lines(capture_log { get root_path }, "request")

    @config.slow_request_ms = 0
    log = capture_log { get root_path }
    assert_match(/WARN|\{"event":"request"/, log)
    assert json_lines(log, "request").sole["slow"]
  end
end
