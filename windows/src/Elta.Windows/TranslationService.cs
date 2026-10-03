using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// C1：OpenAI 兼容 Chat Completions 请求。请求体/结果分类用 Core TranslationLogic（有单测），
    /// 这里只管传输。取消语义对齐 mac：新请求取消旧请求（旧结果由调用方按 Cancelled 忽略）。
    /// </summary>
    public sealed class TranslationService
    {
        private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(120) };

        private CancellationTokenSource? _cts;

        public async Task<TranslationOutcome> TranslateAsync(string text, SettingsManager settings)
        {
            AIProvider provider = settings.ApiProvider;
            string? key = settings.ActiveApiKey;
            if (string.IsNullOrEmpty(key)) return TranslationOutcome.MissingKey;

            string body = TranslationLogic.BuildChatBody(
                provider, settings.EffectiveModel(provider), settings.SystemPrompt, text);

            using var request = new HttpRequestMessage(HttpMethod.Post, AIProviders.Endpoint(provider))
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);

            _cts?.Cancel();
            var cts = new CancellationTokenSource();
            _cts = cts;

            try
            {
                using HttpResponseMessage resp = await Http.SendAsync(request, cts.Token);
                byte[] data = await resp.Content.ReadAsByteArrayAsync(cts.Token);
                string? parsed = ResponseParser.Parse(data);
                Log.Info($"translate http={(int)resp.StatusCode} chars={parsed?.Length ?? 0}");
                return TranslationLogic.Classify((int)resp.StatusCode, parsed);
            }
            catch (OperationCanceledException)
            {
                Log.Info("translate cancelled");
                return TranslationOutcome.Cancelled;
            }
            catch (Exception ex)
            {
                Log.Error("translate failed", ex);
                return TranslationOutcome.Failure;
            }
            finally
            {
                if (ReferenceEquals(_cts, cts)) _cts = null;
                cts.Dispose();
            }
        }
    }
}
