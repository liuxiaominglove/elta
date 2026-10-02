using System;
using System.Threading;
using System.Threading.Tasks;

namespace Elta.Windows
{
    /// <summary>
    /// 在专用 STA 工作线程上执行并返回 Task。
    /// 用途：WinForms 剪贴板要求 STA；取词/合成 Ctrl+C 不能阻塞 UI 线程（WI-3）。
    /// 线程为后台线程，进程退出不被它阻塞。
    /// </summary>
    internal static class StaRunner
    {
        public static Task<T> RunAsync<T>(Func<T> work)
        {
            var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
            var thread = new Thread(() =>
            {
                try { tcs.SetResult(work()); }
                catch (Exception ex) { tcs.SetException(ex); }
            })
            {
                IsBackground = true,
                Name = "EltaStaWorker",
            };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            return tcs.Task;
        }
    }
}
