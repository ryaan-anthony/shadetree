require "test_helper"

class ComponentsHelperTest < ActionView::TestCase
  test "button_classes composes variant and sizes" do
    assert_equal "btn btn-primary", button_classes
    assert_equal "btn btn-danger-solid btn-sm btn-icon", button_classes(:danger_solid, :sm, :icon)
    assert_equal "btn btn-secondary w-full", button_classes(:secondary, extra: "w-full")
  end

  test "button_classes rejects unknown variants and sizes" do
    assert_raises(ArgumentError) { button_classes(:fancy) }
    assert_raises(ArgumentError) { button_classes(:primary, :xl) }
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
