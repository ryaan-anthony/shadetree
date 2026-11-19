require "test_helper"

# ACC-07: the grantable and Owner-only permissions cover the catalog exactly.
class PermissionsCatalogTest < ActiveSupport::TestCase
  test "grantable plus Owner-only is the whole catalog, with no overlap" do
    assert_equal Permissions::CATALOG.keys.sort, (Permissions::GRANTABLE + Permissions::OWNER_ONLY).sort
    assert_empty Permissions::GRANTABLE & Permissions::OWNER_ONLY
  end
end
