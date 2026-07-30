import Cocoa
import Vision

// MARK: - OCR 引擎（Vision Framework）

final class OCREngine {
    static let shared = OCREngine()

    func recognize(cgImage: CGImage) -> String? {
        logi("OCR: CGImage \(cgImage.width)x\(cgImage.height) px, alpha=\(cgImage.alphaInfo.rawValue)")

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        let request = VNRecognizeTextRequest { (req, error) in
            defer { semaphore.signal() }
            if let e = error { loge("OCR Vision 错误: \(e.localizedDescription)"); return }
            guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
            let lines = obs.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            result = text.isEmpty ? nil : text
            logi("OCR: 识别到 \(obs.count) 块文本，\(result?.count ?? 0) 字符")
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "en-GB", "zh-Hans", "zh-Hant"]
        request.usesLanguageCorrection = false
        request.revision = VNRecognizeTextRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            semaphore.wait()
        } catch {
            loge("OCR 执行失败: \(error.localizedDescription)")
            return nil
        }

        return result
    }
}
