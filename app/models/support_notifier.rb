# OPS-05: tells the member who opened a ticket about support's reply, in the app and by email
# (NTF-02's "support_reply", which they can turn off by email in their settings).
module SupportNotifier
  module_function

  def replied(ticket, message, title: "Shadetree support replied: #{ticket.subject}")
    return unless ticket.opened_by

    NotificationType.deliver("support_reply", business: ticket.business, to: [ ticket.opened_by ], subject: ticket, title:,
                                              body: message.body.truncate(200),
                                              path: Rails.application.routes.url_helpers.admin_support_ticket_path(ticket),
                                              email: ->(user) { SupportMailer.with(business_id: ticket.business_id, message_id: message.id, user:).reply })
  end
end
