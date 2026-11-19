# NTF-03: a business's own templates (a name, a subject and text with placeholders), to start a
# quote or invoice email from, and for automations (NTF-04). Same plan feature and editor as
# the catalog emails.
class Admin::CustomMessageTemplatesController < Admin::BaseController
  include MessageTemplatePreviews
  requires_permission :business_settings
  before_action :require_feature, except: %i[edit preview]
  before_action :set_template, only: %i[edit update destroy]
  rate_limit to: 120, within: 1.minute, only: :preview, with: -> { head :too_many_requests }

  def new
    @template = MessageTemplate.new(subject: "{{document_number}} from {{business_name}}", body: "Hi {{client_first_name}},\n\n\n\n{{your_name}}")
    @preview_records = preview_records(@template)
  end

  def create
    @template = MessageTemplate.new(template_params.merge(updated_by: current_user))
    return redirect_to(admin_message_templates_path, notice: "Template “#{@template.name}” saved.") if @template.save

    @preview_records = preview_records(@template)
    render :new, status: :unprocessable_content
  end

  def edit
    @editable = editable?
    @preview_records = preview_records(@template)
  end

  def update
    return redirect_to(admin_message_templates_path, notice: "Template “#{@template.name}” saved.") if @template.update(template_params.merge(updated_by: current_user))

    @editable = true
    @preview_records = preview_records(@template)
    render :edit, status: :unprocessable_content
  end

  def destroy
    @template.destroy!
    redirect_to admin_message_templates_path, notice: "Template “#{@template.name}” deleted."
  end

  def preview
    template = MessageTemplate.new(template_params)
    template.validate(:preview) # skips the per-business checks (limit, name taken) meant for saving
    render partial: "admin/message_templates/preview", locals: { template:, values: preview_values(template) }
  end

  private

  def set_template = @template = MessageTemplate.custom.find_by_param!(params[:id])

  def template_params = params.expect(message_template: %i[name subject body])

  def editable? = current_business.entitlements.feature?(:message_templates)

  def require_feature
    return if editable?

    redirect_to admin_message_templates_path, alert: "Templates of your own are part of a paid plan."
  end
end
