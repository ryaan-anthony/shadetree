require "test_helper"

# OPS-05: email to support threads into tickets: answers to a ticket reopen it, other email from
# a member opens one, anyone else's is ignored.
class SupportMailTest < ActiveSupport::TestCase
  include PermissionHelpers
  setup do
    @business = businesses(:one)
    @ticket = as_business(@business) { SupportTicket.open!(opened_by: users(:one), subject: "Logo", category: "bug", body: "Blurry") }
    as_business(@business) { @ticket.change_status!("resolved") }
  end

  def email(from: "user1@example.com", subject: "Re: Logo", body: "Still blurry.\n\nOn Tue, Shadetree Support wrote:\n> Try a PNG", **headers)
    Mail.new do
      from from
      to "support@getshadetree.com"
      subject subject
      body body
      headers.each { |name, value| self[name.to_s.tr("_", "-")] = value }
    end
  end

  test "an answer to our email adds to the thread and reopens the ticket, by Message-ID or subject" do
    result = SupportMail.receive(email(in_reply_to: "<ticket-#{@ticket.uid}-1-abcd@getshadetree.com>"))
    assert_equal [ :replied, @ticket ], [ result.outcome, result.ticket ]
    message = as_business(@business) { @ticket.messages.last }
    assert_equal [ "Still blurry.", "email", users(:one) ], [ message.body, message.source, message.author ]
    assert_equal "open", @ticket.reload.status

    assert_equal :replied, SupportMail.receive(email(subject: "Re: Logo [##{@ticket.uid}]", body: "And another thing")).outcome
    assert_equal 3, as_business(@business) { @ticket.messages.count }
  end

  test "an emailed reply only reaches a ticket the sender may see (OPS-05 visibility)" do
    tech = member_with_role("technician")
    tech.update_columns(last_business_id: @business.id)
    result = SupportMail.receive(email(from: tech.email, in_reply_to: "<ticket-#{@ticket.uid}-1-abcd@getshadetree.com>"))
    assert_not_equal @ticket, result.ticket, "a technician can't add to the owner's ticket by email"
    assert_equal 1, as_business(@business) { @ticket.messages.count }
  end

  test "other email from a member opens a ticket in the business they last used, with screenshots" do
    mail = email(subject: "Fwd: Can't log in on my phone", body: "It spins forever.")
    mail.add_file(filename: "shot.png", content: file_fixture("logo.png").binread)
    users(:one).update_columns(last_business_id: businesses(:two).id)
    result = SupportMail.receive(mail)
    assert_equal :opened, result.outcome
    assert_equal [ businesses(:two), "Can't log in on my phone", "Email" ], [ result.ticket.business, result.ticket.subject, result.ticket.browser ]
    assert as_business(businesses(:two)) { result.ticket.messages.first.files.attached? }
  end

  test "a reference to another business's ticket doesn't reach it; strangers and empty email are ignored" do
    result = SupportMail.receive(email(from: "user2@example.com", subject: "Re: Logo [##{@ticket.uid}]", body: "Sneaky"))
    assert_equal :opened, result.outcome
    assert_equal businesses(:two), result.ticket.business
    assert_equal 1, as_business(@business) { @ticket.messages.count }

    assert_equal :unknown_sender, SupportMail.receive(email(from: "stranger@example.net")).outcome
    assert_equal :empty, SupportMail.receive(email(body: "> only quoted")).outcome
  end
end
