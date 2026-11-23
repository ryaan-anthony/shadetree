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

  # PLT-22: a caller's own description (Branding's "where the color shows") isn't dropped.
  test "field keeps the caller's aria-describedby beside its help and error" do
    record = Record.new(name: "").tap(&:validate)
    render inline: <<~ERB, locals: { record: }
      <%= form_with model: record, url: "/x" do |f| %><%= f.field :name, help: "As on invoices.", "aria-describedby": "note warnings" %><%= f.field :notes, as: :textarea, optional: true, "aria-describedby": "note" %><% end %>
    ERB
    assert_select "input#sample_name[aria-describedby='sample_name_help sample_name_error note warnings']"
    assert_select "textarea#sample_notes[aria-describedby=note]"
  end

  test "file_drop: a real file field in a drop area, with the caller's ARIA and actions kept" do
    record = Record.new.tap { _1.errors.add(:name, LogoUpload::TYPE_ERROR) }
    render inline: <<~ERB, locals: { record: }
      <%= form_with model: record, url: "/x" do |f| %>
        <%= f.file_drop :name, label: "Upload a logo", prompt: "Drop your logo here", types: %w[image/png], types_label: "PNG",
                        max_bytes: 5.5.megabytes, help: "Wide works best.", "aria-describedby": "note", "aria-labelledby": "section",
                        data: { action: "change->other#go" } %>
      <% end %>
    ERB
    assert_select ".file-drop[data-file-drop-type-error-value='Name must be a PNG file'][data-file-drop-size-error-value='Name must be smaller than 5.5 MB']"
    assert_select "#sample_name_limits", "PNG, up to 5.5 MB."
    assert_select "input#sample_name[type=file][accept='image/png'][aria-invalid=true][aria-labelledby='sample_name_label section']" \
                  "[aria-describedby='sample_name_limits sample_name_help sample_name_error sample_name_check note']" \
                  "[data-action='change->other#go change->file-drop#chosen'][data-file-drop-target=input]"
    assert_select "p.error-text#sample_name_error[data-file-drop-target=serverError] svg"
    assert_select "p.error-text#sample_name_check[hidden] svg" # filled in before saving; read out by the announce line
    assert_select ".file-drop .text-action", "browse"
    assert_select ".file-drop-chosen button.btn-tertiary.btn-sm", "Clear"
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
      <%= form_with model: record, url: "/x" do |f| %><%= f.check :reminders, label: "Remind", hint: "Day before" %><%= f.submit_button "Save" %><%= f.submit_button "Go", variant: :secondary, size: :lg, class: "w-full" %><% end %>
    ERB
    assert_select "label.check input[type='checkbox'][checked]"
    assert_select "label.check .check-hint", "Day before"
    assert_select "input[type='submit'].btn.btn-primary[value='Save']"
    assert_select "input[type='submit'][class='btn btn-secondary btn-lg w-full'][value='Go']"
  end

  test "unknown field types raise" do
    assert_raises(ActionView::Template::Error) do
      render inline: '<%= form_with model: Record.new, url: "/x" do |f| %><%= f.field :name, as: :colour %><% end %>'
    end
  end
end
