#include "camera_image_reader_impl.h"

namespace esphome {
namespace camera {

void CameraImageReaderImpl::set_image(std::shared_ptr<CameraImage> image) {
  this->image_ = image;
  this->offset_ = 0;
}

size_t CameraImageReaderImpl::available() const {
  if (!this->image_)
    return 0;

  return this->image_->get_data_length() - this->offset_;
}

uint8_t *CameraImageReaderImpl::peek_data_buffer() { return this->image_->get_data_buffer() + this->offset_; }

void CameraImageReaderImpl::consume_data(size_t consumed) { this->offset_ += consumed; }

void CameraImageReaderImpl::return_image() { this->image_.reset(); }

}  // namespace camera
}  // namespace esphome
