# JOB-09: the log of work done on a job line, from a visit (My day) or the office: whose work,
# which visit, who typed it and when, and the line's name, so removing the line keeps its log. Entries are only ever added: a correction is another entry
# (a negative quantity takes some back), and a line's done quantity is the sum. JOB-11 writes its
# tracked hours here too (source "time"), so billing reads one ledger.
class WorkEntry < ApplicationRecord
  include BusinessOwned

  SOURCES = %w[logged time].freeze

  belongs_to :job
  belongs_to :job_line_item, optional: true # a line removed from the job keeps its log (item_name)
  belongs_to :visit, optional: true
  belongs_to :user
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :quantity, numericality: { greater_than: -1_000_000, less_than: 1_000_000 }

  before_validation { self.business ||= job&.business }
  before_validation { self.item_name ||= job_line_item&.name }

  def readonly? = persisted?
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Work entries are kept: add a correction instead." }
end
