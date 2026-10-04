using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>C3：设置窗口「测试连接」。10s 超时；取消/网络错误与 HTTP 分类分开返回。</summary>
    public sealed class ConnectionProbe
    {
        private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };

        private CancellationTokenSource? _cts;

        public async Task<ConnectionProbeResult> TestAsync(string endpoint, string model, string key)
        {
            _cts?.Cancel();
            var cts = new CancellationTokenSource();
            _cts = cts;

            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
                {
                    Content = new StringContent(
                        TranslationLogic.BuildProbeBody(model), Encoding.UTF8, "application/json"),
                };
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);

                using HttpResponseMessage resp = await Http.SendAsync(request, cts.Token);
                int code = (int)resp.StatusCode;
                Log.Info($"probe http={code}");
                return new ConnectionProbeResult(ConnectionResult.Classify(code), null, false);
            }
            catch (OperationCanceledException)
            {
                return new ConnectionProbeResult(null, null, true);
            }
            catch (Exception ex)
            {
                Log.Warn("probe failed: " + ex.Message);
                return new ConnectionProbeResult(null, ex.Message, false);
            }
            finally
            {
                if (ReferenceEquals(_cts, cts)) _cts = null;
                cts.Dispose();
            }
        }
    }

    /// <summary>Result=HTTP 分类结果；Error=网络/客户端错误；Cancelled=被新测试取代（静默）。</summary>
    public sealed record ConnectionProbeResult(ConnectionResult? Result, string? Error, bool Cancelled);
}
