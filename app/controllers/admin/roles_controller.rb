# ACC-07: Team → Roles. Owners see what each role can do, and build roles of their own from
# the permission catalog (starting blank or from another role). A role in use is deleted by
# choosing where its members go. Custom roles are a plan feature: without it they keep working
# and are shown read-only.
class Admin::RolesController < Admin::BaseController
  requires_permission :manage_owners
  before_action :require_feature, except: %i[index edit]
  before_action :set_role, only: %i[edit update delete destroy]

  def index
    @roles = Role.ordered.to_a
    @counts = current_business.business_users.active.where.not(role_id: nil).group(:role_id).count
    @editable = editable?
  end

  # ?from=admin|technician|<uid> starts from that role's permissions.
  def new
    source = params[:from].to_s
    permissions = Permissions::ROLES[source] || Role.find_by(uid: source)&.permissions || []
    name = (Permissions::ROLES.key?(source) ? source.humanize : Role.find_by(uid: source)&.name).then { _1 && "#{_1} (copy)" }
    @role = Role.new(name:, permissions: permissions.map(&:to_s) & Permissions::GRANTABLE.map(&:to_s))
  end

  def create
    @role = Role.new(role_params)
    if @role.save
      RoleEvent.record!(@role, "created", by: current_user, permissions: @role.permissions)
      redirect_to admin_roles_path, notice: "#{@role.name} created. Give it to someone from the team page."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @editable = editable?
    @events = @role.events.recent.includes(:user).limit(20)
  end

  def update
    if @role.update(role_params)
      changes = @role.saved_changes.slice("name", "permissions").transform_values { |(was, now)| { "from" => was, "to" => now } }
      RoleEvent.record!(@role, "changed", by: current_user, **changes.symbolize_keys) if changes.any?
      redirect_to admin_roles_path, notice: "#{@role.name} saved. Members with it have the new permissions on their next click."
    else
      @editable = true
      @events = @role.events.recent.includes(:user).limit(20)
      render :edit, status: :unprocessable_content
    end
  end

  # Confirms deleting, and asks where its members go if anyone has it.
  def delete
    @members = @role.business_users.includes(:user).order("users.first_name").to_a
    @replacements = [ [ "Technician", "technician" ], [ "Admin", "admin" ] ] + Role.ordered.where.not(id: @role.id).map { [ _1.name, _1.choice ] }
  end

  def destroy
    replacement = params[:replacement].to_s
    target = if %w[admin technician].include?(replacement) then replacement
    else Role.where.not(id: @role.id).find_by(uid: replacement.delete_prefix("role:"))
    end
    return redirect_to(delete_admin_role_path(@role), alert: "Choose a role for its members.") if @role.in_use? && target.nil?

    @role.replace_with!(target || "technician", by: current_user)
    redirect_to admin_roles_path, notice: "#{@role.name} deleted."
  end

  private

  def set_role = @role = Role.find_by_param!(params[:id])

  def role_params = params.expect(role: [ :name, { permissions: [] } ])

  def editable? = current_business.entitlements.feature?(:custom_roles)

  def require_feature
    return if editable?

    redirect_to admin_roles_path, alert: "Custom roles aren't included in your plan. Roles you already have keep working."
  end
end
