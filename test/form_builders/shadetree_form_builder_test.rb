require "test_helper"

class ShadetreeFormBuilderTest < ActionView::TestCase
  Record = StyleguideController::SampleRecord

  test "is the default form builder" do
    assert_equal ShadetreeFormBuilder, ActionView::Base.default_form_builder
  end

  test "field renders label, input and help wired for screen readers" do
    render inline: <<~ERB, locals: { record: Record.new(email: "a@b.co") }
      <%= form_with model: record, url: "/x" do |f| %><%= f.field :email, as: :email, help: "We send quotes here." %><% end %>
    ERB
    assert_select "label.label[for='sample_email']", "Email"
    assert_select "input.input[type='email'][id='sample_email'][aria-describedby='sample_email_help']"
    assert_select "p.help#sample_email_help", "We send quotes here."
  end

  test "presence validators mark the input required; optional labels say so" do
    render inline: <<~ERB, locals: { record: Record.new }
      <%= form_with model: record, url: "/x" do |f| %><%= f.field :name %><%= f.field :notes, as: :textarea, optional: true %><% end %>
    ERB
    assert_select "input#sample_name[required]"
    assert_select "textarea.textarea#sample_notes:not([required])"
    assert_select "label[for='sample_notes'] .label-optional", "(optional)"
  end

  test "errors set aria-invalid and render one message linked to the input" do
    record = Record.new(name: "", email: "nope").tap(&:validate)
    render inline: <<~ERB, locals: { record: }
      <%= form_with model: record, url: "/x" do |f| %><%= f.field :name %><% end %>
    ERB
    assert_select "input#sample_name[aria-invalid='true'][aria-describedby='sample_name_error']"
    assert_select "p.error-text#sample_name_error", /Name can.t be blank/
  end

  test "select, date, time and money inputs" do
    render inline: <<~ERB, locals: { record: Record.new(price: "12.50") }
      <%= form_with model: record, url: "/x" do |f| %>
        <%= f.field :timezone, as: :select, choices: [["Eastern", "America/New_York"]], include_blank: "Choose" %>
        <%= f.field :visit_on, as: :date %>
        <%= f.field :starts_at, as: :time %>
        <%= f.field :price, as: :money, currency: "€" %>
      <% end %>
    ERB
    assert_select "select.select#sample_timezone option", 2
    assert_select "input.input[type='date']#sample_visit_on"
    assert_select "input.input[type='time']#sample_starts_at"
    assert_select ".input-group .input-addon", "€"
    assert_select ".input-group input[inputmode='decimal'][value='12.50']"
  end

  test "check and submit_button" do
    render inline: <<~ERB, locals: { record: Record.new(reminders: true) }
      <%= form_with model: record, url: "/x" do |f| %><%= f.check :reminders, label: "Remind", hint: "Day before" %><%= f.submit_button "Save" %><% end %>
    ERB
    assert_select "label.check input[type='checkbox'][checked]"
    assert_select "label.check .check-hint", "Day before"
    assert_select "input[type='submit'].btn.btn-primary[value='Save']"
  end

  test "unknown field types raise" do
    assert_raises(ActionView::Template::Error) do
      render inline: '<%= form_with model: Record.new, url: "/x" do |f| %><%= f.field :name, as: :colour %><% end %>'
    end
  end
end
