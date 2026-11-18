require "test_helper"

# JOB-04: photos from site: one at a time from the day view or several from the plain form,
# cleaned of their metadata, limited, and seen by the office.
class Admin::MyVisitPhotosTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @tech = member_with_role(:technician)
    @owner = users(:one)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client: maria, title: "Spring cleanup")
      @visit = @job.visits.new(scheduled_on: @business.today, assignee_ids: [ @tech.id ]).tap { _1.schedule!(by: @owner) }
      @not_mine = @job.visits.new(scheduled_on: @business.today, assignee_ids: [ @owner.id ]).tap { _1.schedule!(by: @owner) }
    end
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def photo(name = "yard.png")
    tagged = Vips::Image.new_from_file(file_fixture("logo.png").to_s).mutate { _1.set_type!(GObject::GSTR_TYPE, "png-comment-0-gps", "40.7,-74.0") }
    path = Rails.root.join("tmp", name).to_s
    tagged.write_to_file(path)
    Rack::Test::UploadedFile.new(path, "image/png", original_filename: name)
  end

  def photos = as_business(@business) { @visit.reload.photos.to_a }

  test "one photo at a time from the day view gets its thumbnail back; metadata is removed" do
    get admin_my_visit_path(@visit)
    assert_select "#photos input[type=file][capture=environment][multiple]"
    assert_select "[data-controller=photo-upload][data-photo-upload-url-value=?]", admin_my_visit_photos_path(@visit)

    post admin_my_visit_photos_path(@visit), params: { photos: [ photo ] }, xhr: true
    assert_response :created
    assert_select "li img[alt='Photo from the visit']"
    stored = Vips::Image.new_from_buffer(photos.sole.download, "")
    assert_not_includes stored.get_fields, "png-comment-0-gps"
    assert_equal @tech.id, photos.sole.blob.metadata["uploaded_by"]
  end

  test "the plain form takes several, and problems are explained" do
    post admin_my_visit_photos_path(@visit), params: { photos: [ photo("a.png"), photo("b.png") ] }
    assert_redirected_to admin_my_visit_path(@visit, anchor: "photos")
    assert_equal "2 photos added.", flash[:notice]

    post admin_my_visit_photos_path(@visit), params: { photos: [ Rack::Test::UploadedFile.new(StringIO.new("not an image"), "image/png", original_filename: "notes.txt") ] }, xhr: true
    assert_response :unprocessable_content
    assert_match "notes.txt", response.body
    assert_equal 2, photos.size
  end

  test "a visit has at most #{Visit::MAX_PHOTOS} photos" do
    stub = photo
    as_business(@business) { Visit::MAX_PHOTOS.times { |i| @visit.photos.attach(io: File.open(stub.path), filename: "#{i}.png", content_type: "image/png") } }
    post admin_my_visit_photos_path(@visit), params: { photos: [ photo ] }, xhr: true
    assert_response :unprocessable_content
    assert_match "already has #{Visit::MAX_PHOTOS} photos", response.body
    get admin_my_visit_path(@visit)
    assert_select "#photos input[type=file]", 0
  end

  test "photos on someone else's visit can't be added or removed, and the office sees them on the job" do
    post admin_my_visit_photos_path(@not_mine), params: { photos: [ photo ] }, xhr: true
    assert_response :not_found
    post admin_my_visit_photos_path(@visit), params: { photos: [ photo ] }, xhr: true
    attachment = photos.sole
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    delete admin_my_visit_photo_path(@visit, attachment)
    assert_response :not_found, "only the people going manage a visit's photos"
    get admin_job_path(@job)
    assert_select "#visit-#{@visit.uid} img[alt='Photo from the visit']", 1

    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    delete admin_my_visit_photo_path(@visit, attachment)
    assert_redirected_to admin_my_visit_path(@visit, anchor: "photos")
    perform_enqueued_jobs
    assert_empty photos
  end

  test "the app can be installed to the home screen" do
    get admin_my_day_path
    assert_select "link[rel=manifest][href=?]", "/manifest.json"
    get "/manifest.json"
    manifest = JSON.parse(response.body)
    assert_equal [ "Shadetree", "/admin", "standalone" ], manifest.values_at("name", "start_url", "display")
  end
end
