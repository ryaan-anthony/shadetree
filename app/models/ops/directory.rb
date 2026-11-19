# OPS-02: the operator business directory. Searches every business (name, or a member's email),
# filters by plan, status and signup dates, and sorts by signup or last activity. Business-level
# data only: no business-owned records are read here.
#
#   Ops::Directory.new(params).businesses  # => a relation with last_active_at on each row
class Ops::Directory
  STATUSES = { "active" => "Active", "suspended" => "Suspended", "closed" => "Closed" }.freeze
  FILTERS = STATUSES.merge("deleting" => "Scheduled for deletion").freeze
  SORTS = { "signup" => "Newest sign-ups", "activity" => "Recently active", "inactive" => "Least recently active" }.freeze
  LAST_ACTIVE_SQL = "(SELECT MAX(bu.last_active_at) FROM business_users bu WHERE bu.business_id = businesses.id)".freeze

  attr_reader :query, :plan_id, :status, :from, :to, :sort

  def initialize(params)
    @query = params[:q].to_s.strip.first(200)
    @plan_id = params[:plan].presence&.to_i
    @status = FILTERS.key?(params[:status]) ? params[:status] : nil
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "signup"
  end

  def filtered? = query.present? || plan_id || status || from || to

  def businesses
    scope = Business.includes(:plan, business_users: :user).select("businesses.*", "#{LAST_ACTIVE_SQL} AS last_active_at")
    scope = search(scope) if query.present?
    scope = scope.where(plan_id:) if plan_id
    scope = filter_status(scope) if status
    scope = scope.where(created_at: from.beginning_of_day..) if from
    scope = scope.where(created_at: ..to.end_of_day) if to
    scope.order(Arel.sql(order_sql))
  end

  # The first active Owner (the creator may have left, or deleted their account).
  def self.owner_of(business) = business.business_users.select { _1.active? && _1.owner? }.min_by(&:created_at)&.user

  # The status shown beside a business. Trial and past due come with subscriptions (BIL-04/05).
  def self.status_of(business)
    if business.active? then "active"
    elsif business.suspended? then "suspended"
    else "closed"
    end
  end

  private

  def search(scope)
    pattern = "%#{Business.sanitize_sql_like(query.downcase)}%"
    members = BusinessUser.joins(:user).where("LOWER(users.email) LIKE ?", pattern).select(:business_id)
    scope.where("LOWER(businesses.name) LIKE ?", pattern).or(scope.where(id: members))
  end

  def filter_status(scope)
    case status
    when "active" then scope.where(active: true)
    when "suspended" then scope.where.not(suspended_at: nil)
    when "deleting" then scope.where.not(deletion_due_at: nil)
    else scope.where(active: false, suspended_at: nil)
    end
  end

  def order_sql
    case sort
    when "activity" then "last_active_at DESC NULLS LAST, businesses.id DESC"
    when "inactive" then "last_active_at ASC NULLS FIRST, businesses.id"
    else "businesses.created_at DESC, businesses.id DESC"
    end
  end

  def parse_date(value) = value.present? ? (Date.iso8601(value.to_s) rescue nil) : nil # rubocop:disable Style/RescueModifier
end
