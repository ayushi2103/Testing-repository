//
//  jtImage.swift
//  imagenetteBenchmark
//
//  Created by Ayush Agrawal on 12/06/20.
//  Copyright © 2020 Ayush Agrawal. All rights reserved.
//

import Foundation
import TensorFlow
import libjpeg
import ModelSupport

public struct jtImage {
    public enum ByteOrdering {
        case bgr
        case rgb
    }

    public enum Colorspace {
        case rgb
        case grayscale
    }

    enum ImageTensor {
        case float(data: Tensor<Float>)
        case uint8(data: Tensor<UInt8>)
    }

    let imageTensor: ImageTensor
    let imageData: ImageData

    public var tensor: Tensor<Float> {
        switch self.imageTensor {
        case let .float(data): return data
        case let .uint8(data): return Tensor<Float>(data)
        }
    }

    public init(tensor: Tensor<UInt8>, data: ImageData) {
        self.imageTensor = .uint8(data: tensor)
        self.imageData = data
    }

    public init(tensor: Tensor<Float>, data: ImageData) {
        self.imageTensor = .float(data: tensor)
        self.imageData = data
    }

    public init(jpeg url: URL, byteOrdering: ByteOrdering = .rgb) {
        if byteOrdering == .bgr {
            // TODO: Add BGR byte reordering.
            fatalError("BGR byte ordering is currently unsupported.")
        } else {
            guard FileManager.default.fileExists(atPath: url.path) else {
                // TODO: Proper error propagation for this.
                fatalError("File does not exist at: \(url.path).")
            }
            
            guard let loadedData = LoadJPEG(atPath: url.path) else {
                // TODO: Proper error propagation for this.
                fatalError("Unable to read image at: \(url.path).")
            }
            
            self.imageData = loadedData
            let data = [UInt8](UnsafeBufferPointer(start: self.imageData.data, count: Int(self.imageData.width * self.imageData.height * 3)))
            var loadedTensor = Tensor<UInt8>(
                shape: [Int(self.imageData.height), Int(self.imageData.width), 3], scalars: data)
            self.imageTensor = .uint8(data: loadedTensor)
        }
    }

    public func save(to url: URL, format: Colorspace = .rgb, quality: Int64 = 95) {
        let outputImageData: Tensor<UInt8>
        let bpp: Int32

        switch format {
        case .grayscale:
            bpp = 1
            switch self.imageTensor {
            case let .uint8(data): outputImageData = data
            case let .float(data):
                let lowerBound = data.min(alongAxes: [0, 1])
                let upperBound = data.max(alongAxes: [0, 1])
                let adjustedData = (data - lowerBound) * (255.0 / (upperBound - lowerBound))
                outputImageData = Tensor<UInt8>(adjustedData)
            }
        case .rgb:
            bpp = 3
            switch self.imageTensor {
            case let .uint8(data): outputImageData = data
            case let .float(data):
                outputImageData = Tensor<UInt8>(data.clipped(min: 0, max: 255))
            }
        }
        
        let status = SaveJPEG(atPath: url.path, image: self.imageData)
        guard status == 0 else {
            // TODO: Proper error propagation for this.
            fatalError("Unable to save image to: \(url.path).")
        }
    }

    public func resized(to size: (Int, Int)) -> jtImage {
        switch self.imageTensor {
        case let .uint8(data):
            let resizedImage = resize(images: Tensor<Float>(data), size: size, method: .bilinear)
            return jtImage(tensor: Tensor<UInt8>(resizedImage), data: self.imageData)
        case let .float(data):
            let resizedImage = resize(images: data, size: size, method: .bilinear)
            return jtImage(tensor: resizedImage, data: self.imageData)
        }
    }
}

public func saveImage(
    _ tensor: Tensor<Float>, _ data: ImageData, shape: (Int, Int), size: (Int, Int)? = nil,
    format: jtImage.Colorspace = .rgb, directory: String, name: String,
    quality: Int64 = 95
) throws {
    try createDirectoryIfMissing(at: directory)

    let channels: Int
    switch format {
    case .rgb: channels = 3
    case .grayscale: channels = 1
    }

    let reshapedTensor = tensor.reshaped(to: [shape.0, shape.1, channels])
    let image = jtImage(tensor: reshapedTensor, data: data)
    let resizedImage = size != nil ? image.resized(to: (size!.0, size!.1)) : image
    let outputURL = URL(fileURLWithPath: "\(directory)\(name).jpg")
    resizedImage.save(to: outputURL, format: format, quality: quality)
}