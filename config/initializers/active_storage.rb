# Uploads go through the app's own forms (e.g. the logo, CAT-02), which validate and clean
# the file. Direct uploads would let anyone create blobs with no such checks, so they're off.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.before_action { head :not_found }
end
