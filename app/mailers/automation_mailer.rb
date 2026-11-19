# NTF-04: a business's own template (NTF-03), sent by an automation, with the button to the
# client's page for the quote, invoice or visit it's about.
class AutomationMailer < ClientMailer
  SUBJECTS = [ ServiceRequest, Quote, Job, Visit, Invoice, Payment ].index_by(&:name).freeze
  def template_email
    template = MessageTemplate.find_by(id: params[:template_id])
    return skip_changed_document(subject: "Automated message", error: "The template was deleted before the email went out.") unless template

    model = SUBJECTS[params[:subject_type]]
    subject = model&.find_by(id: params[:subject_id])
    return skip_changed_document(subject: template.subject, error: "The record was deleted before the email went out.") unless subject

    document = AutomationActions.document_for(subject)
    values = document_values(document, subject).merge(MessageTemplate::Values.sender(nil, @business))
    @intro = MessageTemplate.render(template.body, values)
    @link = document.client_link! if document.respond_to?(:client_link!)
    @button = { Quote => "View quote", Invoice => "View invoice", Visit => "View visit" }[document.class]
    client_mail subject: MessageTemplate.render_subject(template.subject, values)
  end

  private

  def document_values(document, subject)
    case document
    when Quote then MessageTemplate::Values.quote(document)
    when Invoice then MessageTemplate::Values.invoice(document)
    when Visit then MessageTemplate::Values.visit(document.job, document.when_label)
    when ServiceRequest then MessageTemplate::Values.request(document)
    else MessageTemplate::Values.client(AutomationActions.client_for(subject)).merge(MessageTemplate::Values.business(@business))
    end
  end
end
