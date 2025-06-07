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
import AVKit

struct ContentView: View {
    @State private var h264Videos: [PHAsset] = []
    @State private var isAuthorized = false
    @State private var isLoading = false
    @State private var selectedVideo: PHAsset?
    @State private var showingVideoPreview = false

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
                            .onTapGesture {
                                selectedVideo = asset
                                showingVideoPreview = true
                            }
                    }
                    .navigationTitle("H264 Видео")
                    .sheet(isPresented: $showingVideoPreview) {
                        if let asset = selectedVideo {
                            VideoPreviewView(asset: asset)
                        }
                    }
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
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: .video, options: fetchOptions)

        // Prefetch metadata
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true

        fetchResult.enumerateObjects { asset, index, stop in
            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources {
                if resource.uniformTypeIdentifier == "public.mpeg-4" {
                    // Prefetch metadata
                    PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { _, _, _, _ in }

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
    @State private var fileSize: Int64 = 0

    var body: some View {
        HStack {
            VideoThumbnail(asset: asset)
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Видео")
                    .font(.headline)
                Text("Длительность: \(Int(asset.duration)) сек")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Размер: \(formatFileSize(fileSize))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(formatDate(asset.creationDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            getFileSize()
        }
    }

    private func getFileSize() {
        let resources = PHAssetResource.assetResources(for: asset)
        if let videoResource = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo }) {
            if let size = videoResource.value(forKey: "fileSize") as? CLong {
                self.fileSize = Int64(size)
            }
        }
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Неизвестная дата" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

struct VideoPreviewView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack {
                VideoPlayerView(asset: asset)
                    .edgesIgnoringSafeArea(.all)
            }
            .navigationBarItems(trailing: Button("Закрыть") {
                dismiss()
            })
        }
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let asset: PHAsset

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()

        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            if let playerItem = playerItem {
                DispatchQueue.main.async {
                    let player = AVPlayer(playerItem: playerItem)
                    controller.player = player
                    player.play()
                }
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
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
