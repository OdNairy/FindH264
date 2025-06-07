//
//  ContentView.swift
//  FindH264
//
//  Created by odnairy on 7.6.2025.
//

import SwiftUI
import Photos
import AVFoundation
import UIKit

struct ContentView: View {
    @State private var h264Videos: [PHAsset] = []
    @State private var isAuthorized = false
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            Group {
                if !isAuthorized {
                    VStack {
                        Text("Доступ к фотографиям не разрешен")
                            .font(.headline)
                        Button("Запросить доступ") {
                            requestPhotoLibraryAccess()
                        }
                        .padding()
                    }
                } else if isLoading {
                    ProgressView("Поиск видео...")
                } else {
                    List(h264Videos, id: \.localIdentifier) { asset in
                        VideoRow(asset: asset)
                    }
                    .navigationTitle("H264 Видео")
                }
            }
        }
        .onAppear {
            checkPhotoLibraryAuthorization()
        }
    }

    private func checkPhotoLibraryAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        isAuthorized = status == .authorized
        if isAuthorized {
            findH264Videos()
        }
    }

    private func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                isAuthorized = status == .authorized
                if isAuthorized {
                    findH264Videos()
                }
            }
        }
    }

    private func findH264Videos() {
        isLoading = true

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)

        let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)

        fetchResult.enumerateObjects { asset, index, stop in
            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources {
                if resource.uniformTypeIdentifier == "public.mpeg-4" {
                    DispatchQueue.main.async {
                        h264Videos.append(asset)
                    }
                }
            }
        }

        DispatchQueue.main.async {
            isLoading = false
        }
    }
}

struct VideoRow: View {
    let asset: PHAsset

    var body: some View {
        HStack {
            VideoThumbnail(asset: asset)
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading) {
                Text("Видео")
                    .font(.headline)
                Text("Длительность: \(Int(asset.duration)) сек")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct VideoThumbnail: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        option.isSynchronous = false
        option.deliveryMode = .highQualityFormat

        manager.requestImage(for: asset,
                           targetSize: CGSize(width: 200, height: 200),
                           contentMode: .aspectFill,
                           options: option) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.thumbnail = image
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
