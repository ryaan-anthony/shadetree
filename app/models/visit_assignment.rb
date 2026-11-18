# JOB-02: a team member going on a visit (any role).
class VisitAssignment < ApplicationRecord
  include BusinessOwned

  belongs_to_business_record :visit
  belongs_to :user

  before_validation { self.business ||= visit&.business }
end
