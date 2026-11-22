# ACC-05: the steps a new owner takes from an empty business to a first quote sent and online
# payments (#289), each ticked from real data (never a stored checkbox), linking into the real
# feature with from=setup so it returns here.
#
#   checklist = SetupChecklist.new(business)
#   checklist.steps      # => [SetupChecklist::Step, ...]
#   checklist.complete?  # every step done
class SetupChecklist
  Step = Data.define(:key, :title, :text, :done, :optional, :action)

  def initialize(business, membership: nil)
    @business = business
    @membership = membership
  end

  # #289: four steps, from an empty business to being paid: services, a client, the first quote
  # sent and online payments. The business details a quote needs come first inside the quote
  # step; branding is in Settings (and the ACC-08 tour points there).
  def steps
    @steps ||= [
      Step.new(key: "services", title: "Add your services and prices", text: services_text, done: priced_services?, optional: false,
               action: services_action),
      Step.new(key: "client", title: "Add a client", text: "A name and a phone number or email is enough.", done: Client.exists?, optional: false,
               action: "Add a client"),
      Step.new(key: "quote", title: "Send your first quote", text: quote_text, done: business.first_quote_sent_at.present?, optional: false,
               action: quote_action),
      Step.new(key: "payments", title: "Get paid online", text: "Clients pay by card, Apple Pay or Google Pay from the invoice, straight to your own Stripe account.",
               done: business.payment_account&.accepts_payments? || false, optional: false, action: "Set up payments")
    ]
  end

  def required = steps.reject(&:optional)
  def done_count = required.count(&:done)
  def complete? = required.all?(&:done)

  # Shown on the dashboard until it's finished (businesses.onboarded_at, stamped the first time
  # it's complete) or this member hid it for themselves.
  def visible? = business.onboarded_at.nil? && membership&.setup_hidden_at.nil? && !finish!
  def hidden_by_member? = business.onboarded_at.nil? && membership&.setup_hidden_at.present?

  # The quote step opens the business details first when a quote would go out without them.
  def details? = business.phone.present? && business.email.present? && business.address_line1.present? && business.timezone.present?

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

  def quote_action
    return "Add your details first" unless details?

    latest_draft ? "Finish your quote" : "Create a quote"
  end

  def quote_text
    return "Your phone, email and address go on every quote, so add them first. Then pick the client and services, and send." unless details?

    "Pick the client, add services, send it by email or as a link."
  end

  def services_text
    return "Your services are in the catalog; give at least one a price." if unpriced_services?
    return "Start from the common services for your industry, then set your prices." unless preset

    "#{preset.item_list.first(3).map(&:name).join(", ")} and more, ready to price."
  end
end
