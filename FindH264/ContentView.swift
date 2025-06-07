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

enum SortType: String, CaseIterable, Identifiable {
    case date = "По дате"
    case size = "По размеру"
    case duration = "По длительности"
    var id: String { self.rawValue }
}

// Функция форматирования размера файла, доступна во всём файле
func formatFileSize(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
}

struct ContentView: View {
    @State private var h264Videos: [PHAsset] = []
    @State private var isAuthorized = false
    @State private var isLoading = false
    @State private var selectedVideo: PHAsset?
    @State private var showingVideoPreview = false
    @State private var sortType: SortType = .date
    @State private var fileSizes: [String: Int64] = [:] // localIdentifier -> size

    var sortedVideos: [PHAsset] {
        switch sortType {
        case .date:
            return h264Videos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        case .size:
            return h264Videos.sorted { (fileSizes[$0.localIdentifier] ?? 0) > (fileSizes[$1.localIdentifier] ?? 0) }
        case .duration:
            return h264Videos.sorted { $0.duration > $1.duration }
        }
    }

    var totalSize: Int64 {
        sortedVideos.reduce(0) { $0 + (fileSizes[$1.localIdentifier] ?? 0) }
    }

    var body: some View {
        NavigationView {
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
                VStack(spacing: 8) {
                    // Информация о количестве и размере
                    Text("Видео: \(sortedVideos.count), общий размер: \(formatFileSize(totalSize))")
                        .font(.subheadline)
                        .padding(.top)
                    Picker("Сортировка", selection: $sortType) {
                        ForEach(SortType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                    List(sortedVideos, id: \.localIdentifier) { asset in
                        VideoRow(asset: asset, fileSizes: $fileSizes)
                            .onTapGesture {
                                selectedVideo = asset
                                showingVideoPreview = true
                            }
                    }
                    .listStyle(.plain)
                }
                .navigationTitle("H264 Видео")
                .sheet(isPresented: $showingVideoPreview) {
                    if let asset = selectedVideo {
                        VideoPreviewView(asset: asset)
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
    @Binding var fileSizes: [String: Int64]
    @State private var fileSize: Int64 = 0

    var body: some View {
        HStack {
            VideoThumbnail(asset: asset)
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Видео")
                    .font(.headline)
                Text("Длительность: \(formatDuration(asset.duration))")
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
                fileSizes[asset.localIdentifier] = self.fileSize
            }
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Неизвестная дата" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%d сек", seconds)
        }
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
