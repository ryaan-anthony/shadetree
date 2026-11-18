# NTF-02: the kinds of team notification, who gets each, and whether it's emailed by default.
# Every feature raises its notifications through NotificationType.deliver:
#
#   NotificationType.deliver("quote_approved", business:, subject: quote, actor: nil,
#                            title: "Maria Lopez approved Q-0042", body: "$1,240.00",
#                            path: admin_quote_path(quote),
#                            email: ->(user) { QuoteActivityMailer.with(...).responded })
#
# Each member gets the in-app notification; those who want the type by email (their choice in
# Settings, or the type's default) and have confirmed their account also get the email. The
# person who did it is left out. Without `email:`, the email is a short NotificationMailer
# notice with the title and a link.
#
# Adding a type: add a Definition below (kind, the label and hint shown in each member's email
# settings, the permission its recipients need, and the email default), then call deliver
# where it happens. For events about one person's work, like a visit assigned to them (JOB-02),
# pass `to:` with the users instead of using the permission.
class NotificationType
  Definition = Data.define(:kind, :label, :hint, :permission, :email_by_default, :icon)

  ALL = [
    Definition.new(kind: "new_request", label: "New requests", hint: "Someone sends your request form.",
                   permission: :office, email_by_default: true, icon: "inbox"),
    Definition.new(kind: "quote_viewed", label: "Quote opened", hint: "The first time a client opens a quote.",
                   permission: :office, email_by_default: false, icon: "eye"),
    Definition.new(kind: "quote_approved", label: "Quote approved", hint: "By the client, or recorded by a teammate.",
                   permission: :office, email_by_default: true, icon: "check-circle"),
    Definition.new(kind: "quote_declined", label: "Quote declined", hint: "With the client's reason, if they gave one.",
                   permission: :office, email_by_default: true, icon: "x-circle"),
    Definition.new(kind: "quote_changes_requested", label: "Changes requested", hint: "A client asks for changes to a quote.",
                   permission: :office, email_by_default: true, icon: "edit-3"),
    Definition.new(kind: "invitation_accepted", label: "Someone joins the team", hint: "An invitation you or a teammate sent is accepted.",
                   permission: :manage_team, email_by_default: false, icon: "user-plus")
  ].index_by(&:kind).freeze

  class UnknownKind < ArgumentError; end

  def self.kinds = ALL.keys
  def self.fetch(kind) = ALL.fetch(kind.to_s) { raise UnknownKind, "No notification type #{kind.inspect}" }

  # The types a member can receive, for their settings.
  def self.for(membership) = ALL.values.select { membership.can?(_1.permission) }

  def self.deliver(kind, business:, title:, path:, subject: nil, body: nil, actor: nil, to: nil, email: nil)
    type = fetch(kind)
    memberships = business.business_users.active.includes(:user).to_a
    memberships = to ? memberships.select { |m| Array(to).map(&:id).include?(m.user_id) } : memberships.select { _1.can?(type.permission) }
    memberships.reject! { _1.user_id == actor&.id }

    Tenancy.with_business(business) do
      memberships.each do |membership|
        notification = Notification.create!(user: membership.user, kind: type.kind, subject:, actor:, title:, body:, path:)
        next unless membership.email_notification?(type.kind) && membership.user.confirmed?

        (email ? email.call(membership.user) : NotificationMailer.with(notification_id: notification.id, business_id: business.id).notice).deliver_later
      end
    end
  end
end
