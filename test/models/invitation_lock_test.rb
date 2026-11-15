require "test_helper"

class InvitationLockTest < ActiveSupport::TestCase
  test "accept! re-reads the invitation, so a revoke committed after loading wins" do
    business = businesses(:one)
    invitation = as_business(business) { Invitation.create!(email: users(:two).email, role: "technician", invited_by: users(:one)) }
    stale = Invitation.find_by_token(invitation.token)
    as_business(business) { Invitation.find(invitation.id).revoke! }

    assert_raises(Invitation::NotAcceptable) { stale.accept!(users(:two)) }
    assert_not business.business_users.exists?(user: users(:two))
  end
end
