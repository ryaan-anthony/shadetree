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

  # Runs with no delay still go through a job, so a failing automation never breaks the request.
  def now(&) = perform_enqueued_jobs(only: AutomationRunJob, &)

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
    now { small.mark_sent!(by: @owner, channel: "link") }
    assert_match "under $500.00", AutomationRun.find_by!(subject: small).log.first["detail"]
    other = rule(delay: 0, conditions: { "client_tag" => "VIP" }, name: "VIP")
    @maria.update!(tags: [ "vip" ])
    big = quote(total: "900")
    now { big.mark_sent!(by: @owner, channel: "link") }
    assert_equal %w[done done], AutomationRun.where(subject: big).order(:id).map(&:status)
    assert AutomationRun.exists?(rule: other, subject: big)
  end

  test "a client never gets the same template twice about one document, and each rule runs once per record" do
    rule(delay: 0)
    rule(delay: 0, name: "Second rule, same template", conditions: {})
    q = quote
    now do
      q.mark_sent!(by: @owner, channel: "link")
      q.mark_sent!(by: @owner, channel: "link") # sent again: no second run
    end
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
    rule(trigger: "invoice_sent", delay: 0, conditions: {}, name: "Echo on invoice")
    @business.update!(auto_create_jobs: false)
    q = quote
    now do
      q.mark_sent!(by: @owner, channel: "link")
      q.reload.record_response!(:approve, by: @owner, signer_name: "Maria Lopez", message: "Phone")
    end
    job = q.reload.first_job
    assert job, "the automation created the job"
    assert_includes @maria.reload.tags, "approved"
    now { job.complete!(by: @owner) }
    invoice = job.invoices.first
    assert_equal "sent", invoice.status
    assert EmailMessage.exists?(kind: "invoice_sent", related: invoice)
    notice = Notification.find_by!(kind: "automation", user: @owner)
    assert_equal "Invoice it: #{job.number}", notice.title, "notices name the record, not the client"
    assert_not AutomationRun.exists?(subject: invoice), "the invoice an automation sent doesn't start another automation"
    assert_no_match "Maria", AutomationRun.pluck(:log).to_s, "logs don't keep the client's name"
  end

  test "a completed job that comes to $0.00 gets a draft invoice, not an email (#289)" do
    rule(trigger: "job_completed", delay: 0, conditions: {}, actions: [ { "type" => "invoice_job" } ], name: "Invoice it")
    job = Job.create!(client: @maria, title: "Free inspection", line_items_attributes: [ { name: "Inspection", quantity: 1, unit_price: 0 } ])
    now { job.complete!(by: @owner) }
    invoice = job.invoices.sole
    assert_equal "draft", invoice.status
    assert_not EmailMessage.exists?(related: invoice)
    assert_includes AutomationRun.where(subject: job).sole.log.to_s, "Created #{invoice.number} as a draft: it comes to $0.00."
  end

  test "PAY-06: with split jobs, invoice the job skips a job with nothing left to bill, saying so" do
    enable_feature(:split_jobs)
    rule(trigger: "job_completed", delay: 0, conditions: {}, actions: [ { "type" => "invoice_job" } ], name: "Invoice it")
    job = Job.create!(client: @maria, title: "Fence", line_items_attributes: [ { name: "Fence", quantity: 1, unit_price: 400 } ])
    job.update_columns(status: "completed")
    billed = Invoice.from_job!(job.reload)
    job.update_columns(status: "in_progress")
    now { job.reload.complete!(by: @owner) }
    assert_equal [ billed ], job.invoices.to_a
    assert_includes AutomationRun.where(subject: job).sole.log.to_s, "Nothing on the job is left to bill."
  end

  test "PAY-08: invoice the job sends a final bill its progress covers, as any other, and it's Paid at once" do
    enable_feature(:split_jobs)
    rule(trigger: "job_completed", delay: 0, conditions: {}, actions: [ { "type" => "invoice_job" } ], name: "Invoice it")
    job = Job.create!(client: @maria, title: "Fence", line_items_attributes: [ { name: "Fence", quantity: 1, unit_price: 400 } ])
    WorkBilling.bill_progress!(job, by: @owner).mark_sent!(by: @owner, channel: "link")
    now { job.reload.complete!(by: @owner) }
    invoice = job.invoices.where(kind: "work").sole
    assert_equal [ "paid", 0, 1 ], [ invoice.status, invoice.total_cents, invoice.credits.count ]
    assert_includes AutomationRun.where(subject: job).sole.log.to_s, "Created and emailed #{invoice.number}."
  end

  test "overdue invoices trigger once, from the hourly sweep" do
    reminder = MessageTemplate.create!(name: "Overdue", subject: "{{document_number}} is overdue", body: "Hi {{client_first_name}}")
    rule(trigger: "invoice_overdue", delay: 0, conditions: { "still_open" => true }, actions: [ { "type" => "send_template", "template" => reminder.uid } ], name: "Overdue")
    invoice = Invoice.start(client: @maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "120" } ]); _1.update!(tax_rates: []) }
    invoice.mark_sent!(by: @owner, channel: "link")
    invoice.update_columns(issued_on: @business.today - 10, due_on: @business.today - 1)
    old = Invoice.start(client: @maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Old", "quantity" => "1", "unit_price" => "50" } ]); _1.update!(tax_rates: []) }
    old.mark_sent!(by: @owner, channel: "link")
    old.update_columns(issued_on: @business.today - 90, due_on: @business.today - 60)
    AutomationRule.find_by!(name: "Overdue").update_columns(created_at: 2.days.ago)
    Current.reset
    now { 2.times { AutomationsDueJob.perform_now } }
    Current.business = @business
    assert_equal 1, AutomationRun.where(subject: invoice).count
    assert_equal "done", AutomationRun.find_by!(subject: invoice).status
    assert_not AutomationRun.exists?(subject: old), "invoices overdue before the rule existed aren't chased"
  end

  test "an automation whose record was deleted is skipped, and one business's problem doesn't stop the sweep" do
    rule
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    run = AutomationRun.find_by!(subject: q)
    run.update_columns(subject_id: 0)
    later = rule(trigger: "quote_viewed", delay: 0, conditions: {}, name: "Broken")
    broken = AutomationRun.create!(rule: later, rule_name: "Broken", trigger: "quote_viewed", subject: q, run_at: 1.hour.ago)
    broken.update_columns(log: "not a list") # anything unexpected
    Current.reset
    travel(3.days + 10.minutes) { AutomationsDueJob.perform_now }
    Current.business = @business
    assert_equal "skipped", run.reload.status
    assert_equal "The record no longer exists.", run.log.first["detail"]
    assert_equal "failed", broken.reload.status, "an unexpected error marks the run failed instead of retrying it forever"
  end

  test "client emails wait for a confirmed owner, and a rule moved to another trigger doesn't act on runs already waiting" do
    r = rule(delay: 0)
    @owner.update_columns(confirmed_at: nil)
    q = quote
    perform_enqueued_jobs(only: AutomationRunJob) { q.mark_sent!(by: @owner, channel: "link") }
    assert_match "confirms their email", AutomationRun.find_by!(subject: q).log.first["detail"]
    @owner.update_columns(confirmed_at: Time.current)
    r.update!(delay_minutes: 60)
    q2 = quote
    q2.mark_sent!(by: @owner, channel: "link")
    r.update!(trigger: "quote_viewed")
    travel(2.hours) { perform_enqueued_jobs(only: AutomationRunJob) }
    run = AutomationRun.find_by!(subject: q2)
    assert_equal [ "skipped", "The automation now starts on something else." ], [ run.status, run.log.first["detail"] ]
  end

  test "a run for a client whose details were erased (INS-02) is skipped" do
    rule
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    ClientErasure.new(@maria, by: @owner).erase!
    run_due
    run = AutomationRun.find_by!(subject: q)
    assert_equal [ "skipped", "The client's details were erased." ], [ run.status, run.log.first["detail"] ]
  end

  test "runs wait while a business is suspended; on reactivation, ones that came due meanwhile are skipped and later ones go ahead" do
    rule
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    @business.suspend!(reason: "Spam")
    run_due
    assert_equal "scheduled", AutomationRun.find_by!(subject: q).status, "nothing runs while suspended"
    travel(3.days + 10.minutes) { @business.reload.reactivate! }
    run = AutomationRun.find_by!(subject: q)
    assert_equal [ "skipped", Automation::MISSED_WHILE_SUSPENDED ], [ run.status, run.log.last["detail"] ]

    later = quote
    @business.suspend!(reason: "Checking")
    @business.reload.reactivate!
    later.mark_sent!(by: @owner, channel: "link")
    Current.reset
    travel(3.days + 10.minutes) { AutomationsDueJob.perform_now }
    Current.business = @business
    assert_equal "done", AutomationRun.find_by!(subject: later).status, "a short suspension doesn't stop what comes after it"
  end

  test "invoices that fell overdue while the business was suspended aren't chased, even by a rule switched back on later" do
    on = AutomationRule.create!(name: "Overdue", trigger: "invoice_overdue", actions: [ { "type" => "notify_team", "team" => "office" } ])
    off = AutomationRule.create!(name: "Overdue (off)", trigger: "invoice_overdue", enabled: false, actions: [ { "type" => "notify_team", "team" => "office" } ])
    [ on, off ].each { _1.update_columns(created_at: 30.days.ago) }
    invoice = Invoice.start(client: @maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ]); _1.update!(tax_rates: []) }
    invoice.mark_sent!(by: @owner, channel: "link")
    invoice.update_columns(issued_on: @business.today - 5, due_on: @business.today + 2)
    @business.suspend!(reason: "Dispute")
    travel(6.days) do
      @business.reload.reactivate!
      off.update!(enabled: true)
      Current.reset
      AutomationsDueJob.perform_now
      Current.business = @business
    end
    [ on, off ].each do |rule|
      run = AutomationRun.find_by!(rule:, subject: invoice)
      assert_equal [ "skipped", Automation::MISSED_WHILE_SUSPENDED ], [ run.status, run.log.last["detail"] ]
    end
    assert_not Notification.exists?(kind: "automation"), "nobody is notified about an invoice that went overdue during the suspension"
  end

  test "a run that came due before a short suspension isn't called missed" do
    rule
    q = quote
    q.mark_sent!(by: @owner, channel: "link")
    travel(3.days + 10.minutes) do
      @business.suspend!(reason: "Checking")
      @business.reload.reactivate!
      assert_equal "scheduled", AutomationRun.find_by!(subject: q).status, "it was due before the suspension began"
    end
  end

  test "another business's rules never run for this business's records" do
    theirs = Current.set(business: businesses(:two)) do
      template = MessageTemplate.create!(name: "Theirs", subject: "s", body: "b")
      AutomationRule.create!(name: "Theirs", trigger: "quote_sent", actions: [ { "type" => "send_template", "template" => template.uid } ])
    end
    businesses(:two).update!(plan_overrides: @business.plan_overrides)
    now { quote.mark_sent!(by: @owner, channel: "link") }
    assert_equal 0, Tenancy.across_businesses(reason: "test") { AutomationRun.where(rule: theirs).count }
    assert_nil AutomationRule.find_by(id: theirs.id), "rules are scoped to the current business"
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
