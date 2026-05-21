#pragma once

#include "camera.h"

namespace esphome {
namespace camera {

/** Camera image reader interface implemenation.
 */
class CameraImageReaderImpl : public CameraImageReader {
 public:
  // ---- CameraImageReader interface ----
  void set_image(std::shared_ptr<CameraImage> image) override;
  size_t available() const override;
  uint8_t *peek_data_buffer() override;
  void consume_data(size_t consumed) override;
  void return_image() override;
  // -------------------------------------
 protected:
  std::shared_ptr<CameraImage> image_;
  size_t offset_{0};
};

}  // namespace camera
}  // namespace esphome
