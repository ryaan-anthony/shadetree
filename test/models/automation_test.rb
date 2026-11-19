require "test_helper"

# NTF-04: rules react to core-flow events, after a delay, if their conditions still hold, and
# log what they did; safeguards against repeats, loops, suspension and plan changes.
class AutomationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @business.update!(plan_overrides: { "features" => { "automations" => true, "message_templates" => true }, "limits" => { "active_automations" => nil } })
    Current.business = @business
    @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
    @followup = MessageTemplate.create!(name: "Quote follow-up", subject: "Any questions about {{document_number}}?", body: "Hi {{client_first_name}}, just checking in.")
  end

  teardown { Current.reset }

  def quote(total: "200")
    Quote.start(client: @maria).tap do
      _1.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => total, "taxable" => "0" } ])
      _1.save!
    end
  end

  def rule(trigger: "quote_sent", delay: 3.days, conditions: { "still_open" => true }, actions: nil, **attributes)
    AutomationRule.create!(name: "Follow up", trigger:, delay_minutes: delay.to_i / 60, conditions:,
                           actions: actions || [ { "type" => "send_template", "template" => @followup.uid } ], **attributes)
  end

  def run_due
    travel 3.days + 1.minute do
      perform_enqueued_jobs(only: [ AutomationRunJob ])
      perform_enqueued_jobs(only: [ ClientMailDeliveryJob ])
    end
  end

  test "a quote sent is followed up after the delay, with the template filled in and a link to the quote" do
    rule
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    run = AutomationRun.find_by!(subject: q)
    assert_equal "scheduled", run.status
    assert_in_delta 3.days.from_now, run.run_at, 5
    perform_enqueued_jobs(only: AutomationRunJob) # not due yet: the job waits
    run_due
    assert_equal "done", run.reload.status
    assert_equal [ "send_template", "done" ], run.log.first.values_at("action", "result")
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "maria@example.com" ], mail.to
    assert_equal "Any questions about #{q.number}?", mail.subject
    assert_includes mail.text_part.body.to_s, "Hi Maria, just checking in."
    assert_includes mail.text_part.body.to_s, "View quote: http://example.com/c/"
  end

  test "conditions are re-checked when the delay ends: an approved quote isn't chased" do
    rule
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    q.reload.record_response!(:approve, by: @owner, signer_name: "Maria Lopez", message: "Phone")
    run_due
    run = AutomationRun.find_by!(subject: q)
    assert_equal "skipped", run.status
    assert_match "approved", run.log.first["detail"]
    assert_no_emails { perform_enqueued_jobs(only: ClientMailDeliveryJob) }
  end

  test "total and tag conditions" do
    rule(delay: 0, conditions: { "total_at_least" => "500" })
    small = quote(total: "100")
    small.mark_sent!(by: @owner, channel: "link")
    assert_match "under $500.00", AutomationRun.find_by!(subject: small).log.first["detail"]
    other = rule(delay: 0, conditions: { "client_tag" => "VIP" }, name: "VIP")
    @maria.update!(tags: [ "vip" ])
    big = quote(total: "900")
    big.mark_sent!(by: @owner, channel: "link")
    assert_equal %w[done done], AutomationRun.where(subject: big).order(:id).map(&:status)
    assert AutomationRun.exists?(rule: other, subject: big)
  end

  test "a client never gets the same template twice about one document, and each rule runs once per record" do
    rule(delay: 0)
    rule(delay: 0, name: "Second rule, same template", conditions: {})
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    q.mark_sent!(by: @owner, channel: "link") # sent again: no second run
    assert_equal 2, AutomationRun.where(subject: q).count
    assert_equal 1, AutomationDelivery.where(subject: q).count
    assert_match "already got", AutomationRun.where(subject: q).order(:id).last.log.first["detail"]
  end

  test "an automation's own effects don't trigger other automations" do
    rule(trigger: "quote_approved", delay: 0, conditions: {}, actions: [ { "type" => "create_job" } ], name: "Job on approval")
    rule(trigger: "quote_sent", delay: 0, conditions: {}, name: "Echo")
    Current.set(automation_run: AutomationRun.new) { quote.mark_sent!(by: @owner, channel: "link") }
    assert_equal 0, AutomationRun.count, "nothing triggers while an automation is acting"
  end

  test "approved quotes become jobs, completed jobs are invoiced and emailed, clients get tagged, the team is told" do
    rule(trigger: "quote_approved", delay: 0, conditions: {}, actions: [ { "type" => "create_job" }, { "type" => "tag_client", "tag" => "Approved" } ], name: "On approval")
    rule(trigger: "job_completed", delay: 0, conditions: {}, actions: [ { "type" => "invoice_job" }, { "type" => "notify_team", "team" => "office" } ], name: "Invoice it")
    @business.update!(auto_create_jobs: false)
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    q.reload.record_response!(:approve, by: @owner, signer_name: "Maria Lopez", message: "Phone")
    job = q.reload.job
    assert job, "the automation created the job"
    assert_includes @maria.reload.tags, "approved"
    job.complete!(by: @owner)
    invoice = job.invoices.first
    assert_equal "sent", invoice.status
    assert EmailMessage.exists?(kind: "invoice_sent", related: invoice)
    assert Notification.exists?(kind: "automation", user: @owner)
  end

  test "overdue invoices trigger once, from the hourly sweep" do
    reminder = MessageTemplate.create!(name: "Overdue", subject: "{{document_number}} is overdue", body: "Hi {{client_first_name}}")
    rule(trigger: "invoice_overdue", delay: 0, conditions: { "still_open" => true }, actions: [ { "type" => "send_template", "template" => reminder.uid } ], name: "Overdue")
    invoice = Invoice.start(client: @maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "120" } ]); _1.update!(tax_rates: []) }
    invoice.mark_sent!(by: @owner, channel: "link")
    invoice.update_columns(issued_on: @business.today - 10, due_on: @business.today - 1)
    Current.reset
    2.times { AutomationsDueJob.perform_now }
    Current.business = @business
    assert_equal 1, AutomationRun.where(subject: invoice).count
    assert_equal "done", AutomationRun.find_by!(subject: invoice).status
  end

  test "suspended businesses, switched-off rules and plans without automations don't run" do
    r = rule
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    r.update!(enabled: false)
    run_due
    assert_equal "skipped", AutomationRun.find_by!(subject: q).status
    @business.update!(plan_overrides: {})
    q2 = quote
    q2.mark_sent!(by: @owner, channel: "link")
    assert_not AutomationRun.exists?(subject: q2)
  end

  test "rules: fitting actions, a template of the business's own, and the plan's limit on active rules" do
    bad = AutomationRule.new(name: "x", trigger: "request_received", actions: [ { "type" => "invoice_job" } ])
    assert_not bad.valid?
    assert_match "doesn't fit", bad.errors.full_messages.to_sentence
    other = Current.set(business: businesses(:two)) { MessageTemplate.create!(name: "Theirs", subject: "s", body: "b") }
    assert_not AutomationRule.new(name: "x", trigger: "quote_sent", actions: [ { "type" => "send_template", "template" => other.uid } ]).valid?
    @business.update!(plan_overrides: { "features" => { "automations" => true }, "limits" => { "active_automations" => 1 } })
    rule
    second = AutomationRule.new(name: "Two", trigger: "quote_sent", actions: [ { "type" => "send_template", "template" => @followup.uid } ])
    assert_not second.valid?
    assert_match "includes 1 active automation", second.errors.full_messages.to_sentence
    second.enabled = false
    assert second.valid?, "a switched-off rule doesn't count"
  end
end
