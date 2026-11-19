require "test_helper"

# NTF-03: a business's own templates, the send forms' "Start from", and previewing with a real record.
class Admin::CustomMessageTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @business.update!(plan_overrides: { "features" => { "message_templates" => true } })
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Quote.start(client: maria).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
        _1.save!
      end
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def create_template(name: "Spring offer", subject: "{{document_number}}: spring offer", body: "Hi {{client_first_name}}, it's {{total}}.")
    post admin_custom_message_templates_path, params: { message_template: { name:, subject:, body: } }
  end

  test "create, edit and delete a template of your own; it's listed under Messages" do
    get new_admin_custom_message_template_path
    assert_select "input[name='message_template[name]']"
    assert_difference -> { as_business(@business) { MessageTemplate.custom.count } } do
      create_template
    end
    assert_redirected_to admin_message_templates_path
    template = as_business(@business) { MessageTemplate.custom.last }
    get admin_message_templates_path
    assert_select "#custom-template-#{template.uid}", /Spring offer/
    patch admin_custom_message_template_path(template), params: { message_template: { name: "Fall offer", subject: "Fall", body: "Hi" } }
    assert_equal "Fall offer", template.reload.name
    delete admin_custom_message_template_path(template)
    assert_not MessageTemplate.unscoped.exists?(template.id)
  end

  test "names are unique, placeholders are the document ones, and markup is refused" do
    create_template
    create_template(name: "spring OFFER")
    assert_response :unprocessable_content
    create_template(name: "Other", body: "{{visit_window}}")
    assert_select "[role=alert]", /\{\{visit_window\}\} isn't a placeholder/
    create_template(name: "Other", body: "<a href='x'>click</a>")
    assert_select "[role=alert]", /plain text/
  end

  test "the send form offers your usual wording and your templates, filled in for this quote" do
    create_template
    get new_admin_quote_send_path(@quote)
    assert_select "select#start_from option", 2
    assert_select "option[data-subject=?]", "#{@quote.number}: spring offer", text: "Spring offer"
    assert_select "option[data-message=?]", "Hi Maria, it's $200.00.", text: "Spring offer"
    assert_select "option", text: "Your usual wording"
  end

  test "the picker stays after a send error, still offering the usual wording" do
    create_template
    post admin_quote_send_path(@quote), params: { channel: "email", quote_send: { to: "not-an-email", subject: "Mine", message: "Typed" } }
    assert_response :unprocessable_content
    assert_select "option[data-subject=?]", QuoteMailer.default_subject(@quote), text: "Your usual wording"
    assert_select "input[name='quote_send[subject]'][value=?]", "Mine"
  end

  test "the invoice send form offers your templates too" do
    create_template
    invoice = as_business(@business) do
      Invoice.start(client: @quote.client).tap { _1.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "120" } ]); _1.update!(tax_rates: []) }
    end
    get new_admin_invoice_send_path(invoice)
    assert_select "option[data-subject=?]", "#{invoice.number}: spring offer"
  end

  test "the preview of your own template shows sample or real values, without save-time errors" do
    create_template
    post preview_admin_custom_message_templates_path, params: { message_template: { name: "Spring offer", subject: "{{document_number}}", body: "Hi {{client_first_name}}" } }
    assert_response :success
    assert_select "p", text: "Hi Maria"
    assert_select "[role=alert]", false, "its own name isn't 'already taken' in a preview"
    post preview_admin_custom_message_templates_path, params: { message_template: { name: "x", subject: "{{document_number}}", body: "Hi" }, preview_record: "Quote:#{@quote.uid}" }
    assert_select "p", text: @quote.number
  end

  test "up to 50 templates of your own" do
    as_business(@business) { 50.times { |i| MessageTemplate.create!(name: "T#{i}", subject: "S", body: "B") } }
    create_template
    assert_response :unprocessable_content
    assert_select "[role=alert]", /up to 50/
  end

  test "without templates of your own there's no picker" do
    get new_admin_quote_send_path(@quote)
    assert_select "select#start_from", false
  end

  test "the editor previews with a real recent record of this business only" do
    get edit_admin_message_template_path("quote_sent")
    assert_select "select#preview_record option[value=?]", "Quote:#{@quote.uid}"
    post preview_admin_message_template_path("quote_sent"),
         params: { message_template: { subject: "{{quote_number}}", body: "Hi {{client_first_name}}" }, preview_record: "Quote:#{@quote.uid}" }
    assert_select "p", text: @quote.number
    assert_select "p", text: "Hi Maria"

    theirs = as_business(businesses(:two)) { Quote.start(client: Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])).tap(&:save!) }
    post preview_admin_message_template_path("quote_sent"), params: { message_template: { subject: "{{quote_number}}", body: "Hi {{client_first_name}}" }, preview_record: "Quote:#{theirs.uid}" }
    assert_select "p", text: "Hi Maria", count: 1, message: "another business's record falls back to the samples"
    post preview_admin_message_template_path("quote_sent"), params: { message_template: { subject: "x", body: "y" }, preview_record: "User:#{@owner.id}" }
    assert_response :success
  end

  test "without the plan feature, your own templates can't be added or changed" do
    @business.update!(plan_overrides: {})
    get new_admin_custom_message_template_path
    assert_redirected_to admin_message_templates_path
    create_template
    assert_equal 0, as_business(@business) { MessageTemplate.custom.count }
  end
end
