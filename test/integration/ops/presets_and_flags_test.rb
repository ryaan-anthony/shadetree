require "test_helper"

# OPS-04: editing industry presets and release flags from the console, each audited.
class Ops::PresetsAndFlagsTest < ActionDispatch::IntegrationTest
  setup do
    @definitions = Feature.definitions
    Feature.instance_variable_set(:@definitions, { "beta_editor" => Feature::Definition.new(name: "beta_editor", description: "Test flag", owner: "@me", remove_by: "M3") })
  end

  teardown { Feature.instance_variable_set(:@definitions, @definitions) }

  test "operators edit a preset's visit length and starter services" do
    preset = IndustryPreset.for("cleaning") || IndustryPreset.create!(industry: "cleaning", items: [ { "name" => "Deep clean", "unit" => "visit" } ])
    sign_in_operator
    get ops_presets_path
    assert_select "#preset-cleaning"
    get edit_ops_preset_path(preset)
    assert_select "#preset-items tbody tr", preset.items.size + Ops::PresetsController::BLANK_ROWS
    rows = { "0" => { name: "Deep clean", unit: "visit", duration_minutes: "180", taxable: "1", category: "Cleaning" },
             "1" => { name: "Window wash", unit: "custom", custom_unit: "pane", taxable: "0" },
             "2" => { name: "" } }
    patch ops_preset_path(preset), params: { default_visit_minutes: "120", items: rows }
    assert_redirected_to ops_presets_path
    preset.reload
    assert_equal 120, preset.default_visit_minutes
    assert_equal [ { "name" => "Deep clean", "unit" => "visit", "taxable" => true, "duration_minutes" => 180, "category" => "Cleaning" },
                   { "name" => "Window wash", "unit" => "custom", "custom_unit" => "pane", "taxable" => false } ], preset.items
    assert_equal({ "industry" => "cleaning", "items" => 2 }, AuditEntry.find_by!(action: "preset.updated").data)

    patch ops_preset_path(preset), params: { default_visit_minutes: "120", items: { "0" => { name: "Odd", unit: "custom" } } }
    assert_response :unprocessable_content
    assert_select ".banner", /custom_unit is needed/
  end

  test "operators turn a flag on, to a percentage, to some businesses and off" do
    sign_in_operator
    get ops_feature_flags_path
    assert_select "#flag-beta_editor", /Off/
    patch ops_feature_flag_path("beta_editor"), params: { state: "percentage", percentage: "25" }
    flag = FeatureFlag.find_by!(name: "beta_editor")
    assert_equal [ "percentage", 25, "user1@example.com" ], [ flag.state, flag.percentage, flag.changed_by ]
    patch ops_feature_flag_path("beta_editor"), params: { state: "businesses", businesses: "#{businesses(:one).uid}, #{businesses(:two).uid}" }
    assert_equal [ "businesses", [ businesses(:one).id, businesses(:two).id ].sort ], [ flag.reload.state, flag.business_ids.sort ]
    patch ops_feature_flag_path("beta_editor"), params: { state: "businesses", businesses: "nope" }
    assert_match "Unknown business IDs: nope", flash[:alert]
    patch ops_feature_flag_path("beta_editor"), params: { state: "on" }
    assert_equal "on", flag.reload.state
    patch ops_feature_flag_path("beta_editor"), params: { state: "off" }
    assert_equal "off", flag.reload.state
    patch ops_feature_flag_path("undeclared"), params: { state: "on" }
    assert_match "no flag called", flash[:alert]
    assert_equal %w[percentage businesses on off], AuditEntry.where(action: "feature_flag.changed").order(:id).map { _1.data["state"] }
  end
end
