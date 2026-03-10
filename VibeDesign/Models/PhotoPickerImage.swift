import PhotosUI
import SwiftUI

/// A Transferable wrapper that loads picker items as raw image data,
/// handling HEIC, HEIF, WebP, PNG, and JPEG automatically.
struct PhotoPickerImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PhotoPickerImage(data: data)
        }
    }
}
