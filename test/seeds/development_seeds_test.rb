require "test_helper"

# bin/setup runs the development seeds on every setup, so they must be idempotent.
class DevelopmentSeedsTest < ActiveSupport::TestCase
  SEEDS = Rails.root.join("db/seeds/development.rb")

  test "loading the demo data twice creates it once" do
    silence_stream($stdout) { load SEEDS }
    counts = [ User.count, Business.count, BusinessUser.count ]

    silence_stream($stdout) { load SEEDS }

    assert_equal counts, [ User.count, Business.count, BusinessUser.count ]
  end

  test "demo users can sign in and belong to the demo business" do
    silence_stream($stdout) { load SEEDS }
    business = Business.find_by!(name: "Oakline Lawn & Landscape")

    %w[owner@example.com admin@example.com tech@example.com].each do |email|
      user = User.find_by!(email: email)
      assert user.confirmed?, "#{email} should be confirmed"
      assert user.valid_password?("shadetree-demo-1")
      assert BusinessUser.exists?(user: user, business: business), "#{email} should be a member"
    end
  end

  private
    def silence_stream(stream)
      original = stream.dup
      stream.reopen(File::NULL)
      yield
    ensure
      stream.reopen(original)
    end
end
