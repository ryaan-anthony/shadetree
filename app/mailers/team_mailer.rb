# The base for email to a business's team members: one email per member, so addresses aren't
# shared. Who gets which email is decided by NotificationType.deliver (NTF-02).
class TeamMailer < ApplicationMailer
  helper FormattingHelper
end
