package protocol

import (
	"bytes"
	"encoding/base64"
	"errors"
	"image"
	_ "image/jpeg"
	_ "image/png"
)

const MaxImages = 2
const MaxImageBytes = 256 << 10

// ImageInput is bounded inline content, never a URL or a machine-local path.
// Relay forwards it ephemerally to the runtime and never stores image bytes.
type ImageInput struct {
	MediaType string `json:"media_type"`
	Data      string `json:"data"`
}

func ValidateImages(images []ImageInput) error {
	if len(images) > MaxImages {
		return errors.New("too many images")
	}
	for _, input := range images {
		if len(input.Data) > base64.StdEncoding.EncodedLen(MaxImageBytes) {
			return errors.New("image too large")
		}
		data, err := base64.StdEncoding.Strict().DecodeString(input.Data)
		if err != nil || len(data) == 0 || len(data) > MaxImageBytes {
			return errors.New("invalid image data")
		}
		config, format, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || config.Width < 1 || config.Height < 1 || config.Width > 4096 || config.Height > 4096 {
			return errors.New("invalid image dimensions")
		}
		if (format != "jpeg" && format != "png") || input.MediaType != "image/"+format {
			return errors.New("unsupported image format")
		}
	}
	return nil
}
