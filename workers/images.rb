require 'mini_magick'

images = Dir.glob(['../public/logos/*.jpg', '../public/logos/*.jpeg', '../public/logos/*.png', '../public/logos/*.gif', '../public/logos/*.tiff', '../public/logos/*.svg'])

images.each do |image|
  image = MiniMagick::Image.new(image)
  if image.width > 300
    image.resize "300x"
  end
end
