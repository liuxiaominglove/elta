using System;
using System.Net.Http;
using System.Threading.Tasks;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// C4b/C4c：更新检查网络层（解析/比较/URL 构造用 Core UpdateLogic，有单测）。
    /// 遥测 = 开启统计时请求带 ?id=installID（服务端按 id 去重计日活）；日志只记 withId 布尔，不打印 id 值。
    /// </summary>
    public sealed class UpdateService
    {
        private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };

        public async Task<UpdateInfo?> CheckAsync(SettingsManager settings, string currentVersion)
        {
            string url = UpdateLogic.BuildUpdateUrl(settings.TelemetryEnabled, settings.InstallId);
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                request.Headers.UserAgent.ParseAdd($"ELTA/{currentVersion}");

                using HttpResponseMessage resp = await Http.SendAsync(request);
                if ((int)resp.StatusCode != 200)
                {
                    Log.Info($"update check http={(int)resp.StatusCode}");
                    return null;
                }
                string body = await resp.Content.ReadAsStringAsync();
                UpdateInfo? info = UpdateLogic.ParseUpdateResponse(body);
                if (info is null)
                {
                    Log.Info("update check parse=null");
                }
                else
                {
                    string platformLabel = info.Platform ?? "none";
                    Log.Info($"update check remote={info.Version} platform={platformLabel} withId={settings.TelemetryEnabled}");
                }
                return info;
            }
            catch (Exception ex)
            {
                Log.Error("update check failed", ex);
                return null;
            }
        }
    }
}
