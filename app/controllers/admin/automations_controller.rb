# NTF-04: Settings → Automations. Recipes switch on in one step; rules are built from the fixed
# triggers, conditions and actions; every run is listed with what it did. A plan feature: without
# it, rules are shown (and keep their history) but nothing runs and nothing can be changed.
class Admin::AutomationsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :business_settings
  before_action :require_feature, except: :index
  # Automations can email clients, so setting one up (or turning one on) needs a confirmed sender.
  before_action :require_confirmed_sender, only: %i[create update recipe]
  before_action :set_rule, only: %i[edit update destroy toggle]

  DELAY_UNITS = { "minutes" => 1, "hours" => 60, "days" => 24 * 60 }.freeze

  def index
    @rules = AutomationRule.order(:created_at).to_a
    @runs = AutomationRun.recent.includes(:subject).limit(30).to_a
    subjects = @runs.filter_map(&:subject)
    ActiveRecord::Associations::Preloader.new(records: subjects.grep(Payment), associations: :invoice).call
    ActiveRecord::Associations::Preloader.new(records: subjects.grep(Visit), associations: :job).call
    @editable = editable?
    @entitlements = current_business.entitlements
  end

  def new
    @rule = AutomationRule.new(trigger: params[:trigger].presence_in(AutomationRule::TRIGGERS.keys) || "quote_sent", delay_minutes: 0, conditions: {}, actions: [])
  end

  def create
    @rule = AutomationRule.new(rule_attributes.merge(created_by: current_user))
    return redirect_to(admin_automations_path, notice: "“#{@rule.name}” is on.") if @rule.save

    render :new, status: :unprocessable_content
  end

  def edit; end

  def update
    return redirect_to(admin_automations_path, notice: "“#{@rule.name}” saved. Runs already waiting use the new conditions and actions.") if @rule.update(rule_attributes)

    render :edit, status: :unprocessable_content
  end

  def destroy
    @rule.destroy!
    redirect_to admin_automations_path, notice: "“#{@rule.name}” deleted. Its history stays below."
  end

  def toggle
    return require_confirmed_sender if !@rule.enabled? && !current_user.can_send_to_clients?

    @rule.enabled = !@rule.enabled
    return redirect_to(admin_automations_path, notice: "“#{@rule.name}” is #{@rule.enabled ? "on" : "off"}.") if @rule.save

    redirect_to admin_automations_path, alert: @rule.errors.full_messages.to_sentence
  end

  def recipe
    recipe = AutomationRecipe::ALL[params[:key].to_s] or raise ActiveRecord::RecordNotFound
    existing = AutomationRule.find_by(recipe: recipe.key)
    return redirect_to(edit_admin_automation_path(existing), notice: "You already have “#{existing.name}”.") if existing

    rule = AutomationRecipe.install!(recipe.key, by: current_user)
    return redirect_to(admin_automations_path, notice: "“#{rule.name}” is on. You can change its wording or timing at any time.") if rule.persisted?

    redirect_to admin_automations_path, alert: rule.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordInvalid => e # its template couldn't be made (the template limit)
    redirect_to admin_automations_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_rule = @rule = AutomationRule.find_by_param!(params[:id])

  def editable? = current_business.entitlements.feature?(:automations)

  def require_feature
    return if editable?

    redirect_to admin_automations_path, alert: "Automations are part of a paid plan."
  end

  # The form's fields as a rule: a delay in a unit, ticked conditions, ticked actions.
  def rule_attributes
    form = params.expect(automation_rule: [ :name, :trigger, :delay_amount, :delay_unit, { conditions: {}, actions: {} } ])
    delay = form[:delay_amount].to_i.clamp(0, AutomationRule::MAX_DELAY_MINUTES) * DELAY_UNITS.fetch(form[:delay_unit].to_s, 60)
    conditions = (form[:conditions]&.to_h || {}).select { |key, value| AutomationRule::CONDITIONS.key?(key) && value.is_a?(String) && value.present? && value != "0" }
    actions = (form[:actions]&.to_h || {}).filter_map do |type, fields|
      next unless AutomationRule::ACTIONS.key?(type) && fields.is_a?(Hash) && fields["on"] == "1"

      { "type" => type }.merge(fields.slice("template", "team", "tag").select { _2.is_a?(String) }.compact_blank)
    end
    { name: form[:name], trigger: form[:trigger], delay_minutes: delay, conditions:, actions: }
  end
end
