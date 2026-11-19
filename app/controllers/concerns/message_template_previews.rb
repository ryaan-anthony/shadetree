# NTF-03: the editor's preview can use a real recent record in place of the sample details.
# The choices are this business's own recent records of the kind the message is about.
module MessageTemplatePreviews
  extend ActiveSupport::Concern

  RECENT = 10

  private

  # [[label, "Quote:uid"], …] for the "Preview with" menu.
  def preview_records(template)
    preview_models(template).flat_map do |model|
      model.includes(model == Visit ? { job: :client } : :client).order(created_at: :desc).limit(RECENT)
           .map { [ preview_label(_1), "#{model.name}:#{_1.uid}" ] }
    end
  end

  # The chosen record's values, or nil for the samples. Only the allowed models, in this business.
  def preview_values(template)
    model_name, uid = params[:preview_record].to_s.split(":", 2)
    model = preview_models(template).find { _1.name == model_name } or return
    record = model.find_by(uid:) or return
    MessageTemplate::Values.for_record(record, user: current_user)
  end

  def preview_models(template)
    case template.kind
    when nil then [ Quote, Invoice ]
    when /\Aquote_/ then [ Quote ]
    when "invoice_sent", "payment_receipt" then [ Invoice ]
    when /\Avisit_/ then [ Visit ]
    when "request_received" then [ ServiceRequest ]
    else []
    end
  end

  def preview_label(record)
    case record
    when Quote then "Quote #{record.number} · #{record.client.display_name}"
    when Invoice then "Invoice #{record.number} · #{record.client.display_name}"
    when Visit then "Visit #{record.when_label} · #{record.job.client.display_name}"
    when ServiceRequest then "Request · #{record.contact_name.presence || record.client&.display_name || "no name"}"
    end
  end
end
