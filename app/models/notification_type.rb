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
# Delivery happens once the surrounding transaction commits (so a change that's rolled back
# notifies nobody, and emails never go out before their notification exists), and it never
# raises: a notification problem is reported, but can't break or undo what was done.
#
# Adding a type: add a Definition below (kind, the label and hint shown in each member's email
# settings, the permission its recipients need, and the email default), then call deliver
# where it happens. For events about one person's work, like a visit assigned to them (JOB-02),
# define the type with `audience: :named` and pass `to:` with the users; the permission then
# only decides whose settings list it.
class NotificationType
  Definition = Data.define(:kind, :label, :hint, :permission, :email_by_default, :icon, :audience) do
    def initialize(audience: :permission, **) = super
    def named? = audience == :named
  end

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
    Definition.new(kind: "invoice_viewed", label: "Invoice opened", hint: "The first time a client opens an invoice.",
                   permission: :office, email_by_default: false, icon: "eye"),
    Definition.new(kind: "invitation_accepted", label: "Someone joins the team", hint: "An invitation you or a teammate sent is accepted.",
                   permission: :manage_team, email_by_default: false, icon: "user-plus"),
    # JOB-02: to the people going on a visit.
    Definition.new(kind: "visit_assigned", label: "You're put on a visit", hint: "A visit is booked with you on it, or you're added to one.",
                   permission: :field_work, email_by_default: true, icon: "calendar", audience: :named),
    Definition.new(kind: "visit_changed", label: "A visit you're on changes", hint: "It moves, its instructions change, or you're taken off it.",
                   permission: :field_work, email_by_default: true, icon: "clock", audience: :named),
    Definition.new(kind: "job_ready_to_invoice", label: "A job is ready to invoice", hint: "The last visit on a job is completed.",
                   permission: :office, email_by_default: true, icon: "check-circle"),
    Definition.new(kind: "visit_cancelled", label: "A visit you're on is cancelled", hint: "With the reason, if one was given.",
                   permission: :field_work, email_by_default: true, icon: "x-circle", audience: :named),
    Definition.new(kind: "automation", label: "Automation notices", hint: "An automation's “notify the team” step.", # NTF-04
                   permission: :field_work, email_by_default: true, icon: "zap", audience: :named)
  ].index_by(&:kind).freeze

  class UnknownKind < ArgumentError; end

  def self.kinds = ALL.keys
  def self.fetch(kind) = ALL.fetch(kind.to_s) { raise UnknownKind, "No notification type #{kind.inspect}" }

  # The types a member can receive, for their settings.
  def self.for(membership) = ALL.values.select { membership.can?(_1.permission) }

  def self.deliver(kind, business:, title:, path:, subject: nil, body: nil, actor: nil, to: nil, email: nil)
    type = fetch(kind)
    raise ArgumentError, "#{kind} is for named people: pass to:" if type.named? && to.nil?
    raise ArgumentError, "#{kind} goes by permission: don't pass to:" if !type.named? && to

    ActiveRecord.after_all_transactions_commit do
      recipients(type, business, to:, actor:).each do |membership|
        deliver_to(membership, type, business, email:, subject:, actor:, title:, body:, path:)
      end
    end
  end

  def self.recipients(type, business, to:, actor:)
    memberships = business.business_users.active.includes(:user).to_a
    named = to && Array(to).to_set(&:id)
    memberships = named ? memberships.select { named.include?(_1.user_id) && _1.can?(type.permission) } : memberships.select { _1.can?(type.permission) }
    memberships.reject { _1.user_id == actor&.id }
  end

  def self.deliver_to(membership, type, business, email:, **attributes)
    Tenancy.with_business(business) do
      notification = Notification.create!(user: membership.user, kind: type.kind, **attributes)
      next unless membership.email_notification?(type.kind) && membership.user.confirmed?

      (email ? email.call(membership.user) : NotificationMailer.with(notification_id: notification.id, business_id: business.id).notice).deliver_later
    end
  rescue StandardError => e
    Rails.error.report(e, context: { notification_kind: type.kind, user_id: membership.user_id })
  end
  private_class_method :recipients, :deliver_to
end
