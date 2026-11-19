# NTF-03: Settings → Messages. Owners and Admins change the subject and opening text of each
# client-facing email, with a live preview, or go back to the default. Editing is a plan
# feature; on a plan without it, customized messages keep sending and are shown read-only.
class Admin::MessageTemplatesController < Admin::BaseController
  requires_permission :business_settings
  before_action :set_template, only: %i[edit update destroy preview]
  before_action :require_feature, only: %i[update destroy]

  def index
    @templates = MessageTemplate.all.index_by(&:kind)
    @editable = editable?
  end

  def edit
    @editable = editable?
  end

  def update
    @template.assign_attributes(template_params.merge(updated_by: current_user))
    if @template.save
      redirect_to admin_message_templates_path, notice: "Saved. #{EmailCatalog.find(@template.kind).name} emails now use your wording."
    else
      @editable = true
      render :edit, status: :unprocessable_content
    end
  end

  # Back to the default wording.
  def destroy
    @template.destroy! if @template.persisted?
    redirect_to admin_message_templates_path, notice: "#{EmailCatalog.find(@template.kind).name} is back to the default wording."
  end

  # The live preview, as the form is typed: sample values, and any problem with the text.
  def preview
    @template.assign_attributes(template_params)
    @template.validate
    render partial: "preview", locals: { template: @template }
  end

  private

  def set_template
    kind = params[:kind].to_s
    raise ActiveRecord::RecordNotFound unless MessageTemplate::DEFINITIONS.key?(kind)

    @template = MessageTemplate.for_kind(kind) || begin
      definition = MessageTemplate.definition(kind)
      MessageTemplate.new(kind:, subject: definition.subject, body: definition.body)
    end
  end

  def template_params = params.expect(message_template: %i[subject body])

  def editable? = current_business.entitlements.feature?(:message_templates)

  def require_feature
    return if editable?

    redirect_to admin_message_templates_path, alert: "Editing messages isn't included in your plan. Your customized messages still send."
  end
end
