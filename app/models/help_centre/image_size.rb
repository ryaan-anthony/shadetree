# OPS-06: a help image's width and height, read from the file's header (libvips reads only the
# header), so the page keeps its place while the picture loads.
module HelpCentre::ImageSize
  @sizes = Concurrent::Map.new

  def self.of(path)
    @sizes.compute_if_absent([ path.to_s, File.mtime(path) ]) do
      require "vips"
      image = Vips::Image.new_from_file(path.to_s)
      [ image.width, image.height ]
    end
  end
end
