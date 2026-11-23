require "test_helper"

class ComponentsHelperTest < ActionView::TestCase
  test "button_classes composes variant and sizes" do
    assert_equal "btn btn-primary", button_classes
    assert_equal "btn btn-destructive-solid btn-sm btn-icon", button_classes(:destructive_solid, :sm, :icon)
    assert_equal "btn btn-secondary w-full", button_classes(:secondary, extra: "w-full")
  end

  test "button_classes rejects unknown variants and sizes" do
    assert_raises(ArgumentError) { button_classes(:fancy) }
    assert_raises(ArgumentError) { button_classes(:ghost) } # PLT-14: now :tertiary
    assert_raises(ArgumentError) { button_classes(:link) }  # the inline text link isn't a button (.text-action)
    assert_raises(ArgumentError) { button_classes(:primary, :xl) }
  end

  # PLT-14: the six variants are the four ranks, the destructive dialog's confirm and the client
  # pages' brand button.
  test "the kit has six button variants" do
    assert_equal %i[primary secondary tertiary destructive destructive_solid brand], BUTTON_VARIANTS
  end

  # PLT-14: views, layouts and scripts ask the kit for button classes (button_classes,
  # f.submit_button) instead of writing them, so a rank can't drift. The kit itself is exempt.
  test "no view, layout, helper or script writes kit button classes by hand" do
    kit = %w[app/helpers/components_helper.rb app/assets/tailwind/components.css].map { Rails.root.join(_1).to_s }
    files = Dir[Rails.root.join("app/{views,helpers,form_builders,components,javascript}/**/*.{erb,rb,js}")] - kit
    offenders = files.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{Pathname(file).relative_path_from(Rails.root)}:#{index + 1}: #{line.strip}" if line.match?(/(?<![\w-])btn(?:-[a-z]+)*(?![\w-])/)
      end
    end
    assert_empty offenders, "Use button_classes (or f.submit_button variant:/size:) instead:\n#{offenders.join("\n")}"
  end

  test "badge renders a tone and optional dot" do
    assert_dom_equal '<span class="badge badge-success">Paid</span>', badge("Paid", tone: :success)
    assert_dom_equal '<span class="badge badge-plain">Draft</span>', badge("Draft", dot: false)
    assert_raises(ArgumentError) { badge("x", tone: :pink) }
  end

  test "empty state shows title, text and actions" do
    render inline: <<~ERB
      <%= empty_state title: "No clients yet", text: "Add one.", icon: "users" do %><a href="/new">Add client</a><% end %>
    ERB
    assert_select ".empty .empty-title", "No clients yet"
    assert_select ".empty .empty-text", "Add one."
    assert_select ".empty a[href='/new']"
    assert_select ".empty .empty-icon svg"
  end

  test "card renders a header only when given a title or actions" do
    render inline: '<%= card(title: "Client") { "Body" } %><%= card { "Plain" } %>'
    assert_select ".card", 2
    assert_select ".card-head", 1
    assert_select ".card-title", "Client"
  end

  test "pagination summarises the range and disables the ends" do
    controller.request = ActionDispatch::TestRequest.create("PATH_INFO" => "/styleguide", "QUERY_STRING" => "q=oak")
    controller.request.path_parameters = { controller: "styleguide", action: "show" }
    render inline: "<%= pagination(page: 1, per_page: 20, total_count: 45) %>"
    assert_select ".pagination p", /1–20.*of.*45/m
    assert_select "span[aria-disabled='true']", text: /Previous/
    assert_select "a[rel='next'][href*='page=2'][href*='q=oak']"
  end

  test "flash tones map notice and alert" do
    assert_equal :success, flash_tone(:notice)
    assert_equal :danger, flash_tone("alert")
    assert_equal :info, flash_tone(:other)
  end

  test "avatar shows up to two initials" do
    assert_dom_equal '<span class="avatar" title="Maria del Lopez">MD</span>', avatar("Maria del Lopez")
  end
end
