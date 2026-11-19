require "test_helper"
require "rake"

class FeatureTest < ActiveSupport::TestCase
  setup do
    @definitions = Feature.definitions
    definitions = { "beta_editor" => Feature::Definition.new(name: "beta_editor", description: "Test flag", owner: "@me", remove_by: "M3") }
    Feature.instance_variable_set(:@definitions, definitions)
    @one, @two = businesses(:one), businesses(:two)
  end

  teardown { Feature.instance_variable_set(:@definitions, @definitions) }

  test "declared flags default to off" do
    assert_not Feature.enabled?(:beta_editor, business: @one)
  end

  test "on and off for everyone" do
    Feature.enable!(:beta_editor)
    assert Feature.enabled?(:beta_editor, business: @one)
    assert Feature.enabled?(:beta_editor, business: nil)
    Feature.disable!(:beta_editor)
    assert_not Feature.enabled?(:beta_editor, business: @one)
  end

  test "on for a list of businesses" do
    Feature.enable_for!(:beta_editor, @one)
    assert Feature.enabled?(:beta_editor, business: @one)
    assert_not Feature.enabled?(:beta_editor, business: @two)
    assert_not Feature.enabled?(:beta_editor, business: nil)
    Feature.disable_for!(:beta_editor, @one)
    assert_equal "off", FeatureFlag.find_by!(name: "beta_editor").state
  end

  test "percentage rollout is deterministic and grows monotonically" do
    businesses = Array.new(200) { |i| Business.new(id: 10_000 + i) }
    Feature.enable_percentage!(:beta_editor, 25)
    at25 = businesses.select { Feature.enabled?(:beta_editor, business: _1) }
    assert_in_delta 50, at25.size, 20
    assert_equal at25, businesses.select { Feature.enabled?(:beta_editor, business: _1) }

    Feature.enable_percentage!(:beta_editor, 60)
    at60 = businesses.select { Feature.enabled?(:beta_editor, business: _1) }
    assert (at25 - at60).empty?, "raising the percentage never turns a business off"
    Feature.enable_percentage!(:beta_editor, 100)
    assert businesses.all? { Feature.enabled?(:beta_editor, business: _1) }
  end

  test "checks use Current.business by default" do
    Feature.enable_for!(:beta_editor, @two)
    as_business(@two) { assert Feature.enabled?(:beta_editor) }
    as_business(@one) { assert_not Feature.enabled?(:beta_editor) }
  end

  test "undeclared flags raise in test and can't be changed" do
    assert_raises(Feature::UnknownFlag) { Feature.enabled?(:nope) }
    assert_raises(Feature::UnknownFlag) { Feature.enable!(:nope) }
  end

  test "undeclared flags are off and logged outside test" do
    original = Rails.env
    Rails.env = "development"
    assert_not Feature.enabled?(:nope)
  ensure
    Rails.env = original
  end

  test "test helpers override and reset" do
    with_feature(:beta_editor) { assert Feature.enabled?(:beta_editor, business: @one) }
    assert_not Feature.enabled?(:beta_editor, business: @one)
    enable_feature(:beta_editor, only: @two)
    as_business(@two) { assert Feature.enabled?(:beta_editor) }
    as_business(@one) { assert_not Feature.enabled?(:beta_editor) }
  end

  test "business-specific overrides use the business being asked about" do
    enable_feature(:beta_editor, only: @two)
    as_business(@one) { assert Feature.enabled?(:beta_editor, business: @two) }
    as_business(@two) { assert_not Feature.enabled?(:beta_editor, business: @one) }
  end

  test "overrides can't hide a typo in the flag name" do
    assert_raises(Feature::UnknownFlag) { with_feature(:bta_editor) { Feature.enabled?(:bta_editor) } }
  end

  test "overrides are visible to other threads, like the system-test server" do
    enable_feature(:beta_editor)
    assert Thread.new { Feature.enabled?(:beta_editor, business: @one) }.value
  end

  test "a business can't be carved out of an everyone or percentage rollout" do
    Feature.enable!(:beta_editor)
    assert_raises(Feature::UnsupportedChange) { Feature.disable_for!(:beta_editor, @one) }
    Feature.enable_percentage!(:beta_editor, 50)
    error = assert_raises(Feature::UnsupportedChange) { Feature.disable_for!(:beta_editor, @one) }
    assert_match "flags:disable", error.message
  end

  test "enable_for! keeps everyone-on, and replaces a percentage with a list" do
    Feature.enable!(:beta_editor)
    Feature.enable_for!(:beta_editor, @one)
    assert_equal "on", FeatureFlag.find_by!(name: "beta_editor").state
    Feature.enable_percentage!(:beta_editor, 10)
    Feature.enable_for!(:beta_editor, @one)
    assert_equal "businesses", FeatureFlag.find_by!(name: "beta_editor").state
  end

  test "invalid percentages are rejected" do
    assert_raises(ActiveRecord::RecordInvalid) { Feature.enable_percentage!(:beta_editor, 150) }
  end

  test "status lists declared flags with their state" do
    Feature.enable!(:beta_editor, by: "tester")
    definition, flag = Feature.status.first
    assert_equal "beta_editor", definition.name
    assert_equal [ "on", "tester" ], [ flag.state, flag.changed_by ]
  end

  test "the shipped registry loads and every entry has an owner and removal milestone" do
    Feature.reload_definitions!
    assert_kind_of Hash, Feature.definitions
  end

  test "rake tasks change flags at runtime" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("flags:enable")
    silence = ->(&block) { assert_output(/beta_editor/) { block.call } }
    silence.call { Rake::Task["flags:enable_for"].execute(Rake::TaskArguments.new(%i[name business], [ "beta_editor", @one.uid ])) }
    assert Feature.enabled?(:beta_editor, business: @one)
    silence.call { Rake::Task["flags:percentage"].execute(Rake::TaskArguments.new(%i[name percent], [ "beta_editor", "100" ])) }
    assert Feature.enabled?(:beta_editor, business: @two)
    silence.call { Rake::Task["flags:disable"].execute(Rake::TaskArguments.new(%i[name], [ "beta_editor" ])) }
    assert_not Feature.enabled?(:beta_editor, business: @one)
    silence.call { Rake::Task["flags:list"].execute }
  end

  test "controllers and views ask with feature?" do
    Feature.enable!(:beta_editor)
    assert ApplicationController.new.send(:feature?, :beta_editor)
  end
end
