using System;
using System.Collections.Generic;
using System.Windows.Threading;

namespace Elta.Windows
{
    /// <summary>
    /// WI-4：全局热键注册与**自愈**。RegisterHotKey 失败（被其他程序占用）时每 10s 重试，
    /// 占用解除后自动恢复；状态变化通知调用方（用于更新托盘提示）。
    /// 计时器用 <see cref="DispatcherTimer"/>，确保在 UI 线程创建与回调。
    /// </summary>
    internal sealed class HotkeyManager : IDisposable
    {
        private sealed class Spec
        {
            public int Id;
            public uint Modifiers;
            public uint Vk;
            public Action OnTriggered = () => { };
            public string Name = string.Empty;
            public bool Ok;
        }

        private static readonly TimeSpan RetryInterval = TimeSpan.FromSeconds(10);

        private readonly HotkeyHost _host = new();
        private readonly List<Spec> _specs = new();
        private readonly DispatcherTimer _retry;
        private bool _disposed;

        /// <summary>热键注册状态变化（全部就绪或发生恢复）时触发；在 UI 线程回调。</summary>
        public event Action? StatusChanged;

        public HotkeyManager()
        {
            _retry = new DispatcherTimer { Interval = RetryInterval };
            _retry.Tick += (_, _) => Retry();
        }

        public void Add(int id, uint modifiers, uint vk, Action onTriggered, string name)
            => _specs.Add(new Spec { Id = id, Modifiers = modifiers, Vk = vk, OnTriggered = onTriggered, Name = name });

        public void RegisterAll()
        {
            foreach (Spec spec in _specs) TryRegister(spec);
            UpdateTimer();
            StatusChanged?.Invoke();
        }

        public bool AllRegistered
        {
            get
            {
                foreach (Spec spec in _specs)
                    if (!spec.Ok) return false;
                return true;
            }
        }

        public IReadOnlyList<string> PendingNames
        {
            get
            {
                var names = new List<string>();
                foreach (Spec spec in _specs)
                    if (!spec.Ok) names.Add(spec.Name);
                return names;
            }
        }

        private void TryRegister(Spec spec)
        {
            if (spec.Ok) return;
            if (_host.Register(spec.Id, spec.Modifiers, spec.Vk, spec.OnTriggered))
            {
                spec.Ok = true;
                Log.Info($"hotkey registered name={spec.Name} id={spec.Id}");
            }
            else
            {
                Log.Warn($"hotkey busy name={spec.Name} id={spec.Id}");
            }
        }

        private void Retry()
        {
            bool recovered = false;
            foreach (Spec spec in _specs)
            {
                if (spec.Ok) continue;
                TryRegister(spec);
                if (spec.Ok) recovered = true;
            }
            UpdateTimer();
            if (recovered)
            {
                Log.Info("hotkey recovered");
                StatusChanged?.Invoke();
            }
        }

        private void UpdateTimer()
        {
            if (AllRegistered) _retry.Stop();
            else if (!_retry.IsEnabled) _retry.Start();
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _retry.Stop();
            _host.Dispose();
        }
    }
}
