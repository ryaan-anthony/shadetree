# Include in every model whose rows belong to one business (clients, quotes, jobs, …).
#
#   class Client < ApplicationRecord
#     include BusinessOwned                 # needs business_id and uid columns
#     belongs_to_business_record :referrer, class_name: "Client", optional: true
#   end
#
# - Every query is scoped to Current.business; with none set it raises
#   Tenancy::NoBusinessError instead of returning another business's rows.
# - New records take Current.business, and can't be saved into a different one.
# - Records referenced by id from forms must belong to the same business
#   (belongs_to_business_record validates it), so guessing ids gets "not found".
# - URLs use an opaque `uid`, not the sequential id (ADR 0014): `to_param` returns it and
#   `find_by_param!` looks it up within the business.
module BusinessOwned
  extend ActiveSupport::Concern

  UID_LENGTH = 12

  included do
    belongs_to :business

    default_scope do
      if Tenancy.across_businesses?
        all
      elsif Current.business
        where(business_id: Current.business.id)
      else
        raise Tenancy::NoBusinessError, self
      end
    end

    before_validation { self.business ||= Current.business }
    before_validation { self.uid ||= SecureRandom.base58(UID_LENGTH) if new_record? && has_attribute?(:uid) }
    validate :business_matches_current, if: :new_record? # every context, including custom ones
    attr_readonly :business_id
  end

  class_methods do
    # A belongs_to whose target must be in the same business. Use it for every association
    # a form can set by id.
    def belongs_to_business_record(name, **options)
      belongs_to(name, **options)
      validate do
        record = public_send(name)
        errors.add(name, :invalid, message: "isn't available") if record && record.business_id != business_id
      end
    end

    def find_by_param!(param) = find_by!(uid: param.to_s)
  end

  def to_param = uid

  private

  def business_matches_current
    return if Tenancy.across_businesses? || Current.business.nil? || business_id == Current.business.id

    errors.add(:business, "doesn't match the current business")
  end
end
