# OPS-01: the audit log, newest first, filtered by operator, action, business and dates.
class Ops::AuditEntriesController < Ops::BaseController
  PER_PAGE = 50

  def index
    scope = AuditEntry.newest_first.includes(:business, :target_user)
    scope = scope.where(operator_email: params[:operator]) if params[:operator].present?
    scope = scope.where(action: params[:action_name]) if params[:action_name].present?
    @business = Business.find_by(uid: params[:business].to_s) if params[:business].present?
    scope = scope.where(business: @business) if params[:business].present?
    from = parse_date(params[:from])
    to = parse_date(params[:to])
    scope = scope.where(created_at: from.beginning_of_day..) if from
    scope = scope.where(created_at: ..to.end_of_day) if to
    @page = [ params[:page].to_i, 1 ].max
    @entries = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @more = @entries.size > PER_PAGE
    @entries = @entries.first(PER_PAGE)
    @operators = AuditEntry.distinct.order(:operator_email).pluck(:operator_email)
    @actions = AuditEntry.distinct.order(:action).pluck(:action)
  end

  private

  def parse_date(value) = value.present? ? (Date.iso8601(value) rescue nil) : nil # rubocop:disable Style/RescueModifier
end
