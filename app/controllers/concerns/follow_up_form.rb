# CLI-07: what the follow-up form needs, from the request page and when logging a request.
module FollowUpForm
  extend ActiveSupport::Concern

  included do
    helper_method :follow_up_confirm_digest
  end

  private

  # A new follow-up's starting point: a site visit today (on the request location's clock),
  # anytime, with no duration until one's given (RequestFollowUp::DEFAULT_MINUTES).
  def start_follow_up(request, user: nil)
    RequestFollowUp.new(business: current_business, service_request: request, user:, kind: "visit", scheduled_on: request.location&.today || current_business.today,
                        timing: "anytime", start_time: "09:00", window_end_time: "11:00", duration_minutes: nil)
  end

  # Whether to show warnings before going ahead: for a new follow-up, or a change of who or
  # when, unless these exact warnings were seen and confirmed (as visits do, JOB-02).
  def follow_up_warn?(follow_up)
    changed = follow_up.new_record? || (follow_up.changes.keys & %w[user_id scheduled_on timing starts_at window_ends_at duration_minutes]).any?
    @warnings = changed ? VisitWarnings.for([ follow_up ]) : []
    @warnings.any? && params[:confirm] != follow_up_confirm_digest
  end

  def follow_up_confirm_digest = Admin::VisitsController.digest(@warnings)

  # The form's fields, with the person picked from this business's active members (nil, which
  # validation refuses, for anyone else). A blank duration means the kind's usual one.
  FIELDS = %i[user_id kind scheduled_on timing start_time window_end_time duration_hours instructions lock_version].freeze

  # The submitted follow-up fields (empty when there are none, or they aren't a set of fields).
  def follow_up_fields = params.permit(request_follow_up: FIELDS).fetch(:request_follow_up, ActionController::Parameters.new.permit!)

  def follow_up_attributes(fields)
    attributes = fields.slice(*(FIELDS - [ :user_id ])).to_h.symbolize_keys
    if attributes.key?(:duration_hours) && attributes[:duration_hours].blank?
      attributes.delete(:duration_hours)
      attributes[:duration_minutes] = nil
    end
    member = current_business.business_users.active.find_by(user_id: fields[:user_id].to_i) if fields[:user_id].to_s.match?(/\A\d+\z/)
    attributes.merge(user: member&.user)
  end
end
