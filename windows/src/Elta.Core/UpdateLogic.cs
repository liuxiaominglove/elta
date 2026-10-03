using System;
using System.Collections.Generic;
using System.Text.Json;

namespace Elta.Core
{
    /// <summary>更新信息（对齐 mac parseUpdateResponse 的返回语义）。</summary>
    public sealed record UpdateInfo(string Version, string Url);

    /// <summary>
    /// 更新检查纯逻辑（移植自 macOS 版 UpdateChecker）：响应解析 / 版本比较 / 跳过判断 / URL 构造。
    /// 网络与 UI 在外壳；遥测 = 同一请求带 ?id=（服务端按 id 去重计日活，见 server/server.py）。
    /// </summary>
    public static class UpdateLogic
    {
        public const string UpdateUrl = "https://autoelta.com/api/update";
        public const string DownloadPageUrl = "https://autoelta.com/";

        /// <summary>解析自建更新端点：{"version":"5.6.0","url":"..."}；不合法（缺字段/空值/非 JSON/非 http(s)）返回 null。</summary>
        public static UpdateInfo? ParseUpdateResponse(string? json)
        {
            if (string.IsNullOrEmpty(json)) return null;
            try
            {
                using JsonDocument doc = JsonDocument.Parse(json!);
                if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
                if (!doc.RootElement.TryGetProperty("version", out JsonElement vEl) || vEl.ValueKind != JsonValueKind.String) return null;
                if (!doc.RootElement.TryGetProperty("url", out JsonElement uEl) || uEl.ValueKind != JsonValueKind.String) return null;

                string version = vEl.GetString() ?? "";
                string url = uEl.GetString() ?? "";
                if (version.StartsWith("v")) version = version.Substring(1);
                if (version.Length == 0 || url.Length == 0) return null;
                if (!IsHttpUrl(url)) return null;
                return new UpdateInfo(version, url);
            }
            catch (JsonException)
            {
                return null;
            }
        }

        /// <summary>数字段比较（对齐 mac：非数字段被丢弃；缺位补 0，如 5.6 == 5.6.0）。</summary>
        public static bool IsNewer(string remote, string local)
        {
            int[] rv = VersionParts(remote);
            int[] lv = VersionParts(local);
            int maxLen = Math.Max(rv.Length, lv.Length);
            for (int i = 0; i < maxLen; i++)
            {
                int r = i < rv.Length ? rv[i] : 0;
                int l = i < lv.Length ? lv[i] : 0;
                if (r > l) return true;
                if (r < l) return false;
            }
            return false;
        }

        /// <summary>远程较新且未被用户跳过 → 提示更新。</summary>
        public static bool ShouldShowUpdate(string remoteVersion, string localVersion, string? skipVersion)
            => IsNewer(remoteVersion, localVersion) && skipVersion != remoteVersion;

        /// <summary>更新检查 URL：开启匿名统计时附带 installID（该请求即遥测计数），否则不带。</summary>
        public static string BuildUpdateUrl(bool telemetryEnabled, string installId)
            => telemetryEnabled ? UpdateUrl + "?id=" + installId : UpdateUrl;

        /// <summary>协议白名单：只接受 http/https 且 host 非空（打开链接前二次校验复用）。</summary>
        public static bool IsHttpUrl(string? url)
        {
            if (string.IsNullOrEmpty(url)) return false;
            if (!Uri.TryCreate(url, UriKind.Absolute, out Uri? uri)) return false;
            string scheme = uri.Scheme.ToLowerInvariant();
            if (scheme != "http" && scheme != "https") return false;
            return !string.IsNullOrEmpty(uri.Host);
        }

        private static int[] VersionParts(string v)
        {
            var parts = new List<int>();
            foreach (string seg in v.Split('.'))
                if (int.TryParse(seg, out int n)) parts.Add(n);
            return parts.ToArray();
        }
    }
}
