# OPS-02: find a person by email and see their memberships.
class Ops::UsersController < Ops::BaseController
  LIMIT = 20

  def index
    @query = params[:email].to_s.strip.downcase.first(200)
    return @users = [] if @query.blank?

    @users = User.where("LOWER(email) LIKE ?", "%#{User.sanitize_sql_like(@query)}%")
                 .includes(business_users: :business).order(:email).limit(LIMIT).to_a
  end
end
