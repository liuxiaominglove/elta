import Cocoa
import Vision

// MARK: - OCR 引擎（Vision Framework）

final class OCREngine {
    static let shared = OCREngine()

    // MARK: - 纯文本（保持后向兼容）
    func recognize(cgImage: CGImage) -> String? {
        guard let blocks = recognizeWithPositions(cgImage: cgImage) else { return nil }
        let text = blocks.map { $0.text }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 含坐标的识别（用于表格还原）
    func recognizeWithPositions(cgImage: CGImage) -> [OCRBlock]? {
        logi("OCR: CGImage \(cgImage.width)x\(cgImage.height) px, alpha=\(cgImage.alphaInfo.rawValue)")

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        let semaphore = DispatchSemaphore(value: 0)
        var blocks: [OCRBlock]?

        let request = VNRecognizeTextRequest { (req, error) in
            defer { semaphore.signal() }
            if let e = error { loge("OCR Vision 错误: \(e.localizedDescription)"); return }
            guard let obs = req.results as? [VNRecognizedTextObservation] else { return }

            var results: [OCRBlock] = []
            for ob in obs {
                guard let candidate = ob.topCandidates(1).first else { continue }

                // Vision 的 boundingBox 是归一化 [0,1]，原点在左下角
                // 转换为像素坐标，原点改为左上角
                let box = ob.boundingBox
                let x = box.origin.x * imgW
                let y = (1.0 - box.origin.y - box.height) * imgH  // 翻转 Y 轴
                let w = box.width * imgW
                let h = box.height * imgH

                results.append(OCRBlock(
                    text: candidate.string,
                    boundingBox: CGRect(x: x, y: y, width: w, height: h)
                ))
            }
            blocks = results
            logi("OCR: 识别到 \(results.count) 块文本（含坐标）")
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

        return blocks
    }
}
