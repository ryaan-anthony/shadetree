# Uploads go through the app's own forms (e.g. the logo, CAT-02), which validate and clean
# the file. Direct uploads would let anyone create blobs with no such checks, so they're off.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.before_action { head :not_found }
end

# PLT-13: stored files never act as code on our origin. Rails already serves HTML, SVG and XML
# as downloads of plain bytes; scripts and stylesheets join them, since the content security
# policy trusts our own origin for those. (Every upload path re-encodes photos or checks for a
# real PDF, so none of these should be stored at all.)
Rails.application.config.active_storage.content_types_to_serve_as_binary += %w[
  text/javascript application/javascript application/x-javascript application/ecmascript text/ecmascript
  text/x-javascript application/x-ecmascript text/jscript text/livescript text/javascript1.0 text/javascript1.1
  text/javascript1.2 text/javascript1.3 text/javascript1.4 text/javascript1.5
  text/css application/json application/wasm
]
