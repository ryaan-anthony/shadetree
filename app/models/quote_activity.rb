# A quote's activity history for staff (QTE-06), newest first, from the records each step
# already keeps: the quote (created), its sends, its client links' views and requests, the
# client's responses, and QuoteEvent for staff actions nothing else records. Views are
# grouped between other events ("Viewed 3 times") so a busy quote stays readable.
#
#   QuoteActivity.for(quote) # => [QuoteActivity::Entry, ...]
class QuoteActivity
  # `since` is the first of a run of views ("Viewed 3 times, Nov 9 to Nov 11").
  Entry = Data.define(:at, :icon, :title, :detail, :since) do
    def initialize(at:, icon:, title:, detail: nil, since: nil) = super
  end

  def self.for(quote) = new(quote).entries

  def initialize(quote)
    @quote = quote
  end

  def entries
    (created + sends + responses + events + update_request + expiry + grouped_views(others_at: (sends + responses + events).map(&:at)))
      .sort_by { [ _1.at, _1.title ] }.reverse
  end

  private

  attr_reader :quote

  def created
    duplicated = quote.events.find { _1.kind == "duplicated" }
    by = " by #{quote.created_by.full_name}" if quote.created_by
    title = duplicated ? "Duplicated from #{duplicated.data["from"]}#{by}" : "Created#{by}"
    [ Entry.new(at: quote.created_at, icon: "file-plus", title:) ]
  end

  def sends
    quote.sends.includes(:user, :email_message).map do |send|
      by = " by #{send.user.full_name}" if send.user
      what = send.revision > 1 ? "Revision #{send.revision}" : nil
      title = send.channel == "email" ? "#{what || "Emailed"}#{" emailed" if what} to #{send.recipient}#{by}" : "#{what ? "#{what} sent as a link" : "Link copied"}#{by}"
      detail = "Not delivered: #{send.email_message.error.presence || send.email_message.status_label.downcase}" if send.email_message&.problem?
      Entry.new(at: send.created_at, icon: "send", title:, detail:)
    end
  end

  def responses
    quote.responses.includes(:recorded_by).map do |response|
      title = if response.on_behalf?
        "Marked approved by #{response.recorded_by&.full_name || "a former member"} for #{response.signer_name}"
      elsif response.approved? then "Approved by #{response.signer_name}"
      else "#{response.label} by the client"
      end
      Entry.new(at: response.created_at, icon: RESPONSE_ICONS.fetch(response.kind), title:, detail: response.message)
    end
  end
  RESPONSE_ICONS = { "approved" => "check-circle", "declined" => "x-circle", "changes_requested" => "message-square" }.freeze

  def events
    quote.events.includes(:user).filter_map do |event|
      by = " by #{event.actor_label}" if event.user
      case event.kind
      when "archived" then Entry.new(at: event.occurred_at, icon: "archive", title: "Archived#{by}")
      when "unarchived" then Entry.new(at: event.occurred_at, icon: "rotate-ccw", title: "Restored from the archive#{by}")
      when "expiry_extended"
        from = event.data["from"] ? " from #{I18n.l(Date.parse(event.data["from"]))}" : ""
        Entry.new(at: event.occurred_at, icon: "calendar", title: "Valid-until date moved#{from} to #{I18n.l(Date.parse(event.data["to"]))}#{by}")
      when "ready_for_review" then Entry.new(at: event.occurred_at, icon: "check-square", title: "Marked ready for review#{by}") # QTE-07
      when "revised" then Entry.new(at: event.occurred_at, icon: "edit-3", title: "Revision #{event.data["revision"]} started#{by}")
      when "repriced" then Entry.new(at: event.occurred_at, icon: "tag", title: "#{Array(event.data["changed"]).join(" and ").capitalize} set for #{event.data["location"]}#{by}")
      end
    end
  end

  # The end of the valid-until day, if it passed while the client still hadn't answered.
  def expiry
    return [] unless quote.expired?

    [ Entry.new(at: quote.expires_on.in_time_zone(quote.business.time_zone).end_of_day, icon: "clock", title: "Expired without an answer") ]
  end

  def update_request
    return [] unless quote.update_requested_at

    [ Entry.new(at: quote.update_requested_at, icon: "clock", title: "The client asked for an updated quote") ]
  end

  # Client views, one entry per run of views between other events. Only the latest few hundred
  # are read: every page load is a view, and a history doesn't need them all.
  VIEWS_SHOWN = 500
  def grouped_views(others_at:)
    views = ClientLinkEvent.joins(:client_link).where(client_links: { linkable_type: "Quote", linkable_id: quote.id }, kind: "view")
                           .order(occurred_at: :desc).limit(VIEWS_SHOWN).pluck(:occurred_at).reverse
    views.chunk_while { |a, b| others_at.none? { _1 > a && _1 <= b } }.map do |run|
      Entry.new(at: run.last, icon: "eye", title: run.one? ? "Viewed by the client" : "Viewed #{run.size} times", since: (run.first if run.many?))
    end
  end
end
