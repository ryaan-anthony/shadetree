require "test_helper"
require "rake"

# PLT-13: the contact form is guarded like the other public forms (MKT-02 rebuilds it), and the
# lockdown tasks.
class ContactFormTest < ActionDispatch::IntegrationTest
  test "the contact form has the hidden field and a form token, and refuses a fast or reused send" do
    get contact_path
    assert_select "input[name=website]"
    assert_select "input[name=form_token]"
    post contact_path, params: { name: "Ana", email: "ana@example.com", message: "Hi", **form_guard_params("contact", at: 1.second.ago) }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Check your details/
    post contact_path, params: { name: "Ana", email: "ana@example.com", message: "Hi", **form_guard_params("contact") }
    assert_redirected_to contact_path
    post contact_path, params: { name: "Bot", message: "spam", **form_guard_params("contact"), website: "x" }
    assert_redirected_to contact_path, "bots see the usual thank-you"
  end

  test "security:lockdown and security:lift_lockdown" do
    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    Rails.application.load_tasks unless Rake::Task.task_defined?("security:lockdown")
    ENV["HOURS"] = "2"
    assert_output(/lockdown for 2.0 hours/) { Rake::Task["security:lockdown"].tap(&:reenable).invoke }
    assert AbuseProtection.lockdown?
    assert_output(/Lockdown lifted/) { Rake::Task["security:lift_lockdown"].tap(&:reenable).invoke }
    assert_not AbuseProtection.lockdown?
  ensure
    ENV.delete("HOURS")
    Rails.cache = cache
  end
end
