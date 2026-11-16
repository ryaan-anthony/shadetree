# ACC-05: the steps a new owner takes to send a first quote, each ticked from real data (never
# a stored checkbox), linking into the real feature with from=setup so it returns here.
#
#   checklist = SetupChecklist.new(business)
#   checklist.steps      # => [SetupChecklist::Step, ...]
#   checklist.complete?  # every required step done (branding is optional)
class SetupChecklist
  Step = Data.define(:key, :title, :text, :done, :optional, :action)

  def initialize(business, membership: nil)
    @business = business
    @membership = membership
  end

  def steps
    @steps ||= [
      Step.new(key: "details", title: "Add your business details", text: "Your phone, email and address go on every quote; the time zone sets due dates.",
               done: details?, optional: false, action: "Add details"),
      Step.new(key: "services", title: "Add your services and prices", text: services_text, done: priced_services?, optional: false,
               action: services_action),
      Step.new(key: "branding", title: "Add your logo and colour", text: "Optional. They brand every page and email your clients see.",
               done: business.logo.attached? || business.brand_color != Branding::DEFAULT_COLOR, optional: true, action: "Add branding"),
      Step.new(key: "client", title: "Add a client", text: "A name and a phone number or email is enough.", done: Client.exists?, optional: false,
               action: "Add a client"),
      Step.new(key: "quote", title: "Create and send your first quote", text: "Pick the client, add services, send it by email or as a link.",
               done: business.first_quote_sent_at.present?, optional: false, action: latest_draft ? "Finish your quote" : "Create a quote")
    ]
  end

  def required = steps.reject(&:optional)
  def done_count = required.count(&:done)
  def complete? = required.all?(&:done)

  # Shown on the dashboard until it's finished (businesses.onboarded_at, stamped the first time
  # it's complete) or this member hid it for themselves.
  def visible? = business.onboarded_at.nil? && membership&.setup_hidden_at.nil? && !finish!
  def hidden_by_member? = business.onboarded_at.nil? && membership&.setup_hidden_at.present?

  def latest_draft = defined?(@latest_draft) ? @latest_draft : (@latest_draft = Quote.drafts.order(updated_at: :desc).first)

  # Starter services come without prices; the step is done when something has a price.
  def unpriced_services? = CatalogItem.active.exists? && !priced_services?

  # The industry's starter services, offered in one action.
  def preset
    return @preset if defined?(@preset)

    @preset = (IndustryPreset.for(business.industry) if business.industry.present?)
  end

  private

  attr_reader :business, :membership

  # Remembers the first time every required step is done, so the checklist stays gone even if
  # a detail is cleared later (and the dashboard stops checking).
  def finish!
    return false unless complete?

    business.update_columns(onboarded_at: Time.current)
    true
  end

  def priced_services? = CatalogItem.active.where("unit_price_cents > 0").exists?

  def services_action
    return "Set your prices" if CatalogItem.active.exists?

    preset ? "Add #{preset.item_list.size} starter services" : "Add services"
  end

  def details? = business.phone.present? && business.email.present? && business.address_line1.present? && business.timezone.present?

  def services_text
    return "Your services are in the catalog; give at least one a price." if unpriced_services?
    return "Start from the common services for your industry, then set your prices." unless preset

    "#{preset.item_list.first(3).map(&:name).join(", ")} and more, ready to price."
  end
end
