namespace Elta.Core
{
    // MARK: - 连接测试结果分类

    public enum ConnectionResultKind
    {
        Success,
        AuthFailure,
        ServerError,
    }

    /// <summary>「测试连接」HTTP 状态码分类。移植自 macOS 版 ConnectionResult。</summary>
    public sealed record ConnectionResult(ConnectionResultKind Kind, int Code)
    {
        public static ConnectionResult Classify(int code)
        {
            if (code >= 200 && code < 300) return new ConnectionResult(ConnectionResultKind.Success, code);
            if (code == 401 || code == 403) return new ConnectionResult(ConnectionResultKind.AuthFailure, code);
            return new ConnectionResult(ConnectionResultKind.ServerError, code);
        }
    }

    /// <summary>「测试连接」实际应使用的 endpoint 与 model。</summary>
    public sealed record ResolvedConnectionTarget(string Endpoint, string Model);

    public static class ConnectionTarget
    {
        /// <summary>
        /// 优先用输入框键入的模型（用户刚改、尚未保存），为空才回退到生效默认模型。
        /// </summary>
        public static ResolvedConnectionTarget Resolve(string? modelInput, AIProvider provider, string effectiveDefaultModel)
        {
            string endpoint = AIProviders.Endpoint(provider);
            string? trimmed = modelInput?.Trim();
            string model = !string.IsNullOrEmpty(trimmed) ? trimmed! : effectiveDefaultModel;
            return new ResolvedConnectionTarget(endpoint, model);
        }
    }

    // MARK: - 模板双态保存决策

    public enum TemplateSaveActionKind
    {
        KeepDefault,
        SaveCustom,
        ClearCustom,
    }

    public sealed record TemplateSaveAction(TemplateSaveActionKind Kind, string? Content = null)
    {
        public static TemplateSaveAction KeepDefault { get; } = new TemplateSaveAction(TemplateSaveActionKind.KeepDefault);
        public static TemplateSaveAction ClearCustom { get; } = new TemplateSaveAction(TemplateSaveActionKind.ClearCustom);
        public static TemplateSaveAction SaveCustom(string content) => new TemplateSaveAction(TemplateSaveActionKind.SaveCustom, content);
    }

    public static class TemplateLogic
    {
        /// <summary>模板编辑视图应显示的内容：自定义态且有自定义内容 → 自定义；否则内置默认。</summary>
        public static string Content(bool usesDefault, string? custom, string defaultPrompt)
            => (!usesDefault && !string.IsNullOrEmpty(custom)) ? custom! : defaultPrompt;

        /// <summary>保存时的决策：根据当前态与编辑内容，决定写什么状态。</summary>
        public static TemplateSaveAction ResolveSave(bool usesDefault, string content)
        {
            if (usesDefault) return TemplateSaveAction.KeepDefault;
            if (string.IsNullOrWhiteSpace(content)) return TemplateSaveAction.ClearCustom;
            return TemplateSaveAction.SaveCustom(content);
        }
    }
}
