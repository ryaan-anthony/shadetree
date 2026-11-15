# Staff authorization (ACC-04). Every action in a staff controller must declare what it needs,
# and anything undeclared is denied:
#
#   class Admin::ClientsController < Admin::BaseController
#     requires_permission :office                        # every action
#     requires_permission :export_data, only: :export    # a stricter rule for one action
#   end
#
#   allow_any_member only: :index                        # any active member of the business
#   allow_without_business only: %i[new create]          # signed in, no business needed
#
# Use can?(:permission) in views to hide what someone can't do. Permissions and roles live in
# Permissions (the capability table in docs/plans/02-accounts.md).
module Authorization
  extend ActiveSupport::Concern

  Rule = Data.define(:kind, :permission, :only, :except) do
    def applies?(action)
      (only.nil? || only.include?(action)) && !except&.include?(action)
    end
  end

  included do
    class_attribute :authorization_rules, instance_writer: false, default: []
    before_action :authorize_action!
    helper_method :can?
  end

  class_methods do
    def requires_permission(permission, only: nil, except: nil)
      Permissions::CATALOG.fetch(permission.to_sym) { raise Permissions::UnknownPermission, permission.inspect }
      add_authorization_rule(:permission, permission.to_sym, only:, except:)
    end

    def allow_any_member(only: nil, except: nil) = add_authorization_rule(:member, nil, only:, except:)

    def allow_without_business(only: nil, except: nil) = add_authorization_rule(:anyone, nil, only:, except:)

    private

    def add_authorization_rule(kind, permission, only:, except:)
      self.authorization_rules = authorization_rules + [ Rule.new(kind:, permission:, only: only && Array(only).map(&:to_s), except: except && Array(except).map(&:to_s)) ]
    end
  end

  private

  def can?(permission) = Current.membership&.can?(permission) || false

  # The most specific rules win: a rule naming this action beats a controller-wide one.
  def authorize_action!
    rules = authorization_rules.select { _1.applies?(action_name) }
    specific = rules.select(&:only)
    rules = specific if specific.any?
    return deny!(nil, "no authorization rule") if rules.empty?
    return if rules.any? { _1.kind == :anyone }
    return deny!(nil, "no current business") unless Current.membership&.active?
    return if rules.any? { _1.kind == :member }

    missing = rules.reject { can?(_1.permission) }
    deny!(missing.first.permission, "role #{Current.membership.role}") if missing.any?
  end

  # Logged with ids only, never names or emails.
  def deny!(permission, reason)
    Rails.logger.warn("[authz] denied #{controller_path}##{action_name} permission=#{permission.inspect} " \
                      "user=#{current_user&.id} business=#{Current.business&.id} (#{reason})")
    respond_to do |format|
      format.html { render "admin/shared/not_allowed", status: :forbidden, layout: "app" }
      format.any { head :forbidden }
    end
  end
end
