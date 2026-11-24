# ACC-08: the guided tour a member gets, fitted to their role. Office members take it on Home
# (the checklist, then the menu); people who only do field work take a short one on My day.
# A stop is left out when the role can't use what it points at. Wording: config/locales/guidance.en.yml.
#
#   tour = GuidedTour.for(membership, checklist:)   # nil when the role has nothing to tour
#   tour.page                                       # :office (Home) or :field (My day)
#   tour.stops                                      # => [GuidedTour::Stop, ...]
#
# Each stop points at the element with data-tour="<target>"; the browser falls back to the next
# target listed when one isn't on the page.
class GuidedTour
  Stop = Data.define(:key, :targets, :title, :text, :link)
  STATUSES = %w[offered started finished skipped].freeze
  EVENTS = %w[start step finish end resume].freeze
  OFFER = "offer" # the stop recorded when someone skips from the offer

  def self.for(membership, checklist: nil)
    return unless membership&.active?

    if membership.can?(:office) || membership.can?(:business_settings)
      new(membership, :office, checklist)
    elsif membership.can?(:field_work)
      new(membership, :field, checklist)
    end
  end

  attr_reader :page

  def initialize(membership, page, checklist)
    @membership = membership
    @page = page
    @checklist = checklist
  end

  def stops = @stops ||= (page == :office ? office_stops : field_stops)
  def keys = stops.map(&:key)

  # Checklist steps only some roles can act on; the others see them, with nothing to press.
  STEP_PERMISSIONS = { "payments" => :billing }.freeze

  # The last stop leads to the first unfinished checklist step this person can act on:
  # [label, the step's element id].
  def next_step
    step = checklist? && checklist.required.find { !_1.done && can?(STEP_PERMISSIONS.fetch(_1.key, :business_settings)) }
    [ I18n.t("guidance.tour.finish_to_step", step: step.title), "setup-#{step.key}" ] if step
  end

  def as_json(*)
    { stops: stops.map { |stop| stop.to_h.merge(link: stop.link&.then { |label, href| { label:, href: } }) }, next_step: next_step&.then { |label, id| { label:, id: } } }
  end

  private

  attr_reader :membership, :checklist

  def can?(permission) = membership.can?(permission)

  # Home shows the setup checklist only to people who can change the business's settings.
  def checklist? = can?(:business_settings) && checklist&.visible?

  def office_stops
    [
      (checklist? ? stop(:home, %w[checklist home], copy: :home_checklist) : stop(:home, %w[home])),
      (stop(:requests) if can?(:office)),
      (stop(:quotes, link: (sample_quote_link if can?(:business_settings))) if can?(:office)),
      (stop(:schedule) if can?(:schedule)),
      (stop(:invoices) if can?(:office)),
      (stop(:settings, copy: (can?(:billing) ? :settings_owner : :settings)) if can?(:business_settings))
    ].compact
  end

  def field_stops = [ stop(:my_day, %w[today my_day]), stop(:coming_up), stop(:help) ]

  def stop(key, targets = [ key.to_s ], copy: key, link: nil)
    scope = "guidance.tour.#{page}.#{copy}"
    Stop.new(key: key.to_s, targets:, title: I18n.t("#{scope}.title"), text: I18n.t("#{scope}.text"), link:)
  end

  def sample_quote_link = [ I18n.t("guidance.tour.office.quotes.link"), Rails.application.routes.url_helpers.admin_sample_quote_path ]
end
