# JOB-04: a note on a visit from someone going ("Side gate was locked; came back at 2"),
# seen by the office on the job page and by the crew on the visit.
class VisitNote < ApplicationRecord
  include BusinessOwned

  belongs_to_business_record :visit
  belongs_to :user, optional: true

  normalizes :body, with: ->(value) { value.to_s.strip }

  validates :body, presence: { message: "Write something first." }, length: { maximum: 2_000 }

  before_validation { self.business ||= visit&.business }
end
