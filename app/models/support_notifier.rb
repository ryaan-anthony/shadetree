# OPS-05: tells a ticket's people about support's reply, in the app and by email (NTF-02's
# "support_reply", which each can turn off by email in their settings): every active member who
# wrote on the ticket, or, when none of them is left, the business's Owners. Only people who may
# still see the ticket (SupportTicket.visible_to): a role change or a billing ticket keeps others out.
module SupportNotifier
  module_function

  def replied(ticket, message, title: "Shadetree support replied: #{ticket.subject}")
    people = recipients(ticket)
    return [] if people.empty?

    NotificationType.deliver("support_reply", business: ticket.business, to: people, subject: ticket, title:,
                                              body: message.body.truncate(200),
                                              path: Rails.application.routes.url_helpers.admin_support_ticket_path(ticket),
                                              email: ->(user) { SupportMailer.with(business_id: ticket.business_id, message_id: message.id, user:).reply })
    people
  end

  def recipients(ticket)
    memberships = ticket.business.business_users.active.includes(:user).to_a.reject { _1.user.deleted? }
    writers = Tenancy.with_business(ticket.business) { ticket.messages.unscope(:order).where(from_operator: false).distinct.pluck(:author_id) }
    can_see = ->(membership) { Tenancy.with_business(ticket.business) { SupportTicket.visible_to(membership).exists?(ticket.id) } }
    took_part = memberships.select { writers.include?(_1.user_id) && can_see.(_1) }
    (took_part.presence || memberships.select { _1.owner? && can_see.(_1) }).map(&:user)
  end
end
