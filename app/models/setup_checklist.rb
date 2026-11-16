# ACC-05: the steps a new owner takes to send a first quote, each ticked from real data (never
# a stored checkbox), linking into the real feature with from=setup so it returns here.
#
#   checklist = SetupChecklist.new(business)
#   checklist.steps      # => [SetupChecklist::Step, ...]
#   checklist.complete?  # every required step done (branding is optional)
class SetupChecklist
  Step = Data.define(:key, :title, :text, :done, :optional, :action)

  def initialize(business)
    @business = business
  end

  def steps
    @steps ||= [
      Step.new(key: "details", title: "Add your business details", text: "Your phone, email and address go on every quote; the time zone sets due dates.",
               done: details?, optional: false, action: "Add details"),
      Step.new(key: "services", title: "Add your services", text: services_text, done: CatalogItem.exists?, optional: false,
               action: preset ? "Add #{preset.item_list.size} starter services" : "Add services"),
      Step.new(key: "branding", title: "Add your logo and colour", text: "Optional. They brand every page and email your clients see.",
               done: business.logo.attached? || business.brand_color != Branding::DEFAULT_COLOR, optional: true, action: "Add branding"),
      Step.new(key: "client", title: "Add a client", text: "A name and a phone number or email is enough.", done: Client.exists?, optional: false,
               action: "Add a client"),
      Step.new(key: "quote", title: "Create and send your first quote", text: "Pick the client, add services, send it by email or as a link.",
               done: business.first_quote_sent_at.present?, optional: false, action: Quote.drafts.exists? ? "Finish your quote" : "Create a quote")
    ]
  end

  def required = steps.reject(&:optional)
  def done_count = required.count(&:done)
  def complete? = required.all?(&:done)

  # Shown on the dashboard until it's complete or dismissed (businesses.onboarded_at).
  def visible? = business.onboarded_at.nil? && !complete?

  # The industry's starter services, offered in one action.
  def preset
    return @preset if defined?(@preset)

    @preset = (IndustryPreset.for(business.industry) if business.industry.present?)
  end

  private

  attr_reader :business

  def details? = business.phone.present? && business.email.present? && business.address_line1.present? && business.timezone.present?

  def services_text
    return "Start from the common services for your industry, then set your prices." unless preset

    "#{preset.item_list.first(3).map(&:name).join(", ")} and more, ready to price."
  end
end
