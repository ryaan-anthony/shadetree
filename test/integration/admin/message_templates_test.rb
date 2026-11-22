require "test_helper"

# NTF-03: Settings → Messages: edit a client email's subject and opening text with placeholders
# and a preview, go back to the default, and have the emails use it. Editing is a plan feature.
class Admin::MessageTemplatesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @business.update!(plan_overrides: { "features" => { "message_templates" => true } })
    @maria = as_business(@business) do
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def save(kind, subject:, body:) = patch(admin_message_template_path(kind), params: { message_template: { subject:, body: } })

  test "Owners and Admins manage messages; technicians can't" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_message_templates_path }
  end

  test "the list shows every client email, with the customized ones marked" do
    get admin_message_templates_path
    assert_response :success
    MessageTemplate::DEFINITIONS.each_key { assert_select "#message-#{_1} a[href=?]", edit_admin_message_template_path(_1) }
    assert_select ".badge", text: "Customized", count: 0
    save("visit_reminder", subject: "See you tomorrow, {{client_first_name}}", body: "Hi {{client_first_name}}, we're coming tomorrow.")
    get admin_message_templates_path
    assert_select "#message-visit_reminder .badge", "Customized"
  end

  test "editing starts from the default, previews with sample details, and refuses unknown placeholders and markup" do
    get edit_admin_message_template_path("quote_sent")
    assert_select "input[name='message_template[subject]'][value=?]", MessageTemplate.definition("quote_sent").subject
    assert_select "button[data-placeholder=client_first_name]"
    assert_select "[data-template-editor-target=preview]", /Hi Maria,/

    post preview_admin_message_template_path("quote_sent"), params: { message_template: { subject: "Your quote {{quote_number}}", body: "Hey {{client_first_name}} {{oops}}" } }
    assert_response :success
    assert_select "p", text: "Your quote Q-1041"
    assert_select "[role=alert]", /\{\{oops\}\} isn't a placeholder/

    assert_no_difference -> { as_business(@business) { MessageTemplate.count } } do
      save("quote_sent", subject: "Quote", body: "Hi <img src=x onerror=alert(1)>")
    end
    assert_response :unprocessable_content
    assert_select "[role=alert]", /plain text/
  end

  test "saved wording fills the send form; going back to the default restores it" do
    quote = as_business(@business) do
      Quote.start(client: @maria).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
        _1.save!
      end
    end
    save("quote_sent", subject: "Your quote {{quote_number}} is ready", body: "Hello {{client_first_name}}, it's {{total}}.\n\n{{your_name}}")
    assert_redirected_to admin_message_templates_path
    get new_admin_quote_send_path(quote)
    assert_select "input[name='quote_send[subject]'][value=?]", "Your quote #{quote.number} is ready"
    assert_select "textarea[name='quote_send[message]']", text: /Hello Maria, it's \$200\.00\.\s+#{@owner.first_name}/

    delete admin_message_template_path("quote_sent")
    assert_redirected_to admin_message_templates_path
    get new_admin_quote_send_path(quote)
    assert_select "input[name='quote_send[subject]'][value=?]", QuoteMailer.default_subject(quote)
  end

  test "client emails use the saved wording, escaped, and keep the fixed parts; others are unchanged" do
    save("request_received", subject: "Got it, {{client_first_name}}!", body: "Thanks {{client_first_name}}.\n\nWe'll call you <soon>.")
    assert_response :unprocessable_content, "markup is refused"
    save("request_received", subject: "Got it, {{client_first_name}}!", body: "Thanks {{client_first_name}}.\n\nWe'll call you & text you.")
    request = as_business(@business) { ServiceRequest.create!(client: @maria, source: "form", description: "Leaves", contact_name: "Maria Lopez") }
    mail = RequestMailer.with(business_id: @business.id, to: "maria@example.com", request_id: request.id).received
    assert_equal "Got it, Maria!", mail.subject
    assert_includes mail.html_part.body.to_s, "We&#39;ll call you &amp; text you."
    assert_includes mail.text_part.body.to_s, "Thanks Maria."
    assert_includes mail.text_part.body.to_s, "Didn't send a request? You can ignore this email.", "the fixed parts stay"

    visit = as_business(@business) do
      job = Job.create!(client: @maria, title: "Mowing")
      job.visits.new(scheduled_on: @business.today + 1, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) }
    end
    mail = VisitMailer.with(business_id: @business.id, to: "maria@example.com", job_id: visit.job_id, visit_id: visit.id).reminder
    assert_match(/\AReminder: your visit tomorrow/, mail.subject, "not customized: the default")
    assert_includes mail.text_part.body.to_s, "is coming tomorrow"
  end

  test "visit emails use the wording for their kind; mixed changes keep the standard wording" do
    save("visit_reminder", subject: "Tomorrow: {{visit_window}}", body: "Hi {{client_first_name}}, see you tomorrow.")
    save("visit_changed", subject: "New time for {{client_first_name}}", body: "We moved things around.")
    save("visit_cancelled", subject: "Cancelled", body: "Cancelled.")
    visits = as_business(@business) do
      job = Job.create!(client: @maria, title: "Mowing")
      2.times.map { |i| job.visits.new(scheduled_on: @business.today + 1 + i, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) } }
    end
    reminder = VisitMailer.with(business_id: @business.id, to: "maria@example.com", job_id: visits.first.job_id, visit_id: visits.first.id).reminder
    assert_equal "Tomorrow: #{as_business(@business) { visits.first.when_label }}", reminder.subject
    assert_includes reminder.text_part.body.to_s, "Hi Maria, see you tomorrow."
    changes = [ { "visit_id" => visits.first.id, "kind" => "changed", "before" => "Mon" }, { "visit_id" => visits.last.id, "kind" => "cancelled" } ]
    update = VisitMailer.with(business_id: @business.id, to: "maria@example.com", job_id: visits.first.job_id, changes:).update
    assert_equal "Changes to your visits", update.subject, "mixed changes keep the standard wording"
    assert_includes update.text_part.body.to_s, "Your visits have changed"
    changes = [ { "visit_id" => visits.first.id, "kind" => "changed", "before" => "Mon" } ]
    update = VisitMailer.with(business_id: @business.id, to: "maria@example.com", job_id: visits.first.job_id, changes:).update
    assert_equal "New time for Maria", update.subject
    assert_includes update.html_part.body.to_s, "We moved things around."
  end

  # The defaults are the product's own words: saving one unchanged sends the same email.
  def with_default_saved(kind)
    without = yield
    definition = MessageTemplate.definition(kind)
    as_business(@business) { MessageTemplate.create!(kind:, subject: definition.subject, body: definition.body) }
    with = yield
    as_business(@business) { MessageTemplate.for_kind(kind).destroy! }
    [ without, with ]
  end

  def normalized(mail) = [ mail.subject, mail.text_part.body.to_s.gsub(/\s+/, " ").strip ]

  test "a template saved with the default wording sends what the product sends without one" do
    request = as_business(@business) { ServiceRequest.create!(client: @maria, source: "form", description: "Leaves", contact_name: "Maria Lopez") }
    without, with = with_default_saved("request_received") { normalized(RequestMailer.with(business_id: @business.id, to: "maria@example.com", request_id: request.id).received) }
    assert_equal without, with

    quote = as_business(@business) do
      Quote.start(client: @maria).tap do
        _1.update!(title: "Spring cleanup")
        _1.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
        _1.save!
      end
    end
    without, with = with_default_saved("quote_sent") do
      get new_admin_quote_send_path(quote)
      [ css_select("input[name='quote_send[subject]']").first["value"], css_select("textarea[name='quote_send[message]']").first.text.strip ]
    end
    assert_equal without, with
    assert_includes with.first, ": Spring cleanup", "the title stays in the subject"

    as_business(@business) do
      quote.mark_sent!(by: @owner, channel: "link")
      quote.reload.record_response!(:approve, by: @owner, signer_name: "Maria Lopez", message: "On the phone")
    end
    without, with = with_default_saved("quote_approved") { normalized(QuoteMailer.with(business_id: @business.id, to: "maria@example.com", quote_id: quote.id).approved) }
    assert_equal without, with

    visit = as_business(@business) do
      job = Job.create!(client: @maria, title: "Mowing")
      job.visits.new(scheduled_on: @business.today + 1, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) }
    end
    without, with = with_default_saved("visit_reminder") { normalized(VisitMailer.with(business_id: @business.id, to: "maria@example.com", job_id: visit.job_id, visit_id: visit.id).reminder) }
    assert_equal without, with
    %w[scheduled changed cancelled].each do |change|
      changes = [ { "visit_id" => visit.id, "kind" => change, "before" => ("Mon" if change == "changed") } ]
      without, with = with_default_saved("visit_#{change}") { normalized(VisitMailer.with(business_id: @business.id, to: "maria@example.com", job_id: visit.job_id, changes:).update) }
      assert_equal without, with, change
    end
  end

  test "several visits in one email keep the standard wording, which counts them" do
    save("visit_scheduled", subject: "Booked: {{visit_window}}", body: "Your visit is booked.")
    visits = as_business(@business) do
      job = Job.create!(client: @maria, title: "Mowing")
      2.times.map { |i| job.visits.new(scheduled_on: @business.today + 1 + i, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) } }
    end
    changes = visits.map { { "visit_id" => _1.id, "kind" => "scheduled" } }
    mail = VisitMailer.with(business_id: @business.id, to: "maria@example.com", job_id: visits.first.job_id, changes:).update
    assert_match(/\A2 visits booked/, mail.subject)
    assert_includes mail.text_part.body.to_s, "Your visits are booked."
  end

  test "on a plan without the feature, messages are read-only and customized ones keep sending" do
    save("request_received", subject: "Got it, {{client_first_name}}!", body: "Thanks!")
    @business.update!(plan_overrides: {})
    get admin_message_templates_path
    assert_select ".banner", /View only on Free\..*part of a paid plan/m
    get edit_admin_message_template_path("request_received")
    assert_select "fieldset[disabled]"
    assert_select "input[type=submit][value=Save]", false
    save("request_received", subject: "Changed", body: "Changed")
    assert_redirected_to admin_message_templates_path
    assert_equal "Got it, {{client_first_name}}!", as_business(@business) { MessageTemplate.for_kind("request_received").subject }
    delete admin_message_template_path("request_received")
    assert as_business(@business) { MessageTemplate.for_kind("request_received") }, "can't reset either"

    request = as_business(@business) { ServiceRequest.create!(client: @maria, source: "form", description: "Leaves", contact_name: "Maria Lopez") }
    assert_equal "Got it, Maria!", RequestMailer.with(business_id: @business.id, to: "maria@example.com", request_id: request.id).received.subject
  end

  test "unknown messages aren't found, and another business's wording is never used" do
    get edit_admin_message_template_path("team_invitation")
    assert_response :not_found
    as_business(businesses(:two)) { MessageTemplate.create!(kind: "request_received", subject: "Theirs", body: "Theirs") }
    request = as_business(@business) { ServiceRequest.create!(client: @maria, source: "form", description: "Leaves") }
    assert_equal "#{@business.name} received your request", RequestMailer.with(business_id: @business.id, to: "maria@example.com", request_id: request.id).received.subject
  end
end
