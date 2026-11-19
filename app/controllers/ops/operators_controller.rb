# OPS-01: who has operator access. Granting and revoking need a fresh code and are audited;
# the last operator can't be revoked.
class Ops::OperatorsController < Ops::BaseController
  before_action :require_recent_verification, only: %i[create destroy]

  def index
    @operators = Operator.active.includes(:user, :granted_by).order(:created_at)
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    return redirect_to(ops_operators_path, alert: "There's no Shadetree account with that email. They need to sign up first.") unless user
    return redirect_to(ops_operators_path, alert: "#{user.email} is already an operator.") if Operator.for(user)

    Operator.grant!(user, by: current_user)
    audit!("operator.granted", user:)
    redirect_to ops_operators_path, notice: "#{user.email} is an operator. They'll set up two-factor the first time they open the console."
  end

  def destroy
    operator = Operator.active.find(params[:id])
    operator.revoke!(by: current_user)
    audit!("operator.revoked", user: operator.user)
    redirect_to ops_operators_path, notice: "#{operator.user.email} no longer has operator access."
  rescue Operator::LastOperator => error
    redirect_to ops_operators_path, alert: error.message
  end
end
